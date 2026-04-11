import Foundation
import SwiftUI
import Combine

/// Observable store for managing scans with JSON file persistence
class ScanStore: ObservableObject {
    @Published var scans: [Scan] = []

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
        scans.insert(scan, at: 0)
        saveScans()
    }

    func updateScan(_ scan: Scan) {
        if let index = scans.firstIndex(where: { $0.id == scan.id }) {
            scans[index] = scan
            saveScans()
        }
    }

    func deleteScan(_ scan: Scan) {
        scans.removeAll { $0.id == scan.id }
        saveScans()
        NotificationService.shared.cancelFollowUp(for: scan)
    }

    func deleteAllScans() {
        let allScans = scans
        scans.removeAll()
        saveScans()
        for scan in allScans {
            NotificationService.shared.cancelFollowUp(for: scan)
        }
    }

    // MARK: - Persistence

    private var fileURL: URL {
        storageDir.appendingPathComponent("scans.json")
    }

    private func saveScans() {
        do {
            let data = try JSONEncoder().encode(scans)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save scans: \(error)")
        }
    }

    private func loadScans() {
        guard let data = try? Data(contentsOf: fileURL) else {
            scans = []
            return
        }
        // Write backup before decoding — protects against decode failure wiping the file on next save
        let backupURL = storageDir.appendingPathComponent("scans_backup.json")
        try? data.write(to: backupURL, options: .atomic)

        do {
            scans = try JSONDecoder().decode([Scan].self, from: data)
        } catch {
            print("ScanStore: failed to decode scans.json — keeping empty. Error: \(error)")
            scans = []
        }
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

        // Exact match
        if let exact = scans.first(where: { $0.beerName.lowercased().trimmingCharacters(in: .whitespaces) == normalizedQuery }) {
            return exact
        }

        // Contains match
        if let contains = scans.first(where: {
            let normalized = $0.beerName.lowercased().trimmingCharacters(in: .whitespaces)
            return normalized.contains(normalizedQuery) || normalizedQuery.contains(normalized)
        }) {
            return contains
        }

        return nil
    }

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
