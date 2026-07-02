import Foundation
import SwiftUI
import Combine

/// Observable store for managing journal entries with JSON file persistence
class JournalStore: ObservableObject {
    /// Visible (non-deleted) entries — what the UI binds to.
    @Published var entries: [JournalEntry] = []

    /// Soft-deleted records kept only so the deletion can sync to other devices.
    private var tombstones: [JournalEntry] = []

    /// All records (visible + tombstones) for CloudKit sync.
    var syncRecords: [JournalEntry] { entries + tombstones }

    private let storageDir: URL

    /// Standard init — uses app's Documents directory
    init() {
        self.storageDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        loadEntries()
    }

    /// Test-friendly init — custom storage directory + optional seed data
    init(storageDirectory: URL, useSeedData: Bool = false) {
        self.storageDir = storageDirectory
        if useSeedData {
            entries = Self.seedEntries
            saveEntries()
        } else {
            loadEntries()
        }
    }

    // MARK: - CRUD Operations

    func addEntry(_ entry: JournalEntry) {
        var e = entry
        e.lastModifiedLocal = Date()
        e.isDeleted = false
        tombstones.removeAll { $0.id == e.id }  // un-tombstone if re-added
        entries.insert(e, at: 0)
        saveEntries()
        CloudKitSyncService.shared.save(e)
    }

    func updateEntry(_ entry: JournalEntry) {
        var e = entry
        e.lastModifiedLocal = Date()
        if let index = entries.firstIndex(where: { $0.id == e.id }) {
            entries[index] = e
            saveEntries()
            CloudKitSyncService.shared.save(e)
        }
    }

    func deleteEntry(_ entry: JournalEntry) {
        tombstone(ids: [entry.id])
    }

    /// Soft-delete: hide locally and upload a tombstone so the deletion syncs.
    private func tombstone(ids: [UUID]) {
        let idSet = Set(ids)
        let removed = entries.filter { idSet.contains($0.id) }
        guard !removed.isEmpty else { return }
        entries.removeAll { idSet.contains($0.id) }
        for var rec in removed {
            rec.isDeleted = true
            rec.lastModifiedLocal = Date()
            tombstones.removeAll { $0.id == rec.id }
            tombstones.append(rec)
            CloudKitSyncService.shared.save(rec)
        }
        saveEntries()
    }

    /// Apply remote journal entries from CloudKit — bypasses CloudKit upload to avoid loops.
    @MainActor func applyRemoteEntries(_ remoteEntries: [JournalEntry]) {
        var byID: [UUID: JournalEntry] = [:]
        for e in entries { byID[e.id] = e }
        for t in tombstones { byID[t.id] = t }
        for remote in remoteEntries {
            if let local = byID[remote.id] {
                if cloudKitWins(remote, over: local) { byID[remote.id] = remote }
            } else {
                byID[remote.id] = remote
            }
        }
        let all = Array(byID.values)
        tombstones = all.filter { $0.isDeleted }
        entries = all.filter { !$0.isDeleted }.sorted { $0.dateLogged > $1.dateLogged }
        saveEntries()
    }

    func deleteAllEntries() {
        tombstone(ids: entries.map { $0.id })
    }

    // MARK: - Persistence

    private var fileURL: URL {
        storageDir.appendingPathComponent("journal.json")
    }

    private func saveEntries() {
        do {
            let data = try JSONEncoder().encode(entries + tombstones)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save journal entries: \(error)")
        }
    }

    /// Decodes element-by-element so one corrupt record is skipped instead of
    /// failing the whole file. Returns nil only when the data isn't a
    /// decodable array at all.
    private static func decodeTolerantly(_ data: Data) -> [JournalEntry]? {
        struct Lossy: Decodable {
            let value: JournalEntry?
            init(from decoder: Decoder) throws { value = try? JournalEntry(from: decoder) }
        }
        guard let lossy = try? JSONDecoder().decode([Lossy].self, from: data) else { return nil }
        let values = lossy.compactMap(\.value)
        if values.count != lossy.count {
            print("JournalStore: skipped \(lossy.count - values.count) corrupt record(s) in journal.json")
        }
        return values
    }

    private func loadEntries() {
        let backupURL = storageDir.appendingPathComponent("journal_backup.json")
        guard let data = try? Data(contentsOf: fileURL) else {
            entries = []
            tombstones = []
            return
        }

        var records = Self.decodeTolerantly(data)
        var goodBytes = data
        if records == nil {
            // Keep the corrupt file for forensics, then fall back to the
            // last-known-good backup instead of silently starting empty.
            try? data.write(to: storageDir.appendingPathComponent("journal_corrupt.json"), options: .atomic)
            if let backup = try? Data(contentsOf: backupURL),
               let restored = Self.decodeTolerantly(backup) {
                print("JournalStore: journal.json unreadable — restored from backup")
                records = restored
                goodBytes = backup
                try? backup.write(to: fileURL, options: .atomic)
            }
        }

        guard let all = records else {
            print("JournalStore: journal.json and backup both unreadable — starting empty")
            entries = []
            tombstones = []
            return
        }
        tombstones = all.filter { $0.isDeleted }
        entries = all.filter { !$0.isDeleted }
        // Back up only bytes that decoded successfully (last-known-good).
        try? goodBytes.write(to: backupURL, options: .atomic)
    }

    // MARK: - Queries

    /// Last 5 entries (most recent first, since we insert at front)
    var recentEntries: [JournalEntry] {
        Array(entries.prefix(5))
    }

    /// Entries with rating >= 4
    var lovedEntries: [JournalEntry] {
        entries.filter { $0.rating >= 4 }
    }

    /// Average rating across all entries, nil if no entries
    var averageRating: Double? {
        guard !entries.isEmpty else { return nil }
        let sum = entries.reduce(0) { $0 + $1.rating }
        return Double(sum) / Double(entries.count)
    }

    /// Find an entry matching a beer name query
    func findMatch(for query: String) -> JournalEntry? {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespaces)

        if let exact = entries.first(where: { $0.beerName.lowercased().trimmingCharacters(in: .whitespaces) == normalizedQuery }) {
            return exact
        }

        if let contains = entries.first(where: {
            let normalized = $0.beerName.lowercased().trimmingCharacters(in: .whitespaces)
            return normalized.contains(normalizedQuery) || normalizedQuery.contains(normalized)
        }) {
            return contains
        }

        return nil
    }

    /// Inject sample journal entries for testing. Idempotent — skips any already present by ID.
    /// Seeds are stamped with a far-past `lastModifiedLocal` so a real record always
    /// beats them in last-write-wins (prevents the button from clobbering real iCloud edits).
    func seedSampleData() {
        let existing = Set(entries.map { $0.id })
        let fresh = Self.seedEntries.filter { !existing.contains($0.id) }
        guard !fresh.isEmpty else { return }
        for entry in fresh { insertSeed(entry) }
    }

    /// Insert a seed record that can never win last-write-wins (back-dated).
    private func insertSeed(_ entry: JournalEntry) {
        var e = entry
        e.dateLogged = Self.seedDate
        e.lastModifiedLocal = Self.seedDate
        e.isDeleted = false
        tombstones.removeAll { $0.id == e.id }
        entries.insert(e, at: 0)
        saveEntries()
        CloudKitSyncService.shared.save(e)
    }

    /// Fixed timestamp far in the past so seed records always lose last-write-wins.
    static let seedDate = Date(timeIntervalSince1970: 0)

    // MARK: - Seed Data

    static let seedEntries: [JournalEntry] = [
        JournalEntry(
            id: UUID(uuidString: "BB111111-1111-1111-1111-111111111111")!,
            beerName: "Sierra Nevada Pale Ale",
            brand: "Sierra Nevada",
            style: "Pale Ale",
            rating: 5,
            notes: "Classic hop flavor. My go-to."
        ),
        JournalEntry(
            id: UUID(uuidString: "BB222222-2222-2222-2222-222222222222")!,
            beerName: "Guinness Draught",
            brand: "Guinness",
            style: "Stout",
            rating: 4,
            notes: "Smooth and creamy. Perfect on a cold night."
        ),
        JournalEntry(
            id: UUID(uuidString: "BB333333-3333-3333-3333-333333333333")!,
            beerName: "Bud Light",
            brand: "Anheuser-Busch",
            style: "Light Lager",
            rating: 2,
            notes: "Too watery for me."
        ),
    ]
}
