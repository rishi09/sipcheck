import Foundation
import UIKit
import SwiftUI
import Combine

/// Observable store for managing drinks with JSON file persistence
class DrinkStore: ObservableObject {
    @Published var drinks: [Drink] = []

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
        drinks.insert(drink, at: 0)
        saveDrinks()
    }

    func updateDrink(_ drink: Drink) {
        if let index = drinks.firstIndex(where: { $0.id == drink.id }) {
            drinks[index] = drink
            saveDrinks()
        }
    }

    func deleteDrink(_ drink: Drink) {
        drinks.removeAll { $0.id == drink.id }
        saveDrinks()
    }

    func deleteDrinks(at offsets: IndexSet, from filteredDrinks: [Drink]) {
        for index in offsets {
            let drink = filteredDrinks[index]
            deleteDrink(drink)
        }
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
            let data = try JSONEncoder().encode(drinks)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save drinks: \(error)")
        }
    }

    private func loadDrinks() {
        do {
            let data = try Data(contentsOf: fileURL)
            drinks = try JSONDecoder().decode([Drink].self, from: data)
        } catch {
            // File doesn't exist or is invalid - start with empty array
            drinks = []
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
