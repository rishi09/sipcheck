import Foundation

/// On-device, instant beer verdict engine.
///
/// This is the Phase-1 "fast path" ported from the validated Python prototype
/// (`plans/prototypes/menu_verdict_prototype.py`). It is pure, synchronous, and
/// makes NO network calls — given a candidate beer (name + optional style/ABV)
/// and the user's taste library it returns a `Verdict` plus a short reason.
///
/// The network LLM remains available as *optional enrichment* (richer copy,
/// brewery origin, etc.) but the user always gets an instant answer first.
enum TasteScorer {

    // MARK: - Public Result

    /// Outcome of scoring a single candidate against the taste library.
    struct Assessment {
        let verdict: Verdict
        let shortReason: String
        /// Numeric score behind the verdict — exposed for deterministic
        /// tiebreaking and unit testing. Not shown to the user directly.
        let score: Double
    }

    // MARK: - Tuning Constants

    /// Score at/above which a candidate is a confident "try it".
    private static let tryThreshold: Double = 2.0
    /// Score at/above which a candidate is "your call" (below this it's a skip).
    private static let yourCallThreshold: Double = 0.0

    /// Default ABV sweet spot used when the user has no ABV history.
    private static let defaultIdealABV: Double = 6.0
    /// How far (in ABV %) a beer can sit from the ideal before it counts against it.
    private static let abvTolerance: Double = 3.0
    /// Upper bound on the ABV mismatch penalty, so one bad ABV can't dominate the score.
    private static let maxABVPenalty: Double = 2.0
    /// Liked-weight for styles seeded from the onboarding "beers you've had"
    /// picker — weaker than an explicit vibe answer (2.0), stronger than nothing.
    private static let seedStyleWeight: Double = 1.5
    /// Netted against rating-history liked weight when the same style also
    /// carries a dislike signal. History weight caps at 3.0, so mixed evidence
    /// lands in [-2.0, 0.0] — never a confident TRY, never the full -5 veto.
    private static let mixedEvidenceOffset: Double = 3.0
    /// Penalty for a style the user explicitly marked "stay away" during
    /// onboarding. Slightly stronger than the quiz-dislike -5.0 because a
    /// stay-away pick names the exact style, while quiz dislikes are fuzzy
    /// phrases keyword-mapped onto styles — so on an all-bad menu the explicit
    /// pick deterministically ranks last. Mixed evidence (rated LIKE history on
    /// the same style) nets against the shared 3.0 `mixedEvidenceOffset`
    /// instead, so real ratings can walk an over-broad seed back (e.g. "avoid
    /// Bud Light" penalizing all lagers until liked lagers net it out).
    private static let avoidSeedPenalty: Double = 5.5
    /// Neutral-style nudges per the quiz's "How adventurous?" answer.
    private static let neutralBonusCautious: Double = 0.0     // Stick to Favorites
    private static let neutralBonusDefault: Double = 0.2      // Mix It Up / unanswered
    private static let neutralBonusAdventurous: Double = 0.8  // Give Me the Weird Stuff

    // MARK: - Public API

    /// Score a candidate beer against the user's taste library.
    ///
    /// - Parameters:
    ///   - name: The candidate's display name (used for style inference fallback).
    ///   - style: An already-inferred style, if available. When `nil` the name
    ///            is used to infer one via `inferStyle(from:)`.
    ///   - abv: The candidate's ABV percentage, if known.
    ///   - profile: The computed taste profile derived from rating history.
    ///   - preferences: The quick-quiz taste preferences (vibe / dislikes).
    /// - Returns: An `Assessment` with verdict, short reason, and raw score.
    static func assess(
        name: String,
        style: BeerStyle?,
        abv: Double?,
        profile: TasteProfile,
        preferences: TastePreferences
    ) -> Assessment {
        // No style signal at all: an honest "your call", never a confident skip.
        // A graphic label whose OCR only yields brewery + fantasy name carries no
        // taste information — pretending otherwise ("SKIP IT") is worse than
        // admitting it (locked constraint: verdict must work from style alone,
        // and no signal must still yield a usable verdict). A known ABV still
        // contributes to the SCORE so menu ranking stays sane, but it can never
        // fake a confident verdict on its own.
        guard let resolvedStyle = style ?? inferStyle(from: name) else {
            let score = abv.map { abvScore($0, idealABV: idealABV(from: profile)) } ?? 0.0
            return Assessment(
                verdict: .yourCall,
                shortReason: "we couldn't tell the style — trust your gut",
                score: score
            )
        }

        var score = 0.0
        var reasons: [String] = []

        // ---- Style contribution -------------------------------------------
        let likedWeights = likedStyleWeights(from: profile, preferences: preferences)
        let dislikedSet = dislikedStyleKeys(from: profile, preferences: preferences)
        let avoidSet = avoidSeedStyleKeys(from: preferences)

        let key = styleKey(resolvedStyle)
        if avoidSet.contains(key) || dislikedSet.contains(key) {
            // Mixed evidence counts RATED history only: a vibe answer or a
            // "beers you've had" seed is not a like, and must not soften a
            // repeatedly-thumbs-downed (or explicitly avoided) style.
            if let liked = profile.favoriteStyles.first(where: { $0.style.lowercased() == key }) {
                // A single bad stout must not permanently veto a style the user
                // has loved many times — net the signals instead.
                let weight = min(3.0, 1.0 + Double(liked.count - 1) * 0.5)
                score += weight - mixedEvidenceOffset
                reasons.append("mixed history with \(reasonName(resolvedStyle))")
            } else if avoidSet.contains(key) {
                score -= avoidSeedPenalty
                reasons.append("you steer clear of \(reasonName(resolvedStyle))")
            } else {
                score -= 5.0
                reasons.append("you usually avoid \(reasonName(resolvedStyle))")
            }
        } else if let weight = likedWeights[key] {
            score += weight
            reasons.append("matches your love of \(reasonName(resolvedStyle))")
        } else {
            // Known style, neither loved nor avoided — the quiz's adventurousness
            // answer (previously collected and ignored) decides the nudge.
            score += neutralStyleBonus(for: preferences.adventure)
        }

        // ---- ABV contribution ---------------------------------------------
        if let abv {
            let contribution = abvScore(abv, idealABV: idealABV(from: profile))
            score += contribution
            if contribution < 0 {
                reasons.append("\(formattedABV(abv)) is off your usual strength")
            }
        }

        let verdict = verdict(for: score)
        let reason = reasons.isEmpty ? "no strong signal either way" : reasons.joined(separator: "; ")
        return Assessment(verdict: verdict, shortReason: reason, score: score)
    }

    /// The scorer's ABV anchor: liked-history average first, any-history
    /// average second, sensible default last.
    private static func idealABV(from profile: TasteProfile) -> Double {
        profile.likedAverageABV ?? profile.averageABV ?? defaultIdealABV
    }

    /// The single ABV scoring curve — used by both the styled path and the
    /// unknown-style path so menu ranking treats every candidate consistently.
    /// Within tolerance of the ideal: small bonus; outside: clamped penalty so
    /// a misparsed/extreme ABV can't single-handedly bury a loved beer.
    private static func abvScore(_ abv: Double, idealABV: Double) -> Double {
        let gap = abs(abv - idealABV)
        return gap <= abvTolerance ? 0.5 : -min(maxABVPenalty, 0.5 * (gap - abvTolerance))
    }

    /// Map a raw score to a user-facing `Verdict`.
    static func verdict(for score: Double) -> Verdict {
        if score >= tryThreshold {
            return .tryIt
        } else if score >= yourCallThreshold {
            return .yourCall
        } else {
            return .skipIt
        }
    }

    // MARK: - Deterministic Tiebreaker

    /// Returns `true` if candidate `a` should rank strictly ahead of candidate `b`.
    ///
    /// Primary key is the score (higher wins). Ties are broken deterministically:
    ///   1. Closer to the user's ideal ABV wins (a known ABV beats an unknown one).
    ///   2. Then higher liked-style weight wins.
    ///   3. Then case-insensitive name order, so the result is fully stable
    ///      regardless of the input ordering.
    static func ranksAhead(
        _ a: AssessedCandidate,
        _ b: AssessedCandidate,
        profile: TasteProfile,
        preferences: TastePreferences
    ) -> Bool {
        // 1. Score
        if a.assessment.score != b.assessment.score {
            return a.assessment.score > b.assessment.score
        }

        // 2. ABV proximity to ideal (smaller gap wins; unknown ABV ranks last).
        let ideal = idealABV(from: profile)
        let gapA = a.abv.map { abs($0 - ideal) } ?? Double.greatestFiniteMagnitude
        let gapB = b.abv.map { abs($0 - ideal) } ?? Double.greatestFiniteMagnitude
        if gapA != gapB {
            return gapA < gapB
        }

        // 3. Liked-style weight (higher wins).
        let weights = likedStyleWeights(from: profile, preferences: preferences)
        let weightA = a.style.map { weights[styleKey($0)] ?? 0 } ?? 0
        let weightB = b.style.map { weights[styleKey($0)] ?? 0 } ?? 0
        if weightA != weightB {
            return weightA > weightB
        }

        // 4. Stable final tiebreak: case-insensitive name order.
        return a.name.lowercased() < b.name.lowercased()
    }

    /// A candidate paired with its computed assessment — the unit used for ranking.
    struct AssessedCandidate {
        let name: String
        let style: BeerStyle?
        let abv: Double?
        let assessment: Assessment
    }

    // MARK: - Style Inference

    /// Keyword map from beer-name fragments to a `BeerStyle`.
    ///
    /// Beer names almost always telegraph their style, so this lets us classify
    /// a candidate with no database and no network. Mirrors the prototype's
    /// `STYLE_KEYWORDS`; the most specific (longest) matching keyword wins.
    private static let styleKeywords: [(style: BeerStyle, keywords: [String])] = [
        (.ipa,       ["double ipa", "west coast", "neipa", "juicy", "hazy", "dipa", "ipa", "hop"]),
        (.paleAle,   ["pale ale", "golden ale", "blonde", "blond ale", "apa", "pale"]),
        (.lager,     ["lager", "helles", "vienna", "festbier", "doppelbock", "bock", "dunkel", "cream ale"]),
        (.pilsner,   ["pilsner", "pils", "kolsch"]),
        (.stout,     ["imperial stout", "milk stout", "oatmeal", "stout"]),
        (.porter,    ["porter", "schwarzbier", "black lager"]),
        (.wheat,     ["hefeweizen", "witbier", "white ale", "blanche", "wheat", "hefe"]),
        (.sour,      ["berliner", "lambic", "wild ale", "sour", "gose", "kriek", "funk"]),
        (.amber,     ["irish red", "red ale", "amber", "marzen", "oktoberfest", "extra special", "esb"]),
        (.brownAle,  ["nut brown", "brown ale", "brown"]),
        (.belgian,   ["belgian", "tripel", "dubbel", "saison", "quad", "barleywine", "barley wine"]),
    ]

    /// Infer a `BeerStyle` from a beer name, or `nil` if nothing matches.
    ///
    /// The longest matching keyword across all styles wins, so "double ipa"
    /// beats "pale" and "imperial stout" beats a bare "stout". Input is
    /// diacritic-folded ("Märzen"/"Kölsch" match) and keywords match only at
    /// word starts — raw substring matching classified "Grasshopper" as an IPA
    /// via "hop" and "Nepal" as a pale ale via "pale". Word-start (not
    /// whole-word) so "hoppy"/"hops" still signal IPA.
    static func inferStyle(from name: String) -> BeerStyle? {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
        let collapsed = folded.map { c -> Character in (c.isLetter || c.isNumber) ? c : " " }
        let normalized = " " + String(collapsed).split(separator: " ").joined(separator: " ")

        var best: (style: BeerStyle, length: Int)?
        for entry in styleKeywords {
            for keyword in entry.keywords where normalized.contains(" " + keyword) {
                if best == nil || keyword.count > best!.length {
                    best = (entry.style, keyword.count)
                }
            }
        }
        return best?.style
    }

    // MARK: - Taste Library Helpers

    /// Canonical lookup key for a style — the lowercased raw value
    /// (e.g. `BeerStyle.ipa` -> "ipa", `.brownAle` -> "brown ale").
    private static func styleKey(_ style: BeerStyle) -> String {
        style.rawValue.lowercased()
    }

    /// Style name as it should read inside sentence-cased copy: acronyms stay
    /// uppercase ("Matches your love of IPA."), words go lowercase.
    private static func reasonName(_ style: BeerStyle) -> String {
        let display = style.displayName
        return display == display.uppercased() ? display : display.lowercased()
    }

    /// Build a `styleKey -> weight` map of liked styles.
    ///
    /// Weights come from rating history (`favoriteStyles`, scaled by count) and
    /// are boosted by the quick-quiz vibe. Higher weight = stronger "try it" pull.
    private static func likedStyleWeights(
        from profile: TasteProfile,
        preferences: TastePreferences
    ) -> [String: Double] {
        var weights: [String: Double] = [:]

        // History: more liked drinks of a style => higher weight, capped so a
        // single very-liked style can't dwarf everything else.
        for entry in profile.favoriteStyles {
            let key = entry.style.lowercased()
            let weight = min(3.0, 1.0 + Double(entry.count - 1) * 0.5)
            weights[key] = max(weights[key] ?? 0, weight)
        }

        // Quiz vibe: nudge styles the user said they enjoy.
        for key in vibeStyleKeys(from: preferences.vibe) {
            weights[key] = max(weights[key] ?? 0, 2.0)
        }

        // Explicit go-to style chips from onboarding fill the vibe slot at the
        // same 2.0 weight — a direct "I buy this" answer is as strong as a
        // vibe. (assess() checks the avoid set before liked weights, so a
        // stay-away pick on the same style always beats this weight.)
        for style in preferences.goToStyles {
            let key = style.lowercased()
            weights[key] = max(weights[key] ?? 0, 2.0)
        }

        // Cold-start seed from the onboarding "beers you've had" picker —
        // weaker than the explicit vibe, stronger than nothing, so scan #1 is
        // personalized before any ratings exist.
        for style in preferences.seedStyles {
            let key = style.lowercased()
            weights[key] = max(weights[key] ?? 0, seedStyleWeight)
        }

        return weights
    }

    /// How much a known-but-unloved style scores, per the quiz's
    /// "How adventurous?" answer.
    private static func neutralStyleBonus(for adventure: String) -> Double {
        let lower = adventure.lowercased()
        if lower.contains("stick") { return neutralBonusCautious }
        if lower.contains("weird") { return neutralBonusAdventurous }
        return neutralBonusDefault
    }

    /// Build the set of disliked `styleKey`s from history + quiz dislikes.
    private static func dislikedStyleKeys(
        from profile: TasteProfile,
        preferences: TastePreferences
    ) -> Set<String> {
        let disliked = Set(profile.dislikedStyles.map { $0.style.lowercased() })

        var quizDislikes: Set<String> = []
        for dislike in preferences.dislikes {
            quizDislikes.formUnion(styleKeys(matching: dislike))
        }
        // The explicit vibe outranks a generic dislike phrase that keyword-matches
        // the same styles: "Hoppy & Bitter" vibe + "Super Bitter" dislike is a
        // coherent answer (loves hops, hates palate-wreckers) — it must not nuke
        // every IPA. Rating history still counts as a real dislike.
        quizDislikes.subtract(vibeStyleKeys(from: preferences.vibe))

        return disliked.union(quizDislikes)
    }

    /// Build the set of avoid `styleKey`s from the onboarding stay-away seed.
    ///
    /// Deliberately SEPARATE from `dislikedStyleKeys` and never vibe-subtracted:
    /// the vibe-subtraction exists because quiz dislikes are fuzzy phrases
    /// keyword-mapped onto styles ("Super Bitter" incidentally hits every IPA),
    /// but a stay-away pick names the exact style — a "Dark & Roasty" vibe must
    /// not cancel an explicit "stay away from stouts".
    private static func avoidSeedStyleKeys(from preferences: TastePreferences) -> Set<String> {
        Set(preferences.avoidStyles.map { $0.lowercased() })
    }

    /// Map a free-text quiz "vibe" string to liked style keys.
    private static func vibeStyleKeys(from vibe: String) -> Set<String> {
        let lower = vibe.lowercased()
        guard !lower.isEmpty else { return [] }
        var keys: Set<String> = []
        if lower.contains("hoppy") || lower.contains("bitter") {
            keys.formUnion(["ipa", "pale ale"])
        }
        if lower.contains("malt") || lower.contains("roasty") || lower.contains("dark") {
            keys.formUnion(["stout", "porter", "brown ale", "amber"])
        }
        if lower.contains("crisp") || lower.contains("light") || lower.contains("refresh") {
            keys.formUnion(["lager", "pilsner"])
        }
        // "Fruity & Easy" and "Sour & Weird" are different palates — fruity
        // leans wheat/witbier territory, sour/weird leans sours and wild ales.
        if lower.contains("sour") || lower.contains("tart") || lower.contains("weird") {
            keys.formUnion(["sour"])
        }
        if lower.contains("fruit") || lower.contains("easy") {
            keys.formUnion(["wheat"])
        }
        return keys
    }

    /// Map a free-text dislike phrase to any style keys it implies.
    private static func styleKeys(matching phrase: String) -> Set<String> {
        let lower = phrase.lowercased()
        guard !lower.isEmpty else { return [] }
        var keys: Set<String> = []
        if lower.contains("bitter") || lower.contains("hoppy") {
            keys.formUnion(["ipa"])
        }
        if lower.contains("sour") || lower.contains("tart") {
            keys.formUnion(["sour"])
        }
        if lower.contains("dark") || lower.contains("roasty") || lower.contains("heavy") {
            keys.formUnion(["stout", "porter"])
        }
        // Also match a dislike that names a style outright (e.g. "Stout").
        for style in BeerStyle.allCases where lower.contains(styleKey(style)) {
            keys.insert(styleKey(style))
        }
        return keys
    }

    // MARK: - Formatting

    /// Format an ABV the way the prototype reported it (e.g. `6.5%`, `9%`).
    private static func formattedABV(_ abv: Double) -> String {
        if abv == abv.rounded() {
            return "\(Int(abv))%"
        }
        return String(format: "%.1f%%", abv)
    }
}
