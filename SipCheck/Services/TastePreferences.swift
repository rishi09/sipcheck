import Foundation

struct TastePreferences {
    let vibe: String        // e.g. "Hoppy & Bitter"
    let adventure: String   // e.g. "Mix It Up"
    let dislikes: [String]  // e.g. ["Super Bitter", "Really Sour"]

    // MARK: Quiz option strings (single source of truth)
    // Consumed by both the onboarding TasteQuizPage and Settings'
    // TastePreferencesEditorView — the saved answer strings must match
    // wherever they're offered, or verdicts silently stop following answers.
    static let vibeOptions = ["Crisp & Light", "Hoppy & Bitter", "Dark & Roasty", "Fruity & Easy", "Sour & Weird"]
    static let adventureOptions = ["Stick to Favorites", "Mix It Up", "Give Me the Weird Stuff"]
    static let dislikeOptions = ["Super Bitter", "Very Dark", "Really Sour", "Wheat-y / Cloudy"]
    /// Style rawValues seeded from the onboarding "beers you've had" picker —
    /// the cold-start signal so scan #1 is personalized before any ratings.
    /// Defaulted so existing 3-argument construction sites stay valid.
    var seedStyles: [String] = []
    /// Style rawValues the user explicitly picked as go-to chips on the
    /// onboarding go-to picker — a direct "I buy this" answer, scored at the
    /// vibe weight. Defaulted so existing construction sites stay valid.
    var goToStyles: [String] = []
    /// Style rawValues the user explicitly marked "stay away" during onboarding
    /// (picked directly, or resolved from an avoided beer name — "Guinness" →
    /// Stout). This is a SEPARATE channel from `dislikes`: it is never unioned
    /// into the quiz dislike keys and never vibe-subtracted, because a
    /// stay-away pick names the exact style while quiz dislikes are fuzzy
    /// phrases keyword-mapped onto styles. Defaulted so existing construction
    /// sites stay valid.
    var avoidStyles: [String] = []

    static var current: TastePreferences {
        let vibe = value(forKey: "tasteVibe")
        let adventure = value(forKey: "tasteAdventure")
        let dislikesStr = value(forKey: "tasteDislikes")
        let dislikes = dislikesStr.isEmpty ? [] : dislikesStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let seedStr = seedValue(forKey: "tasteSeedStyles")
        let seedStyles = seedStr.isEmpty ? [] : seedStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let goToStr = seedValue(forKey: "tasteGoToStyles")
        let goToStyles = goToStr.isEmpty ? [] : goToStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let avoidStr = seedValue(forKey: "tasteAvoidStyles")
        let avoidStyles = avoidStr.isEmpty ? [] : avoidStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return TastePreferences(vibe: vibe, adventure: adventure, dislikes: dislikes, seedStyles: seedStyles, goToStyles: goToStyles, avoidStyles: avoidStyles)
    }

    /// The raw onboarding beer picks, for restoring the picker on replay.
    static var savedKnownBeers: [String] {
        let raw = seedValue(forKey: "knownBeers")
        return raw.isEmpty ? [] : raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// The raw onboarding stay-away picks — a MIXED list of beer names and
    /// style rawValues — for restoring the stay-away picker on replay and for
    /// future re-derivation. The scorer never reads this; it consumes the
    /// resolved styles in `avoidStyles` (key "tasteAvoidStyles").
    static var savedAvoidBeers: [String] {
        let raw = seedValue(forKey: "avoidBeers")
        return raw.isEmpty ? [] : raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
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

    /// Seed keys are a toggleable picker, not a one-shot quiz: deselect-all is
    /// a real user action, so a PRESENT cloud value — even empty — is
    /// authoritative, and stale locals are never mirrored back up (the quiz's
    /// self-heal mirror would resurrect explicitly-cleared picks).
    private static func seedValue(forKey key: String) -> String {
        let local = UserDefaults.standard.string(forKey: key) ?? ""
        guard !cloudDisabled else { return local }
        if let synced = NSUbiquitousKeyValueStore.default.string(forKey: key) {
            return synced
        }
        return local
    }

    /// Persist the onboarding "beers you've had" cold-start seed: the raw picks
    /// (for future re-derivation) and the styles they resolve to (what the
    /// scorer consumes). Unlike the quiz's save(), empties ARE pushed to the
    /// cloud — clearing the picker must propagate (see seedValue).
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
        for (key, value) in values {
            cloud.set(value, forKey: key)
        }
        cloud.synchronize()
    }

    /// Persist the onboarding go-to picker: the raw beer picks, the styles they
    /// resolve to, and the explicit go-to style chips. Same seed-save semantics
    /// as `saveKnownBeers` — empties ARE pushed to the cloud, because clearing
    /// a toggleable picker must propagate (see seedValue). Kept separate from
    /// `saveKnownBeers` so the legacy (control) picker never blanks
    /// "tasteGoToStyles" it doesn't know about.
    static func saveGoTo(beers: [String], styleChips: [String], seedStyles: [String]) {
        let values = [
            "knownBeers": beers.sorted().joined(separator: ","),
            "tasteSeedStyles": seedStyles.sorted().joined(separator: ","),
            "tasteGoToStyles": styleChips.sorted().joined(separator: ",")
        ]
        for (key, value) in values {
            UserDefaults.standard.set(value, forKey: key)
        }
        guard !cloudDisabled else { return }
        let cloud = NSUbiquitousKeyValueStore.default
        for (key, value) in values {
            cloud.set(value, forKey: key)
        }
        cloud.synchronize()
    }

    /// Persist the onboarding stay-away picker: the raw picks (beer names and
    /// style rawValues, mixed — for restoring the picker and future
    /// re-derivation) and the styles they resolve to (what the scorer's avoid
    /// channel consumes). Seed-save semantics: empties ARE pushed to the
    /// cloud — clearing the picker must propagate (see seedValue).
    static func saveAvoidBeers(_ picks: [String], avoidStyles: [String]) {
        let values = [
            "avoidBeers": picks.sorted().joined(separator: ","),
            "tasteAvoidStyles": avoidStyles.sorted().joined(separator: ",")
        ]
        for (key, value) in values {
            UserDefaults.standard.set(value, forKey: key)
        }
        guard !cloudDisabled else { return }
        let cloud = NSUbiquitousKeyValueStore.default
        for (key, value) in values {
            cloud.set(value, forKey: key)
        }
        cloud.synchronize()
    }

    /// Persist ONLY the adventure answer (the go-to page's optional row)
    /// without touching vibe/dislikes — routing through the 3-key save() would
    /// blank a real vibe answer. Quiz-save semantics, not seed-save: local
    /// always, cloud only when non-empty, so an unanswered row on one device
    /// can't erase a synced answer elsewhere.
    static func saveAdventure(_ value: String) {
        UserDefaults.standard.set(value, forKey: "tasteAdventure")
        guard !cloudDisabled, !value.isEmpty else { return }
        let cloud = NSUbiquitousKeyValueStore.default
        cloud.set(value, forKey: "tasteAdventure")
        cloud.synchronize()
    }

    var isEmpty: Bool { vibe.isEmpty && adventure.isEmpty }

    /// A compact natural-language summary for injection into prompts
    var promptSummary: String {
        // isEmpty (vibe/adventure) is deliberately unchanged for its other
        // callers, but the default onboarding flow never asks the vibe quiz —
        // go-to/stay-away picks alone must still reach the prompt.
        guard !(isEmpty && goToStyles.isEmpty && avoidStyles.isEmpty) else { return "" }
        var parts: [String] = []
        if !vibe.isEmpty { parts.append("prefers \(vibe) beers") }
        if !adventure.isEmpty { parts.append("adventure level: \(adventure)") }
        if !dislikes.isEmpty { parts.append("dislikes: \(dislikes.joined(separator: ", "))") }
        if !goToStyles.isEmpty { parts.append("go-to styles: \(goToStyles.joined(separator: ", "))") }
        if !avoidStyles.isEmpty { parts.append("always stays away from: \(avoidStyles.joined(separator: ", "))") }
        return "User taste profile: " + parts.joined(separator: "; ") + "."
    }
}
