import Foundation
import SwiftUI
import Combine

/// Observable store for managing scans with JSON file persistence
class ScanStore: ObservableObject {
    /// Visible (non-deleted) scans — what the UI binds to.
    @Published var scans: [Scan] = []

    /// Soft-deleted records kept only so the deletion can sync to other devices.
    private var tombstones: [Scan] = []

    /// All records (visible + tombstones) for CloudKit sync.
    var syncRecords: [Scan] { scans + tombstones }

    private let storageDir: URL

    /// Standard init — uses app's Documents directory
    init() {
        self.storageDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        loadScans()
    }

    /// Test-friendly init — custom storage directory + optional seed data
    init(storageDirectory: URL, useSeedData: Bool = false) {
        self.storageDir = storageDirectory
        if useSeedData {
            scans = Self.seedScans
            saveScans()
        } else {
            loadScans()
        }
    }

    // MARK: - CRUD Operations

    func addScan(_ scan: Scan) {
        var s = scan
        s.lastModifiedLocal = Date()
        s.isDeleted = false
        tombstones.removeAll { $0.id == s.id }  // un-tombstone if re-added
        scans.insert(s, at: 0)
        saveScans()
        CloudKitSyncService.shared.save(s)
    }

    func updateScan(_ scan: Scan) {
        var s = scan
        s.lastModifiedLocal = Date()
        if let index = scans.firstIndex(where: { $0.id == s.id }) {
            scans[index] = s
            saveScans()
            CloudKitSyncService.shared.save(s)
        }
    }

    func deleteScan(_ scan: Scan) {
        tombstone(ids: [scan.id])
    }

    func deleteAllScans() {
        tombstone(ids: scans.map { $0.id })
    }

    /// Soft-delete: hide locally, cancel any follow-up, and upload a tombstone so
    /// the deletion syncs to other devices.
    private func tombstone(ids: [UUID]) {
        let idSet = Set(ids)
        let removed = scans.filter { idSet.contains($0.id) }
        guard !removed.isEmpty else { return }
        scans.removeAll { idSet.contains($0.id) }
        for var rec in removed {
            NotificationService.shared.cancelFollowUp(for: rec)
            rec.isDeleted = true
            rec.lastModifiedLocal = Date()
            tombstones.removeAll { $0.id == rec.id }
            tombstones.append(rec)
            CloudKitSyncService.shared.save(rec)
        }
        saveScans()
    }

    /// Apply remote scans from CloudKit — bypasses CloudKit upload to avoid loops.
    @MainActor func applyRemoteScans(_ remoteScans: [Scan]) {
        let previouslyVisible = Set(scans.map { $0.id })
        var byID: [UUID: Scan] = [:]
        for s in scans { byID[s.id] = s }
        for t in tombstones { byID[t.id] = t }
        for remote in remoteScans {
            if let local = byID[remote.id] {
                if cloudKitWins(remote, over: local) { byID[remote.id] = remote }
            } else {
                byID[remote.id] = remote
            }
        }
        let all = Array(byID.values)
        tombstones = all.filter { $0.isDeleted }
        scans = all.filter { !$0.isDeleted }.sorted { $0.timestamp > $1.timestamp }
        // A scan deleted on another device must also cancel this device's
        // pending follow-up notification, or the push fires days later
        // pointing at a record that no longer resolves.
        for tombstone in tombstones where previouslyVisible.contains(tombstone.id) {
            NotificationService.shared.cancelFollowUp(for: tombstone)
        }
        saveScans()
    }

    // MARK: - Persistence

    private var fileURL: URL {
        storageDir.appendingPathComponent("scans.json")
    }

    private func saveScans() {
        do {
            let data = try JSONEncoder().encode(scans + tombstones)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save scans: \(error)")
        }
    }

    /// Decodes element-by-element so one corrupt record is skipped instead of
    /// failing the whole file. Returns nil only when the data isn't a
    /// decodable array at all.
    private static func decodeTolerantly(_ data: Data) -> [Scan]? {
        struct Lossy: Decodable {
            let value: Scan?
            init(from decoder: Decoder) throws { value = try? Scan(from: decoder) }
        }
        guard let lossy = try? JSONDecoder().decode([Lossy].self, from: data) else { return nil }
        let values = lossy.compactMap(\.value)
        if values.count != lossy.count {
            print("ScanStore: skipped \(lossy.count - values.count) corrupt record(s) in scans.json")
        }
        return values
    }

    private func loadScans() {
        let backupURL = storageDir.appendingPathComponent("scans_backup.json")
        guard let data = try? Data(contentsOf: fileURL) else {
            scans = []
            tombstones = []
            return
        }

        var records = Self.decodeTolerantly(data)
        var goodBytes = data
        if records == nil {
            // Keep the corrupt file for forensics, then fall back to the
            // last-known-good backup instead of silently starting empty.
            try? data.write(to: storageDir.appendingPathComponent("scans_corrupt.json"), options: .atomic)
            if let backup = try? Data(contentsOf: backupURL),
               let restored = Self.decodeTolerantly(backup) {
                print("ScanStore: scans.json unreadable — restored from backup")
                records = restored
                goodBytes = backup
                try? backup.write(to: fileURL, options: .atomic)
            }
        }

        guard let all = records else {
            print("ScanStore: scans.json and backup both unreadable — starting empty")
            scans = []
            tombstones = []
            return
        }
        tombstones = all.filter { $0.isDeleted }
        scans = all.filter { !$0.isDeleted }
        // Back up only bytes that decoded successfully (last-known-good).
        try? goodBytes.write(to: backupURL, options: .atomic)
    }

    // MARK: - Queries

    /// Last 5 scans (most recent first, since we insert at front)
    var recentScans: [Scan] {
        Array(scans.prefix(5))
    }

    /// Scans marked "want to try" that haven't been linked to a journal entry yet
    var wantToTryScans: [Scan] {
        scans.filter { $0.wantToTry && $0.linkedJournalId == nil }
    }

    /// Find a scan matching a beer name query
    func findMatch(for query: String) -> Scan? {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespaces)

        if let exact = scans.first(where: { $0.beerName.lowercased().trimmingCharacters(in: .whitespaces) == normalizedQuery }) {
            return exact
        }

        if let contains = scans.first(where: {
            let normalized = $0.beerName.lowercased().trimmingCharacters(in: .whitespaces)
            return normalized.contains(normalizedQuery) || normalizedQuery.contains(normalized)
        }) {
            return contains
        }

        return nil
    }

    /// Inject sample scans for testing. Idempotent — skips any already present by ID.
    /// Seeds are stamped with a far-past `lastModifiedLocal` so a real record always
    /// beats them in last-write-wins (prevents the button from clobbering real iCloud edits).
    func seedSampleData() {
        let existing = Set(scans.map { $0.id })
        let fresh = Self.seedScans.filter { !existing.contains($0.id) }
        guard !fresh.isEmpty else { return }
        for scan in fresh { insertSeed(scan) }
    }

    /// Insert a seed record that can never win last-write-wins (back-dated).
    private func insertSeed(_ scan: Scan) {
        var s = scan
        s.timestamp = Self.seedDate
        s.lastModifiedLocal = Self.seedDate
        s.isDeleted = false
        tombstones.removeAll { $0.id == s.id }
        scans.insert(s, at: 0)
        saveScans()
        CloudKitSyncService.shared.save(s)
    }

    /// Fixed timestamp far in the past so seed records always lose last-write-wins.
    static let seedDate = Date(timeIntervalSince1970: 0)

    // MARK: - Seed Data

    static let seedScans: [Scan] = [
        Scan(
            id: UUID(uuidString: "AA111111-1111-1111-1111-111111111111")!,
            beerName: "Lagunitas IPA",
            style: "IPA",
            abv: 6.2,
            verdict: .tryIt,
            explanation: "Your taste profile loves citrusy IPAs. This West Coast classic should be right up your alley."
        ),
        Scan(
            id: UUID(uuidString: "AA222222-2222-2222-2222-222222222222")!,
            beerName: "Bud Light Lime",
            style: "Light Lager",
            abv: 4.2,
            verdict: .skipIt,
            explanation: "Based on your preferences for bold flavors, this light lager with artificial lime flavor probably won't impress you."
        ),
        Scan(
            id: UUID(uuidString: "AA333333-3333-3333-3333-333333333333")!,
            beerName: "Blue Moon",
            style: "Wheat Ale",
            abv: 5.4,
            verdict: .yourCall,
            explanation: "This wheat beer is outside your usual IPA territory, but its orange peel and coriander notes might surprise you."
        ),
    ]
}
