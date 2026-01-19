import Foundation
import SwiftUI
import Combine

/// Observable store for managing drinks with JSON file persistence
class DrinkStore: ObservableObject {
    @Published var drinks: [Drink] = []

    init() {
        loadDrinks()
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
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("drinks.json")
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

    // MARK: - Queries

    var recentDrinks: [Drink] {
        Array(drinks.prefix(3))
    }

    func findMatch(for query: String) -> Drink? {
        BeerMatcher.findMatch(for: query, in: drinks)
    }
}
