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
    /// Exact named beers chosen under the behavioral go-to/stay-away questions.
    /// These remain useful even when a local release has no catalog/model facts.
    var goToBeers: [String] = []
    var avoidBeers: [String] = []

    static var current: TastePreferences {
        let vibe = value(forKey: "tasteVibe")
        let adventure = value(forKey: "tasteAdventure")
        let dislikesStr = value(forKey: "tasteDislikes")
        let dislikes = dislikesStr.isEmpty ? [] : dislikesStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let seedStr = seedValue(forKey: "tasteSeedStyles")
        let rawSeedStyles = seedStr.isEmpty ? [] : seedStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let goToStr = seedValue(forKey: "tasteGoToStyles")
        let rawGoToStyles = goToStr.isEmpty ? [] : goToStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let avoidStr = seedValue(forKey: "tasteAvoidStyles")
        let avoidStyles = avoidStr.isEmpty ? [] : avoidStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let avoidBeerNames = savedAvoidBeers
        let goToBeerNames = savedGoToBeers.filter { goTo in
            !avoidBeerNames.contains { BeerMatcher.exactNamesMatch($0, goTo) }
        }
        // A legacy or cross-device race can leave the same style in both
        // channels. The explicit hard avoid is authoritative until the user
        // clears it, so contradictory positive seeds are ignored at read time.
        let avoidKeys = Set(avoidStyles.map { $0.lowercased() })
        let seedStyles = rawSeedStyles.filter { !avoidKeys.contains($0.lowercased()) }
        let goToStyles = rawGoToStyles.filter { !avoidKeys.contains($0.lowercased()) }
        return TastePreferences(
            vibe: vibe,
            adventure: adventure,
            dislikes: dislikes,
            seedStyles: seedStyles,
            goToStyles: goToStyles,
            avoidStyles: avoidStyles,
            goToBeers: goToBeerNames,
            avoidBeers: avoidBeerNames
        )
    }

    /// The raw onboarding beer picks, for restoring the picker on replay.
    static var savedKnownBeers: [String] {
        let raw = seedValue(forKey: "knownBeers")
        return raw.isEmpty ? [] : raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Raw named beers selected specifically as go-tos. Existing modern-flow
    /// installs migrate from `knownBeers`; the legacy "tried these" control did
    /// not write `tasteGoToStyles`, so it is not misread as a positive signal.
    static var savedGoToBeers: [String] {
        if let json = seedValueIfPresent(forKey: "tasteGoToBeersJSON"),
           let decoded = decodeList(json) {
            return decoded
        }
        if let raw = seedValueIfPresent(forKey: "tasteGoToBeers") {
            return raw.isEmpty ? [] : raw.components(separatedBy: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
        }
        return seedValue(forKey: "tasteGoToStyles").isEmpty ? [] : savedKnownBeers
    }

    /// Raw go-to styles for editing. `current.goToStyles` intentionally drops
    /// overlaps with hard avoids for scoring, but both independent answers
    /// must remain selected when the user reopens Settings.
    static var savedGoToStyles: [String] {
        if let json = seedValueIfPresent(forKey: "tasteGoToStyleChipsJSON"),
           let decoded = decodeList(json) {
            return decoded
        }
        let raw = seedValue(forKey: "tasteGoToStyles")
        return raw.isEmpty ? [] : raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Exact beer identities from the stay-away beer picker. New storage keeps
    /// this channel separate from style chips so a beer literally named "IPA"
    /// cannot silently become a broad style preference.
    static var savedAvoidBeers: [String] {
        if let json = seedValueIfPresent(forKey: "tasteAvoidBeersJSON"),
           let decoded = decodeList(json) {
            return decoded
        }
        if let json = seedValueIfPresent(forKey: "avoidBeersJSON"),
           let decoded = decodeList(json) {
            return decoded.filter { pick in
                !BeerStyle.allCases.contains {
                    $0.rawValue.caseInsensitiveCompare(pick) == .orderedSame
                }
            }
        }
        let raw = seedValue(forKey: "avoidBeers")
        return raw.isEmpty ? [] : raw.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { pick in
            !BeerStyle.allCases.contains {
                $0.rawValue.caseInsensitiveCompare(pick) == .orderedSame
            }
        }
    }

    /// Explicit stay-away style chips, distinct from styles inferred from beer
    /// names and from exact named-beer preferences.
    static var savedAvoidStyleChips: [String] {
        if let json = seedValueIfPresent(forKey: "tasteAvoidStyleChipsJSON"),
           let decoded = decodeList(json) {
            return decoded
        }
        let legacy = seedValue(forKey: "avoidBeers")
        guard !legacy.isEmpty else { return [] }
        return legacy.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { pick in
            BeerStyle.allCases.contains {
                $0.rawValue.caseInsensitiveCompare(pick) == .orderedSame
            }
        }
    }

    /// The onboarding beer buttons intentionally use familiar shorthand
    /// ("Lagunitas", "Guinness") rather than exact catalog product names.
    /// Resolve those product cues explicitly so the cold-start signal does not
    /// depend on a fuzzy catalog hit for a brewery-only label.
    static func styleForOnboardingBeer(_ beer: String) -> BeerStyle? {
        switch beer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "modelo", "corona", "heineken", "coors light", "bud light": return .lager
        case "stella artois": return .pilsner
        case "blue moon", "allagash white": return .wheat
        case "sam adams": return .amber
        case "guinness": return .stout
        case "sierra nevada": return .paleAle
        case "lagunitas", "hazy little thing", "two hearted ale", "dogfish head", "stone ipa", "goose island": return .ipa
        default: return nil
        }
    }

    static func onboardingBeer(_ beer: String, conflictsWith styles: [String]) -> Bool {
        guard let beerStyle = styleForOnboardingBeer(beer) else { return false }
        return styles.contains {
            $0.caseInsensitiveCompare(beerStyle.rawValue) == .orderedSame
        }
    }

    /// Fast preference generalization from explicit style picks, recognizable
    /// onboarding examples, printed style words, or the bundled catalog.
    static func locallyResolvedStyles(
        for picks: [String],
        catalog: BundledCatalog = .shared
    ) -> [String] {
        var resolved: Set<String> = []
        for pick in picks {
            if let style = styleForOnboardingBeer(pick)
                ?? TasteScorer.inferStyle(from: pick) {
                resolved.insert(style.rawValue)
                continue
            }

            // Beer-mode text is an identity, not a fuzzy catalog query. Only
            // generalize an exact catalog name when every duplicate row agrees
            // on one style; otherwise keep the preference item-local.
            let exactStyles = Set(catalog.exactMatches(name: pick).compactMap(\.style))
            if exactStyles.count == 1, let style = exactStyles.first {
                resolved.insert(style.rawValue)
            }
        }
        return resolved.sorted()
    }

    /// Test runs must be hermetic — mirror CloudKitSyncService's gate so the
    /// iCloud key-value store is never touched under test launch args.
    private static var cloudDisabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--disable-cloudkit")
            || args.contains("--isolated-storage")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
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
        seedValueIfPresent(forKey: key) ?? ""
    }

    /// Presence matters for toggleable values: a stored empty string means the
    /// user explicitly cleared the selection and must not fall back to legacy
    /// data from another key.
    private static func seedValueIfPresent(forKey key: String) -> String? {
        let defaults = UserDefaults.standard
        let local = defaults.object(forKey: key) == nil ? nil : (defaults.string(forKey: key) ?? "")
        guard !cloudDisabled else { return local }
        if let synced = NSUbiquitousKeyValueStore.default.string(forKey: key) {
            return synced
        }
        return local
    }

    private static func encodeList(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let encoded = String(data: data, encoding: .utf8) else { return "[]" }
        return encoded
    }

    private static func decodeList(_ encoded: String) -> [String]? {
        guard let data = encoded.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        return values
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

    /// Save the exact go-to identities before any asynchronous style lookup.
    /// This makes the user's tap immediately authoritative even when the beer
    /// is absent from every fact source or they advance before enrichment ends.
    static func saveGoToSelections(beers: [String], styleChips: [String]) {
        let sorted = beers.sorted()
        let sortedStyles = styleChips.sorted()
        let values = [
            "knownBeers": sorted.joined(separator: ","),
            "tasteGoToBeers": sorted.joined(separator: ","),
            "tasteGoToBeersJSON": encodeList(sorted),
            "tasteGoToStyleChipsJSON": encodeList(sortedStyles),
            // Clear derived styles immediately; the local resolver adds the
            // current snapshot back asynchronously. Explicit chips take effect
            // now and removed beers cannot leave a ghost style behind.
            "tasteSeedStyles": "",
            "tasteGoToStyles": sortedStyles.joined(separator: ",")
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

    /// Save raw stay-away identities before asynchronous local fact resolution.
    static func saveAvoidSelections(beers: [String], styleChips: [String]) {
        let sortedBeers = beers.sorted()
        let sortedStyles = styleChips.sorted()
        let legacyMixed = (sortedBeers + sortedStyles).sorted()
        let values = [
            "avoidBeers": legacyMixed.joined(separator: ","),
            "avoidBeersJSON": encodeList(legacyMixed),
            "tasteAvoidBeersJSON": encodeList(sortedBeers),
            "tasteAvoidStyleChipsJSON": encodeList(sortedStyles),
            // Same immediate-baseline rule as go-tos: explicit chips apply
            // now, removed beer-derived styles disappear before async work.
            "tasteAvoidStyles": sortedStyles.joined(separator: ",")
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
        // A named beer selected under "What's your go-to?" is an explicit
        // preference, not merely something the user has sampled. Keep the
        // seed channel for compatibility, and also give its resolved styles
        // the same full-weight channel as directly tapped style chips.
        let explicitGoToStyles = Array(Set(styleChips).union(seedStyles)).sorted()
        let values = [
            "knownBeers": beers.sorted().joined(separator: ","),
            "tasteGoToBeers": beers.sorted().joined(separator: ","),
            "tasteGoToBeersJSON": encodeList(beers.sorted()),
            "tasteGoToStyleChipsJSON": encodeList(styleChips.sorted()),
            "tasteSeedStyles": seedStyles.sorted().joined(separator: ","),
            "tasteGoToStyles": explicitGoToStyles.joined(separator: ",")
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

    /// Async style derivation is view-local, but selections are app-global.
    /// Recheck the local source-of-truth keys so an older screen instance
    /// cannot overwrite a newer edit after its detached work finishes.
    static func goToSelectionsAreCurrent(beers: [String], styleChips: [String]) -> Bool {
        let defaults = UserDefaults.standard
        guard let beerJSON = defaults.string(forKey: "tasteGoToBeersJSON"),
              let savedBeers = decodeList(beerJSON),
              let styleJSON = defaults.string(forKey: "tasteGoToStyleChipsJSON"),
              let savedStyles = decodeList(styleJSON) else { return false }
        return savedBeers.sorted() == beers.sorted()
            && savedStyles.sorted() == styleChips.sorted()
    }

    static func avoidSelectionsAreCurrent(beers: [String], styleChips: [String]) -> Bool {
        let defaults = UserDefaults.standard
        guard let beerJSON = defaults.string(forKey: "tasteAvoidBeersJSON"),
              let savedBeers = decodeList(beerJSON),
              let styleJSON = defaults.string(forKey: "tasteAvoidStyleChipsJSON"),
              let savedStyles = decodeList(styleJSON) else { return false }
        return savedBeers.sorted() == beers.sorted()
            && savedStyles.sorted() == styleChips.sorted()
    }

    /// Persist the stay-away beer identities, explicit style chips, and all
    /// locally resolved styles. Beer/style channels stay separate in the new
    /// keys; legacy mixed keys remain for migration compatibility.
    static func saveAvoidSelections(
        beers: [String],
        styleChips: [String],
        avoidStyles: [String]
    ) {
        let sortedBeers = beers.sorted()
        let sortedStyles = styleChips.sorted()
        let legacyMixed = (sortedBeers + sortedStyles).sorted()
        let values = [
            "avoidBeers": legacyMixed.joined(separator: ","),
            "avoidBeersJSON": encodeList(legacyMixed),
            "tasteAvoidBeersJSON": encodeList(sortedBeers),
            "tasteAvoidStyleChipsJSON": encodeList(sortedStyles),
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

    var isEmpty: Bool {
        vibe.isEmpty && adventure.isEmpty && goToStyles.isEmpty && avoidStyles.isEmpty
            && goToBeers.isEmpty && avoidBeers.isEmpty
    }

    /// A compact natural-language summary for injection into prompts
    var promptSummary: String {
        // The default onboarding flow may collect only behavioral picks, so
        // named beers and style seeds must reach the prompt without quiz data.
        guard !isEmpty else { return "" }
        var parts: [String] = []
        if !vibe.isEmpty { parts.append("prefers \(vibe) beers") }
        if !adventure.isEmpty { parts.append("adventure level: \(adventure)") }
        if !dislikes.isEmpty { parts.append("dislikes: \(dislikes.joined(separator: ", "))") }
        if !goToStyles.isEmpty { parts.append("go-to styles: \(goToStyles.joined(separator: ", "))") }
        if !avoidStyles.isEmpty { parts.append("always stays away from: \(avoidStyles.joined(separator: ", "))") }
        if !goToBeers.isEmpty { parts.append("go-to beers: \(goToBeers.joined(separator: ", "))") }
        if !avoidBeers.isEmpty { parts.append("always avoids these beers: \(avoidBeers.joined(separator: ", "))") }
        return "User taste profile: " + parts.joined(separator: "; ") + "."
    }
}
