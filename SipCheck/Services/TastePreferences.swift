import Foundation

struct TastePreferences {
    let vibe: String        // e.g. "Hoppy & Bitter"
    let adventure: String   // e.g. "Mix It Up"
    let dislikes: [String]  // e.g. ["Super Bitter", "Really Sour"]

    static var current: TastePreferences {
        let vibe = value(forKey: "tasteVibe")
        let adventure = value(forKey: "tasteAdventure")
        let dislikesStr = value(forKey: "tasteDislikes")
        let dislikes = dislikesStr.isEmpty ? [] : dislikesStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return TastePreferences(vibe: vibe, adventure: adventure, dislikes: dislikes)
    }

    /// Quiz answers previously lived only in this device's UserDefaults, so
    /// the two test iPhones disagreed on every verdict. Reads prefer the
    /// iCloud key-value store (synced) and fall back to local; writes go to
    /// both. Devices that answered the quiz before syncing existed self-heal:
    /// their local answers are mirrored up the first time they're read.
    private static func value(forKey key: String) -> String {
        let cloud = NSUbiquitousKeyValueStore.default
        let local = UserDefaults.standard.string(forKey: key) ?? ""
        if let synced = cloud.string(forKey: key) {
            return synced
        }
        if !local.isEmpty {
            cloud.set(local, forKey: key)
        }
        return local
    }

    /// Write-through both stores. The KVS copy is what other devices see.
    static func save(vibe: String, adventure: String, dislikes: String) {
        let cloud = NSUbiquitousKeyValueStore.default
        for (key, value) in ["tasteVibe": vibe, "tasteAdventure": adventure, "tasteDislikes": dislikes] {
            UserDefaults.standard.set(value, forKey: key)
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
