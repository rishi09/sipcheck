import Foundation
import UIKit
import SwiftUI
import Combine

/// Observable store for managing drinks with JSON file persistence
class DrinkStore: ObservableObject {
    /// Visible (non-deleted) drinks — what the UI binds to.
    @Published var drinks: [Drink] = []

    /// Soft-deleted records kept only so the deletion can sync to other devices.
    /// Never shown in the UI; merged/uploaded alongside `drinks`.
    private var tombstones: [Drink] = []

    /// All records (visible + tombstones) for CloudKit sync.
    var syncRecords: [Drink] { drinks + tombstones }

    private let storageDir: URL

    /// Standard init — uses app's Documents directory
    init() {
        self.storageDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        loadDrinks()
    }

    /// Test-friendly init — custom storage directory + optional seed data
    init(storageDirectory: URL, useSeedData: Bool = false) {
        self.storageDir = storageDirectory
        if useSeedData {
            drinks = Self.seedDrinks
            saveDrinks()
        } else {
            loadDrinks()
        }
    }

    // MARK: - CRUD Operations

    func addDrink(_ drink: Drink) {
        var d = drink
        d.lastModifiedLocal = Date()
        d.isDeleted = false
        tombstones.removeAll { $0.id == d.id }  // un-tombstone if re-added
        drinks.insert(d, at: 0)
        saveDrinks()
        CloudKitSyncService.shared.save(d)
    }

    func updateDrink(_ drink: Drink) {
        var d = drink
        d.lastModifiedLocal = Date()
        if let index = drinks.firstIndex(where: { $0.id == d.id }) {
            drinks[index] = d
            saveDrinks()
            CloudKitSyncService.shared.save(d)
        }
    }

    func deleteDrink(_ drink: Drink) {
        tombstone(ids: [drink.id])
    }

    func deleteDrinks(at offsets: IndexSet, from filteredDrinks: [Drink]) {
        tombstone(ids: offsets.map { filteredDrinks[$0].id })
    }

    /// Soft-delete: hide locally and upload a tombstone so the deletion syncs.
    private func tombstone(ids: [UUID]) {
        let idSet = Set(ids)
        let removed = drinks.filter { idSet.contains($0.id) }
        guard !removed.isEmpty else { return }
        drinks.removeAll { idSet.contains($0.id) }
        for var rec in removed {
            rec.isDeleted = true
            rec.lastModifiedLocal = Date()
            tombstones.removeAll { $0.id == rec.id }
            tombstones.append(rec)
            CloudKitSyncService.shared.save(rec)
        }
        saveDrinks()
    }

    /// Apply remote drinks from CloudKit — bypasses CloudKit upload to avoid loops.
    /// Merges visible records AND tombstones by last-write-wins, so a newer remote
    /// deletion removes a local record (and vice versa).
    @MainActor func applyRemoteDrinks(_ remoteDrinks: [Drink]) {
        var byID: [UUID: Drink] = [:]
        for d in drinks { byID[d.id] = d }
        for t in tombstones { byID[t.id] = t }
        for remote in remoteDrinks {
            if let local = byID[remote.id] {
                if remote.lastModifiedLocal > local.lastModifiedLocal { byID[remote.id] = remote }
            } else {
                byID[remote.id] = remote
            }
        }
        let all = Array(byID.values)
        tombstones = all.filter { $0.isDeleted }
        drinks = all.filter { !$0.isDeleted }.sorted { $0.dateAdded > $1.dateAdded }
        saveDrinks()
    }

    // MARK: - Persistence

    private var fileURL: URL {
        storageDir.appendingPathComponent("drinks.json")
    }

    private var photosDir: URL {
        let dir = storageDir.appendingPathComponent("photos")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func saveDrinks() {
        do {
            // Persist visible records and tombstones together.
            let data = try JSONEncoder().encode(drinks + tombstones)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save drinks: \(error)")
        }
    }

    private func loadDrinks() {
        guard let data = try? Data(contentsOf: fileURL) else {
            drinks = []
            tombstones = []
            return
        }
        // Write backup before decoding — protects against decode failure wiping the file on next save
        let backupURL = storageDir.appendingPathComponent("drinks_backup.json")
        try? data.write(to: backupURL, options: .atomic)

        do {
            let all = try JSONDecoder().decode([Drink].self, from: data)
            tombstones = all.filter { $0.isDeleted }
            drinks = all.filter { !$0.isDeleted }
        } catch {
            print("DrinkStore: failed to decode drinks.json — keeping empty. Error: \(error)")
            drinks = []
            tombstones = []
        }
    }

    // MARK: - Photo Management

    private let photoCache = NSCache<NSString, UIImage>()

    func savePhoto(_ image: UIImage, for drinkId: UUID) async -> String? {
        return await Task.detached(priority: .userInitiated) {
            guard let data = ImageCompressor.compress(image, maxDimension: 1024, quality: 0.8) else { return nil }
            let fileName = "\(drinkId.uuidString).jpg"
            let fileURL = self.photosDir.appendingPathComponent(fileName)
            do {
                try data.write(to: fileURL, options: .atomic)
                return fileName
            } catch {
                print("Failed to save photo: \(error)")
                return nil
            }
        }.value
    }

    func loadPhoto(named fileName: String) -> UIImage? {
        let cacheKey = fileName as NSString
        if let cached = photoCache.object(forKey: cacheKey) {
            return cached
        }
        let fileURL = photosDir.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else { return nil }
        photoCache.setObject(image, forKey: cacheKey)
        return image
    }

    func deletePhoto(named fileName: String) {
        photoCache.removeObject(forKey: fileName as NSString)
        let fileURL = photosDir.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Queries

    var recentDrinks: [Drink] {
        Array(drinks.prefix(3))
    }

    var tasteProfile: TasteProfile {
        TasteProfile.build(from: drinks)
    }

    func findMatch(for query: String) -> Drink? {
        BeerMatcher.findMatch(for: query, in: drinks)
    }

    /// Inject sample drinks for testing. Idempotent — skips any already present by ID.
    func seedSampleData() {
        let existing = Set(drinks.map { $0.id })
        let fresh = Self.seedDrinks.filter { !existing.contains($0.id) }
        guard !fresh.isEmpty else { return }
        for drink in fresh { addDrink(drink) }
    }

    // MARK: - Seed Data

    static let seedDrinks: [Drink] = [
        Drink(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Sierra Nevada Pale Ale",
            brand: "Sierra Nevada",
            style: "Pale Ale",
            rating: .like,
            notes: "Classic hop flavor"
        ),
        Drink(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Guinness Draught",
            brand: "Guinness",
            style: "Stout",
            rating: .like,
            notes: "Smooth and creamy"
        ),
        Drink(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            name: "Bud Light",
            brand: "Anheuser-Busch",
            style: "Light Lager",
            rating: .dislike
        ),
    ]
}
