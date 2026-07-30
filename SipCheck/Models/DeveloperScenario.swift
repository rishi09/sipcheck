#if DEBUG
import Foundation

/// Deterministic, isolated app states for product work and UI verification.
/// These fixtures are only compiled into Debug builds and are safe to apply
/// only when the process uses `--isolated-storage`.
enum DeveloperScenario: String, CaseIterable, Identifiable {
    case empty
    case richHistory = "rich-history"
    case savedOnly = "saved-only"
    case error

    static let launchArgument = "--developer-scenario"
    static let storageKey = "developerScenario"
    static let errorMessage = "Couldn't read that label. Try again or enter the beer name."

    var id: String { rawValue }

    var title: String {
        switch self {
        case .empty: return "Empty"
        case .richHistory: return "Rich History"
        case .savedOnly: return "Saved Only"
        case .error: return "Error"
        }
    }

    var subtitle: String {
        switch self {
        case .empty: return "No tried or saved beers"
        case .richHistory: return "Three ratings across distinct styles"
        case .savedOnly: return "Three beers waiting in Want to Try"
        case .error: return "A recoverable label-reading failure"
        }
    }

    var symbol: String {
        switch self {
        case .empty: return "tray"
        case .richHistory: return "books.vertical.fill"
        case .savedOnly: return "bookmark.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    /// Check = 0, Journal = 1. Rich/saved/empty scenarios open where their
    /// data is immediately visible; Error opens on the recovery surface.
    var initialTab: Int {
        self == .error ? 0 : 1
    }

    var fixture: DeveloperScenarioFixture {
        switch self {
        case .empty, .error:
            return DeveloperScenarioFixture(drinks: [], scans: [], journalEntries: [])
        case .richHistory:
            return Self.richHistoryFixture
        case .savedOnly:
            return Self.savedOnlyFixture
        }
    }

    static func requested(in arguments: [String] = ProcessInfo.processInfo.arguments) -> DeveloperScenario? {
        if let inline = arguments.first(where: { $0.hasPrefix("\(launchArgument)=") }) {
            return DeveloperScenario(rawValue: String(inline.dropFirst(launchArgument.count + 1)))
        }
        guard let index = arguments.firstIndex(of: launchArgument),
              arguments.indices.contains(index + 1) else { return nil }
        return DeveloperScenario(rawValue: arguments[index + 1])
    }

    static var current: DeveloperScenario? {
        guard let raw = UserDefaults.standard.string(forKey: storageKey) else { return nil }
        return DeveloperScenario(rawValue: raw)
    }

    static func clearCurrent() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    /// Replaces only the isolated developer stores. No CloudKit operation is
    /// emitted by these replacement hooks.
    func apply(
        drinkStore: DrinkStore,
        scanStore: ScanStore,
        journalStore: JournalStore,
        notify: Bool = true
    ) {
        let fixture = fixture
        drinkStore.replaceForDeveloperScenario(with: fixture.drinks)
        scanStore.replaceForDeveloperScenario(with: fixture.scans)
        journalStore.replaceForDeveloperScenario(with: fixture.journalEntries)
        UserDefaults.standard.set(rawValue, forKey: Self.storageKey)

        if notify {
            NotificationCenter.default.post(name: .developerScenarioDidChange, object: self)
        }
    }

    private static let anchorDate = Date(timeIntervalSince1970: 1_767_225_600)

    private static var richHistoryFixture: DeveloperScenarioFixture {
        var drinks = DrinkStore.seedDrinks
        var entries = JournalStore.seedEntries
        var scans = ScanStore.seedScans
        for index in drinks.indices {
            let date = anchorDate.addingTimeInterval(Double(-index) * 86_400)
            drinks[index].dateAdded = date
            drinks[index].lastModifiedLocal = date
            entries[index].dateLogged = date
            entries[index].dateTried = date
            entries[index].lastModifiedLocal = date
        }
        for index in scans.indices {
            let date = anchorDate.addingTimeInterval(Double(-index) * 86_400)
            scans[index].timestamp = date
            scans[index].lastModifiedLocal = date
        }
        return DeveloperScenarioFixture(drinks: drinks, scans: scans, journalEntries: entries)
    }

    private static var savedOnlyFixture: DeveloperScenarioFixture {
        var scans = ScanStore.seedScans
        for index in scans.indices {
            let date = anchorDate.addingTimeInterval(Double(-index) * 86_400)
            scans[index].timestamp = date
            scans[index].lastModifiedLocal = date
            scans[index].wantToTry = true
            scans[index].linkedJournalId = nil
        }
        return DeveloperScenarioFixture(drinks: [], scans: scans, journalEntries: [])
    }
}

struct DeveloperScenarioFixture {
    let drinks: [Drink]
    let scans: [Scan]
    let journalEntries: [JournalEntry]
}

extension Notification.Name {
    static let developerScenarioDidChange = Notification.Name("developerScenarioDidChange")
}
#endif
