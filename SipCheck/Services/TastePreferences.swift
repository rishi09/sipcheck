import Foundation

struct TastePreferences {
    let vibe: String        // e.g. "Hoppy & Bitter"
    let adventure: String   // e.g. "Mix It Up"
    let dislikes: [String]  // e.g. ["Super Bitter", "Really Sour"]

    static var current: TastePreferences {
        let vibe = UserDefaults.standard.string(forKey: "tasteVibe") ?? ""
        let adventure = UserDefaults.standard.string(forKey: "tasteAdventure") ?? ""
        let dislikesStr = UserDefaults.standard.string(forKey: "tasteDislikes") ?? ""
        let dislikes = dislikesStr.isEmpty ? [] : dislikesStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return TastePreferences(vibe: vibe, adventure: adventure, dislikes: dislikes)
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
