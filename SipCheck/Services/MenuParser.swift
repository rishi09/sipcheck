import Foundation

/// A single beer parsed out of a menu OCR blob.
struct BeerCandidate: Equatable {
    /// The cleaned-up line the candidate came from (post noise-stripping context).
    let rawLine: String
    /// The display name with price / ABV / serving noise removed.
    let name: String
    /// Style inferred from the name, if any.
    let style: BeerStyle?
    /// ABV percentage extracted from the line, if present.
    let abv: Double?
}

/// Parses a messy multi-line OCR menu string into beer candidates and, using
/// `TasteScorer`, picks the single best beer to order.
///
/// Ported from the validated Python prototype with the two known flaws fixed:
///   1. Junk non-beer lines are dropped by a parse-confidence floor — a line is
///      only kept if it has *some* beer signal (inferable style, an ABV, or a
///      price) and is not a bare section header.
///   2. Top-score ties are resolved deterministically by `TasteScorer.ranksAhead`
///      (closer-to-ideal ABV, then higher liked-style weight, then name order)
///      rather than by input list order.
enum MenuParser {

    // MARK: - Result

    /// Outcome of evaluating a whole menu.
    struct MenuVerdict {
        /// Every candidate, ranked best-first (already assessed & tiebroken).
        let ranked: [TasteScorer.AssessedCandidate]
        /// The single clear winner, or `nil` if the menu yielded no candidates.
        var winner: TasteScorer.AssessedCandidate? { ranked.first }
    }

    // MARK: - Public API

    /// Parse a raw OCR menu blob into beer candidates, applying the
    /// confidence floor that drops junk / non-beer lines.
    static func parse(_ blob: String) -> [BeerCandidate] {
        var candidates: [BeerCandidate] = []

        for rawLine in blob.split(whereSeparator: { $0.isNewline }) {
            // Trim surrounding whitespace and common bullet / divider glyphs.
            let line = String(rawLine).trimmingCharacters(in: lineTrimSet)
            guard line.count >= 3 else { continue }
            if isSectionHeader(line) { continue }

            let abv = extractABV(from: line)
            let hasPrice = priceRegex.firstMatch(in: line) != nil

            // Strip price / ABV / serving noise to recover the beer name.
            let stripped = stripNoise(from: line)
            let name = stripped.trimmingCharacters(in: nameTrimSet)
            guard name.count >= 3 else { continue }

            let style = TasteScorer.inferStyle(from: name)

            // ---- Confidence floor (flaw #1 fix) ---------------------------
            // Keep the line only if it shows real beer signal: an inferable
            // style, OR an explicit ABV, OR a price. A line with none of these
            // is almost certainly menu chrome ("Happy Hour", "Cheers!", etc.).
            // A line that is NOTHING BUT style vocabulary ("IPAs", "Sours",
            // "Belgian Ales") is a section header wearing a style — it would
            // otherwise outrank real beers whose style matches the user less.
            guard abv != nil || hasPrice || (style != nil && !isStyleOnlyName(name)) else { continue }

            candidates.append(
                BeerCandidate(rawLine: line, name: name, style: style, abv: abv)
            )
        }

        return candidates
    }

    /// Evaluate a menu blob end-to-end: parse, score every candidate against
    /// the taste library, and rank with the deterministic tiebreaker.
    static func evaluate(
        _ blob: String,
        profile: TasteProfile,
        preferences: TastePreferences
    ) -> MenuVerdict {
        let candidates = parse(blob)
        return evaluate(candidates: candidates, profile: profile, preferences: preferences)
    }

    /// Evaluate already-parsed candidates (kept separate for unit testing).
    static func evaluate(
        candidates: [BeerCandidate],
        profile: TasteProfile,
        preferences: TastePreferences
    ) -> MenuVerdict {
        let assessed: [TasteScorer.AssessedCandidate] = candidates.map { candidate in
            let assessment = TasteScorer.assess(
                name: candidate.name,
                style: candidate.style,
                abv: candidate.abv,
                profile: profile,
                preferences: preferences
            )
            return TasteScorer.AssessedCandidate(
                name: candidate.name,
                style: candidate.style,
                abv: candidate.abv,
                assessment: assessment
            )
        }

        let ranked = assessed.sorted { lhs, rhs in
            TasteScorer.ranksAhead(lhs, rhs, profile: profile, preferences: preferences)
        }

        return MenuVerdict(ranked: ranked)
    }

    /// Convenience: pick just the single best beer from a menu blob.
    static func pickWinner(
        from blob: String,
        profile: TasteProfile,
        preferences: TastePreferences
    ) -> TasteScorer.AssessedCandidate? {
        evaluate(blob, profile: profile, preferences: preferences).winner
    }

    // MARK: - Line Classification

    /// Characters trimmed from the edges of a raw menu line (bullets, dividers).
    private static let lineTrimSet: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.insert(charactersIn: "-•·|\t")
        return set
    }()

    /// Characters trimmed from the edges of a recovered beer name.
    /// Includes list punctuation — "HAZY IPA, 6.5%" left a trailing comma
    /// after noise-stripping and shipped "HAZY IPA," as the beer's name
    /// (founder bug video 2026-07-07).
    private static let nameTrimSet: CharacterSet = {
        var set = CharacterSet.whitespaces
        set.insert(charactersIn: ".-—|,;:•·")
        return set
    }()

    /// Matches bare section headers like "ON TAP", "Drafts:", "Bottles", "Beer".
    private static let sectionRegex = makeRegex(
        "^\\s*(on tap|drafts?|bottles?|cans?|beer|menu|drinks?)\\s*:?\\s*$"
    )

    /// Matches a price token, e.g. `$9`, `$7.50`.
    private static let priceRegex = makeRegex("\\$\\s?\\d+(?:\\.\\d{2})?")

    /// Matches an ABV percentage, e.g. `6.7%`, `9 %`.
    private static let abvRegex = makeRegex("(\\d{1,2}(?:\\.\\d{1,2})?)\\s?%(?!\\s*off\\b)")

    /// Matches all serving / price / ABV / IBU noise to strip from a name.
    /// Includes the keyword ABV forms ("ABV: 7.0", "7 ABV") now that
    /// extractABV accepts them — otherwise they'd survive into the display
    /// name and break exact-match history lookups.
    private static let noiseRegex = makeRegex(
        "(\\$\\s?\\d+(?:\\.\\d{2})?|alc(?:ohol)?\\.?[: \\t]{0,3}\\d{1,2}(?:\\.\\d{1,2})?(?:[ \\t]*%?[ \\t]*(?:by|/)?[ \\t]*vol\\.?)?|\\d{1,2}(?:\\.\\d{1,2})?\\s?%|abv[: \\t]{0,3}\\d{1,2}(?:\\.\\d{1,2})?|\\d{1,2}(?:\\.\\d{1,2})?[ \\t]{0,2}abv|ibu[: \\t]{0,3}\\d{1,3}|\\d{1,3}[ \\t]{0,2}ibu|\\babv\\b:?|\\bibu\\b:?|\\bpint\\b|\\bdraft\\b|\\b1/2\\b)"
    )

    /// Collapses runs of 2+ whitespace into a single space.
    private static let multiSpaceRegex = makeRegex("\\s{2,}")

    private static func isSectionHeader(_ line: String) -> Bool {
        sectionRegex.firstMatch(in: line) != nil
    }

    /// Style/menu vocabulary that, alone, marks a section header rather than a
    /// beer name ("IPAs", "Dark Beers", "Local Drafts").
    private static let styleHeaderWords: Set<String> = [
        "ipa", "stout", "porter", "sour", "lager", "pilsner", "pils", "ale",
        "wheat", "belgian", "amber", "brown", "pale", "hazy", "dark", "light",
        "beer", "draft", "bottle", "can", "seasonal", "local", "craft",
        "specialty", "premium", "domestic", "import", "rotating", "guest"
    ]

    /// True for section headers wearing a style: a single style word ("IPAs",
    /// "Stout") or a style-only phrase with a PLURAL style word ("Belgian
    /// Ales", "Wheat Beers"). Singular multi-word style phrases stay beers —
    /// taprooms really do sell an "Amber Ale" or "Hazy IPA" by that exact name,
    /// and dropping them broke price-less chalkboard menus entirely.
    private static func isStyleOnlyName(_ name: String) -> Bool {
        let tokens = name.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        guard !tokens.isEmpty, tokens.count <= 3 else { return false }

        var sawPlural = false
        for token in tokens {
            let singular = token.hasSuffix("s") ? String(token.dropLast()) : token
            guard styleHeaderWords.contains(token) || styleHeaderWords.contains(singular) else {
                return false
            }
            if token.hasSuffix("s"), styleHeaderWords.contains(singular) { sawPlural = true }
        }
        return tokens.count == 1 || sawPlural
    }

    /// Plausible ABV range for a beer. Bounds reject menu chrome such as
    /// "Save 50% today" or "20% off" being misread as a beer's strength.
    private static let plausibleABV: ClosedRange<Double> = 0.5...20.0

    /// "ABV 5.6" / "ABV: 5.6" — the keyword LEADS, so an IBU number sitting
    /// before the word ABV ("IBU 18 ABV 4.2") can't hijack the read. Spacing
    /// is space/tab only: label blobs are multi-line, and \s would let "ABV\n12
    /// FL OZ" bind the ounces as strength.
    private static let abvLeadingKeywordRegex = makeRegex(
        "abv[: \\t]{1,3}(\\d{1,2}(?:\\.\\d{1,2})?)"
    )
    /// "5.6 ABV" — checked only after the leading-keyword form.
    private static let abvTrailingKeywordRegex = makeRegex(
        "(\\d{1,2}(?:\\.\\d{1,2})?)[ \\t]{0,2}abv"
    )
    /// "ALC. 5.9 BY VOL" — common on imported bottles without a percent sign.
    private static let alcoholLeadingKeywordRegex = makeRegex(
        "alc(?:ohol)?\\.?[: \\t]{1,3}(\\d{1,2}(?:\\.\\d{1,2})?)(?:[ \\t]*%?[ \\t]*(?:by|/)?[ \\t]*vol\\.?)?"
    )

    /// Extract the first *plausible* ABV percentage from a line, if present.
    /// Scans ALL %-tokens (not just the first — "20% off … 5.6%" must find the
    /// 5.6) and falls back to keyword forms with no % sign ("ABV: 5.6").
    static func extractABV(from line: String) -> Double? {
        let fullRange = NSRange(line.startIndex..., in: line)

        for regex in [abvRegex, abvLeadingKeywordRegex, abvTrailingKeywordRegex, alcoholLeadingKeywordRegex] {
            for match in regex.matches(in: line, options: [], range: fullRange) {
                if let captureRange = Range(match.range(at: 1), in: line),
                   let value = Double(line[captureRange]),
                   plausibleABV.contains(value) {
                    return value
                }
            }
        }
        return nil
    }

    /// Remove price / ABV / serving noise from a line and collapse whitespace.
    private static func stripNoise(from line: String) -> String {
        let fullRange = NSRange(line.startIndex..., in: line)
        let withoutNoise = noiseRegex.stringByReplacingMatches(
            in: line, range: fullRange, withTemplate: ""
        )
        let collapsedRange = NSRange(withoutNoise.startIndex..., in: withoutNoise)
        return multiSpaceRegex.stringByReplacingMatches(
            in: withoutNoise, range: collapsedRange, withTemplate: " "
        )
    }

    // MARK: - Regex Helper

    /// Build a case-insensitive `NSRegularExpression`. Patterns here are static
    /// and known-valid, so a failure is a programmer error and we trap it.
    private static func makeRegex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            fatalError("Invalid MenuParser regex: \(pattern) — \(error)")
        }
    }
}

// MARK: - NSRegularExpression Convenience

private extension NSRegularExpression {
    /// First match across the whole string, or `nil`.
    func firstMatch(in string: String) -> NSTextCheckingResult? {
        firstMatch(in: string, range: NSRange(string.startIndex..., in: string))
    }
}
