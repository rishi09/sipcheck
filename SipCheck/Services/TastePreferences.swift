import Foundation

struct TastePreferences {
    let vibe: String        // e.g. "Hoppy & Bitter"
    let adventure: String   // e.g. "Mix It Up"
    let dislikes: [String]  // e.g. ["Super Bitter", "Really Sour"]
    /// Style rawValues seeded from the onboarding "beers you've had" picker —
    /// the cold-start signal so scan #1 is personalized before any ratings.
    /// Defaulted so existing 3-argument construction sites stay valid.
    var seedStyles: [String] = []

    static var current: TastePreferences {
        let vibe = value(forKey: "tasteVibe")
        let adventure = value(forKey: "tasteAdventure")
        let dislikesStr = value(forKey: "tasteDislikes")
        let dislikes = dislikesStr.isEmpty ? [] : dislikesStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let seedStr = value(forKey: "tasteSeedStyles")
        let seedStyles = seedStr.isEmpty ? [] : seedStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return TastePreferences(vibe: vibe, adventure: adventure, dislikes: dislikes, seedStyles: seedStyles)
    }

    /// Test runs must be hermetic — mirror CloudKitSyncService's gate so the
    /// iCloud key-value store is never touched under test launch args.
    private static var cloudDisabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--disable-cloudkit") || args.contains("--isolated-storage")
    }

    /// Quiz answers previously lived only in this device's UserDefaults, so
    /// the two test iPhones disagreed on every verdict. Reads prefer the
    /// iCloud key-value store (synced) and fall back to local; writes go to
    /// both. Devices that answered the quiz before syncing existed self-heal:
    /// their local answers are mirrored up the first time they're read.
    /// An EMPTY cloud value is treated as absent — "skip quiz" on one device
    /// must never shadow real answers stored anywhere else.
    private static func value(forKey key: String) -> String {
        let local = UserDefaults.standard.string(forKey: key) ?? ""
        guard !cloudDisabled else { return local }
        let cloud = NSUbiquitousKeyValueStore.default
        if let synced = cloud.string(forKey: key), !synced.isEmpty {
            return synced
        }
        if !local.isEmpty {
            cloud.set(local, forKey: key)
        }
        return local
    }

    /// Write-through both stores. The KVS copy is what other devices see.
    /// Empty values are written locally but never pushed to the cloud, so a
    /// skipped quiz can't erase synced answers on other devices.
    static func save(vibe: String, adventure: String, dislikes: String) {
        let values = ["tasteVibe": vibe, "tasteAdventure": adventure, "tasteDislikes": dislikes]
        for (key, value) in values {
            UserDefaults.standard.set(value, forKey: key)
        }
        guard !cloudDisabled else { return }
        let cloud = NSUbiquitousKeyValueStore.default
        for (key, value) in values where !value.isEmpty {
            cloud.set(value, forKey: key)
        }
        cloud.synchronize()
    }

    /// Persist the onboarding "beers you've had" cold-start seed: the raw picks
    /// (for future re-derivation) and the styles they resolve to (what the
    /// scorer consumes). Same write-through-cloud policy as the quiz answers.
    static func saveKnownBeers(_ beers: [String], seedStyles: [String]) {
        let values = [
            "knownBeers": beers.sorted().joined(separator: ","),
            "tasteSeedStyles": seedStyles.sorted().joined(separator: ",")
        ]
        for (key, value) in values {
            UserDefaults.standard.set(value, forKey: key)
        }
        guard !cloudDisabled else { return }
        let cloud = NSUbiquitousKeyValueStore.default
        for (key, value) in values where !value.isEmpty {
            cloud.set(value, forKey: key)
        }
        cloud.synchronize()
    }

    var isEmpty: Bool { vibe.isEmpty && adventure.isEmpty }

    /// A compact natural-language summary for injection into prompts
    var promptSummary: String {
        guard !isEmpty else { return "" }
        var parts: [String] = []
        if !vibe.isEmpty { parts.append("prefers \(vibe) beers") }
        if !adventure.isEmpty { parts.append("adventure level: \(adventure)") }
        if !dislikes.isEmpty { parts.append("dislikes: \(dislikes.joined(separator: ", "))") }
        return "User taste profile: " + parts.joined(separator: "; ") + "."
    }
}
