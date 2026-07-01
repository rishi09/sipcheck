import Foundation

/// A beer resolved to just the fields the verdict needs: style (+ optional ABV).
struct ResolvedBeer: Equatable {
    let name: String
    let brewery: String?
    let style: BeerStyle?
    let abv: Double?
    let source: Source

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
            source: source
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
    /// Normalized-name → index, for O(1) exact hits before falling back to fuzzy.
    private let exactIndex: [String: Int]

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
        var idx: [String: Int] = [:]
        for (i, e) in loaded.enumerated() {
            idx[BundledCatalog.normalize(e.name)] = i
        }
        self.exactIndex = idx
    }

    /// Test/preview seam: build directly from decoded rows without a bundle.
    init(seed rows: [(name: String, brewery: String?, style: String?, coarse: String?, abv: Double?)]) {
        let mapped = rows.map { Entry(name: $0.name, brewery: $0.brewery, style: $0.style, coarse: $0.coarse, abv: $0.abv) }
        self.entries = mapped
        var idx: [String: Int] = [:]
        for (i, e) in mapped.enumerated() { idx[BundledCatalog.normalize(e.name)] = i }
        self.exactIndex = idx
    }

    func lookup(name: String) -> ResolvedBeer? {
        guard !entries.isEmpty else { return nil }
        let q = BundledCatalog.normalize(name)
        guard !q.isEmpty else { return nil }

        // 1. Exact normalized hit.
        if let i = exactIndex[q] { return resolved(entries[i]) }

        // 2. Substring either direction (label text often has extra words) — but
        //    only for reasonably specific names, so short generic catalog names
        //    ("IPA", "Pils") don't swallow every scan that contains them.
        if let e = entries.first(where: {
            let n = BundledCatalog.normalize($0.name)
            return n.count >= 6 && (q.contains(n) || n.contains(q))
        }) {
            return resolved(e)
        }
        return nil
    }

    // MARK: - Helpers

    private func resolved(_ e: Entry) -> ResolvedBeer {
        ResolvedBeer(
            name: e.name,
            brewery: e.brewery,
            style: BundledCatalog.style(fromCoarse: e.coarse) ?? TasteScorer.inferStyle(from: e.style ?? e.name),
            abv: e.abv,
            source: .catalog
        )
    }

    /// Map a coarse key ("ipa", "brown ale", …) to a `BeerStyle`.
    private static func style(fromCoarse coarse: String?) -> BeerStyle? {
        guard let coarse, !coarse.isEmpty else { return nil }
        return BeerStyle.allCases.first { $0.rawValue.lowercased() == coarse.lowercased() }
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
    }
}
