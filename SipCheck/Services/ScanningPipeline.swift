import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Scan Result

struct ScanResult {
    let beerInfo: BeerInfo
    let verdict: Verdict
    let explanation: String
    let scanSource: ScanSource
    let latencyMs: Int

    enum ScanSource: String {
        case ocrPlusText = "ocr+text"           // Fast path: OCR -> text LLM
        case visionFallback = "vision-fallback"  // Slow path: full image to vision API
        case mock = "mock"
    }
}

// MARK: - Post-Verdict Enrichment

/// Model-sourced beer facts for a verdict already on screen. There is no verdict
/// field on purpose: after facts arrive, the app runs the deterministic local
/// scorer again. The model resolves the beer; it never personalizes the answer.
struct Enrichment {
    var name: String?
    var brand: String?
    var style: BeerStyle?
    var abv: Double?
    var origin: String?
    var explanation: String?

    /// True when the model produced nothing usable.
    var isEmpty: Bool {
        name == nil && brand == nil && style == nil && abv == nil && origin == nil && explanation == nil
    }

    func addingLocalExplanation(for verdict: Verdict) -> Enrichment {
        guard explanation == nil, let style else { return self }
        var result = self
        switch verdict {
        case .tryIt:
            result.explanation = "Looks like a \(style.displayName) — that lines up with your taste."
        case .skipIt:
            result.explanation = "Looks like a \(style.displayName), which is outside your usual lane."
        case .yourCall:
            result.explanation = "Looks like a \(style.displayName), but your history doesn't point strongly either way."
        }
        return result
    }
}

/// Optional iOS 26 beer knowledge. This is a free, offline resolver tier used
/// after the deterministic verdict is already visible; unsupported devices and
/// disabled/not-ready Apple Intelligence simply return nil.
enum OnDeviceBeerKnowledge {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    static var availabilityDescription: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "available"
            case .unavailable(.deviceNotEligible):
                return "device not eligible"
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Apple Intelligence disabled"
            case .unavailable(.modelNotReady):
                return "model not ready"
            @unknown default:
                return "unavailable"
            }
        }
        #endif
        return "requires iOS 26"
    }

    static func prewarm() {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), isAvailable else { return }
        Task { await FoundationModelBeerResolver.shared.prewarm() }
        #endif
    }

    static func enrich(text: String, candidateName: String? = nil, deviceVerdict: Verdict) async -> Enrichment? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), isAvailable else { return nil }
        return await FoundationModelBeerResolver.shared.enrich(
            text: text,
            candidateName: candidateName,
            verdict: deviceVerdict
        )
        #else
        return nil
        #endif
    }
}

/// Keeps optional model work proportional to uncertainty. A clean printed
/// style or high-confidence catalog hit is already final and must not spend a
/// paid request merely to decorate the card.
enum EnrichmentPolicy {
    static func shouldStart(
        nameIsGuess: Bool,
        startedStyleless: Bool,
        isMenu: Bool,
        onDeviceAvailable: Bool,
        onlineAvailable: Bool
    ) -> Bool {
        guard !isMenu else { return false }
        // Text-only Foundation Models proved unreliable for graphic-label OCR
        // in physical tests. Guessed camera identities require an image-aware
        // provider; trusted typed/catalog names can still use the free model.
        if nameIsGuess { return onlineAvailable }
        if startedStyleless { return onDeviceAvailable || onlineAvailable }
        return false
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private actor FoundationModelBeerResolver {
    static let shared = FoundationModelBeerResolver()

    private static let instructions = """
        You identify beer from OCR text or a typed name. Return only compact
        facts when reasonably confident. OCR fragments can be wrong. Never
        repeat gibberish as a beer name and never invent an ABV.
        """
    private let warmupSession = LanguageModelSession(instructions: instructions)

    func prewarm() {
        warmupSession.prewarm()
    }

    func enrich(text: String, candidateName: String?, verdict: Verdict) async -> Enrichment? {
        let candidateContext = candidateName.map {
            "OCR-derived name candidate (possibly partial or wrong): \($0)\n"
        } ?? ""
        let prompt = """
            \(candidateContext)OCR context:
            \(text)

            Respond with only one compact JSON object:
            {"name":"canonical beer name or null","brand":"brewery or null","style":"IPA, Pale Ale, Lager, Pilsner, Stout, Porter, Wheat, Sour, Amber, Brown Ale, Belgian, Other, or null","abv":5.5,"origin":"country or city or null"}
            Prefer an explicit printed style. Ingredient words such as "hops"
            do not imply IPA. Use null when uncertain. Do not add an explanation,
            markdown, or text outside the JSON.
            """

        do {
            // LanguageModelSession keeps a transcript. A fresh session per
            // lookup prevents a run of IPA scans from biasing the next beer.
            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await session.respond(
                to: prompt,
                options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 120)
            )
            guard let enrichment = ScanningPipeline.parseEnrichment(response.content) else {
                #if DEBUG
                print("FOUNDATION_MODEL parse failed content=\(response.content)")
                #endif
                return nil
            }
            return enrichment.addingLocalExplanation(for: verdict)
        } catch {
            #if DEBUG
            print("FOUNDATION_MODEL error type=\(type(of: error)) description=\(error)")
            #endif
            return nil
        }
    }
}
#endif

// MARK: - Scanning Pipeline

class ScanningPipeline {
    static let shared = ScanningPipeline()

    private init() {}

    // MARK: - Enrichment (post-verdict, never on the critical path)

    /// Whether a refinement attempt is worth starting right now — a usable
    /// network path plus at least one configured provider. Callers use this to
    /// decide whether to show a "refining…" hint; offline it stays false and no
    /// network work starts at all.
    var canEnrich: Bool {
        OnDeviceBeerKnowledge.isAvailable || canEnrichOnline
    }

    var canEnrichOnline: Bool {
        if OpenAIService.useMockResponses { return true }
        guard NetworkMonitor.shared.isSatisfied else { return false }
        return !Config.geminiAPIKey.isEmpty || !Config.openAIAPIKey.isEmpty
    }

    var canEnrichVision: Bool {
        if OpenAIService.useMockResponses { return true }
        return NetworkMonitor.shared.isSatisfied && !Config.openAIAPIKey.isEmpty
    }

    /// One merged network round trip (extraction + explanation copy) inside a
    /// hard time budget. Returns nil offline, with no provider, over budget, on
    /// cancellation, or when the model produced nothing usable — the caller's
    /// on-device verdict simply stands unrefined.
    ///
    /// Pass `image` when the OCR text is weak/guessed: if the text prompt can't
    /// identify the beer, the same budget covers a vision extraction so graphic
    /// labels with garbage OCR can still be named.
    func enrich(
        text: String,
        candidateName: String? = nil,
        image: UIImage? = nil,
        nameIsGuess: Bool = false,
        startedStyleless: Bool = false,
        deviceVerdict: Verdict,
        budgetSeconds: Double = 5.0
    ) async -> Enrichment? {
        if OpenAIService.useMockResponses {
            // Verdict-aware so mock copy never argues with the on-device badge.
            let copy: String
            switch deviceVerdict {
            case .tryIt: copy = "Based on your taste profile, this looks like a solid match. Give it a shot!"
            case .skipIt: copy = "Not your usual lane — probably one to skip."
            case .yourCall: copy = "Could go either way for you — trust your gut."
            }
            return Enrichment(
                name: nil,
                brand: "Mock Brewery",
                style: .ipa,
                abv: 6.5,
                origin: "Mock Brewery was founded in 2005 in Portland, Oregon.",
                explanation: copy
            )
        }

        // A guessed graphic label must be resolved visually. Physical tests
        // showed that text-only Foundation Models confidently mislabeled
        // Orion, Tusker, and Tyskie from OCR fragments. If visual resolution
        // fails, preserve the honest instant verdict instead of accepting a
        // partial text guess.
        if nameIsGuess {
            guard let image, canEnrichVision else { return nil }
            let fromVision: Enrichment? = await Self.withTimeout(seconds: budgetSeconds) {
                guard let vision = try? await OpenAIService.shared.extractBeerInfo(
                    from: image,
                    ocrText: text,
                    candidateName: candidateName
                ) else { return nil }
                return Self.visualIdentityEnrichment(from: vision, verdict: deviceVerdict)
            }
            return fromVision
        }

        if startedStyleless {
            if let local = await OnDeviceBeerKnowledge.enrich(
                text: text,
                candidateName: candidateName,
                deviceVerdict: deviceVerdict
            ), local.style != nil || local.abv != nil {
                return local
            }
        }
        guard canEnrichOnline else { return nil }

        let prompt = Self.enrichmentPrompt(text: text, candidateName: candidateName)

        return await Self.withTimeout(seconds: budgetSeconds) {
            // Gemini gets the first slice of the budget; OpenAI is the fallback.
            if !Config.geminiAPIKey.isEmpty {
                let fromGemini: Enrichment? = await Self.withTimeout(seconds: min(3.0, budgetSeconds)) {
                    guard let raw = try? await GeminiService.shared.complete(prompt: prompt) else { return nil }
                    return Self.parseEnrichment(raw)?.addingLocalExplanation(for: deviceVerdict)
                }
                if let fromGemini { return fromGemini }
            }
            if Task.isCancelled { return nil }
            if !Config.openAIAPIKey.isEmpty,
               let raw = try? await OpenAIService.shared.complete(prompt: prompt),
               let parsed = Self.parseEnrichment(raw) {
                return parsed.addingLocalExplanation(for: deviceVerdict)
            }
            if Task.isCancelled { return nil }
            // Text failed to identify anything; if the caller shared the frame,
            // let the vision API read the graphic label directly.
            if let image, !Config.openAIAPIKey.isEmpty,
               let vision = try? await OpenAIService.shared.extractBeerInfo(
                   from: image,
                   ocrText: text,
                   candidateName: candidateName
               ) {
                let fromVision = Enrichment(
                    name: vision.name,
                    brand: vision.brand,
                    style: vision.style,
                    abv: nil,
                    origin: vision.origin,
                    explanation: nil
                )
                if !fromVision.isEmpty { return fromVision.addingLocalExplanation(for: deviceVerdict) }
            }
            return nil
        }
    }

    private static func enrichmentPrompt(text: String, candidateName: String?) -> String {
        let candidateContext = candidateName.map {
            "OCR-derived name candidate (possibly partial or wrong): \($0)\n"
        } ?? ""
        return """
        Identify this beer using compact facts only.
        \(candidateContext)OCR context:
        \(text)

        Respond ONLY with one JSON object:
        {"name":"canonical beer name or null","brand":"brewery or null","style":"IPA, Pale Ale, Lager, Pilsner, Stout, Porter, Wheat, Sour, Amber, Brown Ale, Belgian, Other, or null","abv":5.5,"origin":"country or city or null"}
        Prefer an explicit printed style. Ingredient words such as "hops" do
        not imply IPA. Use null when uncertain. No explanation, markdown, or
        text outside the JSON.
        """
    }

    static func parseEnrichment(_ raw: String) -> Enrichment? {
        guard let jsonStart = raw.firstIndex(of: "{"),
              let jsonEnd = raw.lastIndex(of: "}"),
              let jsonData = String(raw[jsonStart...jsonEnd]).data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any?] else {
            return nil
        }

        var result = Enrichment()
        result.name = nonEmpty(parsed["name"] as? String)
        result.brand = nonEmpty(parsed["brand"] as? String)
        if let styleString = parsed["style"] as? String {
            result.style = BeerStyle.allCases.first { $0.rawValue.lowercased() == styleString.lowercased() }
        }
        if let abvNumber = parsed["abv"] as? Double {
            result.abv = abvNumber
        } else if let abvString = parsed["abv"] as? String {
            result.abv = Double(abvString.replacingOccurrences(of: ",", with: "."))
        }
        result.origin = nonEmpty(parsed["origin"] as? String)
        result.explanation = nonEmpty(parsed["explanation"] as? String)

        return result.isEmpty ? nil : result
    }

    /// A guessed camera label is corrected only when the visual provider can
    /// actually name the package. Style-only partial responses are not enough
    /// to replace an honest unresolved verdict.
    static func visualIdentityEnrichment(
        from vision: OpenAIService.BeerExtractionResult,
        verdict: Verdict
    ) -> Enrichment? {
        guard let name = nonEmpty(vision.name) else { return nil }
        return Enrichment(
            name: name,
            brand: vision.brand,
            style: vision.style,
            abv: nil,
            origin: vision.origin,
            explanation: nil
        ).addingLocalExplanation(for: verdict)
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty, s.lowercased() != "null" else { return nil }
        return s
    }

    /// Race an operation against a deadline; the loser is cancelled (URLSession
    /// honors task cancellation, so in-flight requests genuinely stop).
    private static func withTimeout<T: Sendable>(
        seconds: Double,
        _ operation: @escaping @Sendable () async -> T?
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Scan a beer by text description (name / label text) and return structured beer information.
    func scan(text: String) async throws -> ScanResult {
        let start = CFAbsoluteTimeGetCurrent()

        if OpenAIService.useMockResponses {
            let mockInfo = BeerInfo(
                name: text.isEmpty ? "Mock IPA" : text,
                brand: "Mock Brewery",
                style: .ipa,
                abv: 6.5,
                origin: "Mock Brewery was founded in 2005 in Portland, Oregon. They've been brewing bold IPAs ever since."
            )
            let elapsed = latencyMs(since: start)
            return ScanResult(beerInfo: mockInfo, verdict: .tryIt, explanation: "Based on your taste profile, this looks like a solid match. Give it a shot!", scanSource: .mock, latencyMs: elapsed)
        }

        let beerInfo = try await extractBeerInfoFromText(text)
        let (verdict, explanation) = await getVerdictAndExplanation(for: beerInfo)
        let elapsed = latencyMs(since: start)
        return ScanResult(beerInfo: beerInfo, verdict: verdict, explanation: explanation, scanSource: .ocrPlusText, latencyMs: elapsed)
    }

    /// Scan a beer label image and return structured beer information.
    ///
    /// Pipeline order:
    /// 1. On-device Apple Vision OCR (fast, ~100ms)
    /// 2. If OCR yields usable text -> send text to Gemini (or OpenAI text fallback)
    /// 3. If OCR confidence is too low -> fall back to OpenAI Vision API with the full image
    func scan(image: UIImage) async throws -> ScanResult {
        let start = CFAbsoluteTimeGetCurrent()

        // ------- Mock mode -------
        if OpenAIService.useMockResponses {
            let mockInfo = BeerInfo(
                name: "Mock IPA",
                brand: "Mock Brewery",
                style: .ipa,
                abv: 6.5,
                origin: "Mock Brewery was founded in 2005 in Portland, Oregon. They've been brewing bold IPAs ever since."
            )
            let elapsed = latencyMs(since: start)
            return ScanResult(beerInfo: mockInfo, verdict: .tryIt, explanation: "Based on your taste profile, this looks like a solid match. Give it a shot!", scanSource: .mock, latencyMs: elapsed)
        }

        // ------- Step 1: On-device OCR -------
        let ocrResult = await VisionOCRService.extractText(from: image)

        // ------- Step 2: Decide fast-path vs fallback -------
        if ocrResult.confidence >= 0.5 && ocrResult.text.count > 3 {
            // Fast path: send extracted text to a text LLM
            let beerInfo = try await extractBeerInfoFromText(ocrResult.text)
            let (verdict, explanation) = await getVerdictAndExplanation(for: beerInfo)
            let elapsed = latencyMs(since: start)
            return ScanResult(beerInfo: beerInfo, verdict: verdict, explanation: explanation, scanSource: .ocrPlusText, latencyMs: elapsed)
        }

        // ------- Step 3: Vision fallback (low confidence / short text) -------
        let beerInfo: BeerInfo
        if let extractionResult = try? await OpenAIService.shared.extractBeerInfo(from: image) {
            beerInfo = BeerInfo(
                name: extractionResult.name ?? "Unknown",
                brand: extractionResult.brand ?? "Unknown",
                style: extractionResult.style,
                abv: nil,
                origin: extractionResult.origin
            )
        } else {
            // No vision provider available — stub from whatever OCR found so the
            // flow completes and the user can fill in details manually.
            let ocrText = ocrResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
            beerInfo = BeerInfo(name: ocrText.isEmpty ? "Unknown Beer" : ocrText, brand: nil, style: nil, abv: nil, origin: nil)
        }
        let (verdict, explanation) = await getVerdictAndExplanation(for: beerInfo)
        let elapsed = latencyMs(since: start)
        return ScanResult(beerInfo: beerInfo, verdict: verdict, explanation: explanation, scanSource: .visionFallback, latencyMs: elapsed)
    }

    // MARK: - Private Helpers

    /// Use Gemini if a key is configured; otherwise fall back to OpenAI; if no
    /// provider is available, return stub info so the flow still completes.
    private func extractBeerInfoFromText(_ text: String) async throws -> BeerInfo {
        if !Config.geminiAPIKey.isEmpty,
           let info = try? await GeminiService.shared.extractBeerInfo(fromText: text) {
            return info
        }
        if let info = try? await OpenAIService.shared.extractBeerInfo(fromText: text) {
            return info
        }
        // No AI provider available (e.g. API keys not configured) — return stub
        // info built from the input so the scan flow still completes end-to-end
        // and the user can edit the details manually.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return BeerInfo(name: trimmed.isEmpty ? "Unknown Beer" : trimmed, brand: nil, style: nil, abv: nil, origin: nil)
    }

    /// Milliseconds elapsed since a `CFAbsoluteTimeGetCurrent()` timestamp.
    private func latencyMs(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }

    /// Use Gemini if a key is configured; otherwise fall back to OpenAI for the verdict.
    private func getVerdictAndExplanation(for beerInfo: BeerInfo) async -> (Verdict, String) {
        if !Config.geminiAPIKey.isEmpty,
           let result = try? await GeminiService.shared.getVerdictAndExplanation(for: beerInfo) {
            return result
        }
        if let result = try? await OpenAIService.shared.getVerdictAndExplanation(for: beerInfo) {
            return result
        }
        return (.yourCall, "Give it a try and see what you think!")
    }
}
