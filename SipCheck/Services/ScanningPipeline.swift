import UIKit

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

/// Network-sourced extras for a verdict already on screen. There is no verdict
/// field on purpose: the verdict is decided on-device and must never flip after
/// it has rendered (locked constraint — the network refines, it never decides).
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
}

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
        if OpenAIService.useMockResponses { return true }
        guard NetworkMonitor.shared.isSatisfied else { return false }
        return !Config.geminiAPIKey.isEmpty || !Config.openAIAPIKey.isEmpty
    }

    /// One merged network round trip (extraction + explanation copy) inside a
    /// hard time budget. Returns nil offline, with no provider, over budget, on
    /// cancellation, or when the model produced nothing usable — the caller's
    /// on-device verdict simply stands unrefined.
    func enrich(text: String, deviceVerdict: Verdict, budgetSeconds: Double = 5.0) async -> Enrichment? {
        if OpenAIService.useMockResponses {
            return Enrichment(
                name: nil,
                brand: "Mock Brewery",
                style: .ipa,
                abv: 6.5,
                origin: "Mock Brewery was founded in 2005 in Portland, Oregon.",
                explanation: "Based on your taste profile, this looks like a solid match. Give it a shot!"
            )
        }
        guard canEnrich else { return nil }

        let prompt = Self.enrichmentPrompt(text: text, verdict: deviceVerdict)

        return await Self.withTimeout(seconds: budgetSeconds) {
            // Gemini gets the first slice of the budget; OpenAI is the fallback.
            if !Config.geminiAPIKey.isEmpty {
                let fromGemini: Enrichment? = await Self.withTimeout(seconds: min(3.0, budgetSeconds)) {
                    guard let raw = try? await GeminiService.shared.complete(prompt: prompt) else { return nil }
                    return Self.parseEnrichment(raw)
                }
                if let fromGemini { return fromGemini }
            }
            if Task.isCancelled { return nil }
            if !Config.openAIAPIKey.isEmpty,
               let raw = try? await OpenAIService.shared.complete(prompt: prompt),
               let parsed = Self.parseEnrichment(raw) {
                return parsed
            }
            return nil
        }
    }

    private static func enrichmentPrompt(text: String, verdict: Verdict) -> String {
        let verdictText: String
        switch verdict {
        case .tryIt: verdictText = "TRY IT"
        case .skipIt: verdictText = "SKIP IT"
        case .yourCall: verdictText = "YOUR CALL"
        }
        let tasteContext = TastePreferences.current.promptSummary

        return """
        You are a friendly beer expert. The app has already shown the user its verdict \
        for this beer: \(verdictText) (decided on-device from their taste history). \
        Do not contradict or change that verdict.

        \(tasteContext.isEmpty ? "" : "\(tasteContext)\n\n")Beer (label text or typed name):
        \(text)

        Extract facts and write copy. Respond ONLY with a JSON object exactly like:
        {"name": "beer name or null", "brand": "brewery name or null", "style": "one of: IPA, Pale Ale, Lager, Pilsner, Stout, Porter, Wheat, Sour, Amber, Brown Ale, Belgian, Other — or null", "abv": 5.5, "origin": "1-2 sentence brewery origin story or null", "explanation": "1-2 friendly sentences written directly to the user, consistent with the verdict \(verdictText)"}

        Use null for anything you cannot determine. Do not include a verdict field.
        """
    }

    private static func parseEnrichment(_ raw: String) -> Enrichment? {
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
