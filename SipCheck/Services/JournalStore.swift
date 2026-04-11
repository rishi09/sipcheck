import Foundation
import SwiftUI
import Combine

/// Observable store for managing journal entries with JSON file persistence
class JournalStore: ObservableObject {
    @Published var entries: [JournalEntry] = []

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
        entries.insert(entry, at: 0)
        saveEntries()
    }

    func updateEntry(_ entry: JournalEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
            saveEntries()
        }
    }

    func deleteEntry(_ entry: JournalEntry) {
        entries.removeAll { $0.id == entry.id }
        saveEntries()
    }

    // MARK: - Persistence

    private var fileURL: URL {
        storageDir.appendingPathComponent("journal.json")
    }

    private func saveEntries() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save journal entries: \(error)")
        }
    }

    private func loadEntries() {
        guard let data = try? Data(contentsOf: fileURL) else {
            entries = []
            return
        }
        // Write backup before decoding — protects against decode failure wiping the file on next save
        let backupURL = storageDir.appendingPathComponent("journal_backup.json")
        try? data.write(to: backupURL, options: .atomic)

        do {
            entries = try JSONDecoder().decode([JournalEntry].self, from: data)
        } catch {
            print("JournalStore: failed to decode journal.json — keeping empty. Error: \(error)")
            entries = []
        }
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

        // Exact match
        if let exact = entries.first(where: { $0.beerName.lowercased().trimmingCharacters(in: .whitespaces) == normalizedQuery }) {
            return exact
        }

        // Contains match
        if let contains = entries.first(where: {
            let normalized = $0.beerName.lowercased().trimmingCharacters(in: .whitespaces)
            return normalized.contains(normalizedQuery) || normalizedQuery.contains(normalized)
        }) {
            return contains
        }

        return nil
    }

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
