import Foundation

/// A beer resolved to just the fields the verdict needs: style (+ optional ABV).
struct ResolvedBeer: Equatable {
    let name: String
    let brewery: String?
    let style: BeerStyle?
    let abv: Double?
    let source: Source
    /// Catalog match confidence (0–1) when `source == .catalog`; nil otherwise.
    /// Lets the UI say "Best match: Two Hearted (72%)" instead of faking certainty.
    var confidence: Double? = nil

    /// Where the style/ABV came from — useful for telemetry and for deciding
    /// whether an async top-up is worth firing.
    enum Source: String {
        case labelText     // style/ABV read straight off the label or menu line
        case catalog       // matched a bundled catalog entry
        case onDeviceLLM   // Foundation Models world-knowledge
        case online        // network top-up / vision fallback
        case unresolved    // nothing found — name only
    }

    /// Enough to give a verdict right now? The scorer only *needs* a style;
    /// ABV is a bonus modifier.
    var isActionable: Bool { style != nil }
}

/// A source of beer knowledge keyed by name.
///
/// `BundledCatalog` is the offline/instant implementation. Online/LLM sources
/// adopt `AsyncBeerCatalog` so they can be awaited as a top-up without ever
/// blocking the instant path.
protocol BeerCatalog {
    /// Fast, synchronous fuzzy lookup by name. Returns `nil` on a miss.
    func lookup(name: String) -> ResolvedBeer?
}

protocol AsyncBeerCatalog {
    func lookup(name: String) async -> ResolvedBeer?
}

/// Fuses whatever signals a scan produced into a `ResolvedBeer`, fastest-first,
/// so the UI can show a verdict in the moment and refine later.
///
/// Fusion order (see CLAUDE.md → Camera/Scan):
///   1. style/ABV printed on the label or menu line  (labelText)
///   2. bundled offline catalog, fuzzy name match     (catalog)
///   3. on-device LLM / online top-up                 (async, optional)
///
/// The synchronous `resolve` never touches the network; `enrich` is the opt-in
/// async refinement for misses or to fill a missing ABV.
enum BeerResolver {

    // MARK: - Instant, synchronous resolution (no network)

    /// Resolve from raw recognized text (a label blob or a single menu line)
    /// plus a bundled catalog. Returns the best `ResolvedBeer` we can build now.
    static func resolve(recognizedText text: String, using catalog: BeerCatalog?) -> ResolvedBeer {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // (1) What the label/menu itself prints.
        let printedStyle = TasteScorer.inferStyle(from: cleaned)
        let printedABV = MenuParser.extractABV(from: cleaned)

        // (2) Bundled catalog match by name (fills gaps, adds brewery/ABV).
        let hit = catalog?.lookup(name: cleaned)

        let style = printedStyle ?? hit?.style
        let abv = printedABV ?? hit?.abv
        let brewery = hit?.brewery

        let source: ResolvedBeer.Source
        if printedStyle != nil {
            source = .labelText          // we read it directly — fastest, most trustworthy
        } else if hit?.style != nil {
            source = .catalog
        } else {
            source = .unresolved
        }

        return ResolvedBeer(
            name: hit?.name ?? cleaned,
            brewery: brewery,
            style: style,
            abv: abv,
            source: source,
            confidence: hit?.confidence
        )
    }

    /// Resolve then score against the taste library in one shot — the instant verdict.
    static func verdict(
        forRecognizedText text: String,
        using catalog: BeerCatalog?,
        profile: TasteProfile,
        preferences: TastePreferences
    ) -> (resolved: ResolvedBeer, assessment: TasteScorer.Assessment) {
        let resolved = resolve(recognizedText: text, using: catalog)
        let assessment = TasteScorer.assess(
            name: resolved.name,
            style: resolved.style,
            abv: resolved.abv,
            profile: profile,
            preferences: preferences
        )
        return (resolved, assessment)
    }

    // MARK: - Async top-up (opt-in; only when it helps)

    /// Worth firing a network/LLM top-up? Yes if we couldn't get a style, or if
    /// we have a style but no ABV and want the extra precision.
    static func shouldEnrich(_ r: ResolvedBeer) -> Bool {
        r.style == nil || r.abv == nil
    }

    /// Refine an instant result with an async source (LLM / online), preferring
    /// any field we already trust. Safe to call after the verdict is on screen.
    static func enrich(
        _ base: ResolvedBeer,
        with source: AsyncBeerCatalog
    ) async -> ResolvedBeer {
        guard let more = await source.lookup(name: base.name) else { return base }
        return ResolvedBeer(
            name: base.name,
            brewery: base.brewery ?? more.brewery,
            style: base.style ?? more.style,
            abv: base.abv ?? more.abv,
            source: base.isActionable ? base.source : more.source
        )
    }
}

// MARK: - Bundled Offline Catalog

/// Loads the app-bundled `catalog.json` (name → brewery/style/ABV) and answers
/// fuzzy name lookups entirely on-device. This is the default resolver source.
final class BundledCatalog: BeerCatalog {

    /// Shared, app-bundle-backed instance used by the instant scan path.
    /// Decodes `catalog.json` from `Bundle.main` once and answers on-device.
    static let shared = BundledCatalog()

    /// One row of the bundled catalog. Mirrors `plans/prototypes/data/catalog.json`.
    private struct Entry: Decodable {
        let name: String
        let brewery: String?
        let style: String?
        let coarse: String?   // one of our coarse style keys, e.g. "ipa"
        let abv: Double?
    }

    private let entries: [Entry]
    /// Precomputed normalized names + token sets, parallel to `entries`.
    private let normalizedNames: [String]
    private let tokenSets: [Set<String>]
    /// Normalized-name → index, for O(1) exact hits before falling back to fuzzy.
    private let exactIndex: [String: Int]
    /// token → entry indices; candidate generation so fuzzy scoring never walks
    /// all 2,410 entries.
    private let tokenIndex: [String: [Int]]

    /// Words that can never identify a beer on their own ("Pale Ale" must not
    /// match every pale ale on the shelf). Backed up by a data-driven check on
    /// posting-list size in `isDistinctive`.
    private static let genericWords: Set<String> = [
        "ale", "beer", "the", "and", "brewing", "brewery", "company", "co",
        "ipa", "lager", "stout", "porter", "pale", "with", "series"
    ]

    /// Minimum score for a fuzzy candidate to count as a match at all.
    private static let matchThreshold: Double = 0.6

    /// - Parameter bundle: defaults to `.main`; injectable for tests.
    init(bundle: Bundle = .main, resourceName: String = "catalog") {
        let loaded: [Entry]
        if let url = bundle.url(forResource: resourceName, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            loaded = decoded
        } else {
            loaded = []
        }
        self.entries = loaded
        (self.normalizedNames, self.tokenSets, self.exactIndex, self.tokenIndex) =
            BundledCatalog.buildIndexes(loaded)
    }

    /// Test/preview seam: build directly from decoded rows without a bundle.
    init(seed rows: [(name: String, brewery: String?, style: String?, coarse: String?, abv: Double?)]) {
        let mapped = rows.map { Entry(name: $0.name, brewery: $0.brewery, style: $0.style, coarse: $0.coarse, abv: $0.abv) }
        self.entries = mapped
        (self.normalizedNames, self.tokenSets, self.exactIndex, self.tokenIndex) =
            BundledCatalog.buildIndexes(mapped)
    }

    func lookup(name: String) -> ResolvedBeer? {
        matches(name: name, limit: 1).first
    }

    /// Ranked candidate matches with a 0–1 confidence, best first. Deterministic
    /// for identical inputs. The old first-substring-wins lookup confidently
    /// returned the wrong beer ("Voodoo Ranger Juice Force" → a porter named
    /// "Voodoo"); scoring anchored on distinctive tokens prevents that class of
    /// false positive while still matching label blobs that *contain* a real name.
    func matches(name: String, limit: Int = 3) -> [ResolvedBeer] {
        guard !entries.isEmpty else { return [] }
        let q = BundledCatalog.normalize(name)
        guard !q.isEmpty else { return [] }

        // 1. Exact normalized hit.
        if let i = exactIndex[q] { return [resolved(entries[i], confidence: 1.0)] }

        // 2. Candidate generation via the token index (distinctive tokens only).
        let querySet = Set(q.split(separator: " ").map(String.init))
        var candidates: Set<Int> = []
        for token in querySet where isDistinctive(token) {
            if let list = tokenIndex[token] { candidates.formUnion(list) }
        }
        guard !candidates.isEmpty else { return [] }

        // 3. Score candidates; keep those above threshold.
        var scored: [(idx: Int, score: Double, overlap: Int)] = []
        for i in candidates {
            let s = score(query: q, querySet: querySet, entry: normalizedNames[i], entrySet: tokenSets[i])
            if s >= BundledCatalog.matchThreshold {
                scored.append((i, s, querySet.intersection(tokenSets[i]).count))
            }
        }

        // 4. Deterministic ranking: score, then token overlap, then name.
        scored.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.overlap != b.overlap { return a.overlap > b.overlap }
            return entries[a.idx].name < entries[b.idx].name
        }
        return scored.prefix(limit).map { resolved(entries[$0.idx], confidence: $0.score) }
    }

    // MARK: - Scoring

    /// A token specific enough to anchor a match: not a generic beer word, not
    /// trivially short, and not present in a huge slice of the catalog.
    private func isDistinctive(_ token: String) -> Bool {
        guard token.count >= 4, !BundledCatalog.genericWords.contains(token) else { return false }
        return (tokenIndex[token]?.count ?? 0) <= 150
    }

    private func score(query q: String, querySet: Set<String>, entry n: String, entrySet: Set<String>) -> Double {
        if q == n { return 1.0 }

        let hasDistinctiveOverlap = querySet.intersection(entrySet).contains(where: isDistinctive)

        // Full containment either direction, anchored by a distinctive token:
        // a label blob ("TRADER JOES BOATSWAIN DOUBLE IPA 22 FL OZ") contains the
        // full entry name; a typed partial ("two hearted") is contained by it.
        if entrySet.count >= 2, hasDistinctiveOverlap, entrySet.isSubset(of: querySet) {
            return min(0.95, 0.75 + 0.07 * Double(entrySet.count))
        }
        if querySet.count >= 2, hasDistinctiveOverlap, querySet.isSubset(of: entrySet) {
            return 0.85
        }
        // Single long specific token ("boatswain") on either side.
        if querySet.count == 1, let t = querySet.first, t.count >= 7, entrySet.contains(t) { return 0.62 }
        if entrySet.count == 1, let t = entrySet.first, t.count >= 7, querySet.contains(t) { return 0.62 }

        var s = 0.0
        let union = querySet.union(entrySet)
        if !union.isEmpty, hasDistinctiveOverlap {
            let jaccard = Double(querySet.intersection(entrySet).count) / Double(union.count)
            if jaccard >= 0.5 { s = 0.45 + 0.4 * jaccard }
        }
        // Typo tolerance on the whole string ("hazy little thnig").
        if abs(q.count - n.count) <= 3, max(q.count, n.count) <= 40 {
            let sim = BeerMatcher.calculateSimilarity(q, n)
            if sim >= 0.8 { s = max(s, sim * 0.92) }
        }
        return s
    }

    // MARK: - Helpers

    private static func buildIndexes(
        _ entries: [Entry]
    ) -> (names: [String], tokens: [Set<String>], exact: [String: Int], byToken: [String: [Int]]) {
        var names: [String] = []
        var tokens: [Set<String>] = []
        var exact: [String: Int] = [:]
        var byToken: [String: [Int]] = [:]
        names.reserveCapacity(entries.count)
        tokens.reserveCapacity(entries.count)
        for (i, e) in entries.enumerated() {
            let n = normalize(e.name)
            names.append(n)
            let set = Set(n.split(separator: " ").map(String.init))
            tokens.append(set)
            if exact[n] == nil { exact[n] = i }
            for t in set { byToken[t, default: []].append(i) }
        }
        return (names, tokens, exact, byToken)
    }

    private func resolved(_ e: Entry, confidence: Double) -> ResolvedBeer {
        ResolvedBeer(
            name: e.name,
            brewery: e.brewery,
            style: BundledCatalog.style(fromCoarse: e.coarse) ?? TasteScorer.inferStyle(from: e.style ?? e.name),
            abv: e.abv,
            source: .catalog,
            confidence: confidence
        )
    }

    /// Map a coarse key ("ipa", "brown ale", …) to a `BeerStyle`.
    private static func style(fromCoarse coarse: String?) -> BeerStyle? {
        guard let coarse, !coarse.isEmpty else { return nil }
        return BeerStyle.allCases.first { $0.rawValue.lowercased() == coarse.lowercased() }
    }

    /// Case/diacritic-folded, punctuation-stripped, whitespace-collapsed.
    /// "Kölsch #002 — Löwenbräu" → "kolsch 002 lowenbrau", so real-world label
    /// text and catalog names meet on common ground.
    private static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
        let mapped = folded.map { c -> Character in (c.isLetter || c.isNumber) ? c : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }
}
