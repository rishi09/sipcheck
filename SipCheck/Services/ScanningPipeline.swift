import UIKit

// MARK: - Scan Result

struct ScanResult {
    let beerInfo: BeerInfo
    let scanSource: ScanSource
    let latencyMs: Int

    enum ScanSource: String {
        case ocrPlusText = "ocr+text"           // Fast path: OCR -> text LLM
        case visionFallback = "vision-fallback"  // Slow path: full image to vision API
        case mock = "mock"
    }
}

// MARK: - Scanning Pipeline

class ScanningPipeline {
    static let shared = ScanningPipeline()

    private init() {}

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
            return ScanResult(beerInfo: mockInfo, scanSource: .mock, latencyMs: elapsed)
        }

        let beerInfo = try await extractBeerInfoFromText(text)
        let elapsed = latencyMs(since: start)
        return ScanResult(beerInfo: beerInfo, scanSource: .ocrPlusText, latencyMs: elapsed)
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
            return ScanResult(beerInfo: mockInfo, scanSource: .mock, latencyMs: elapsed)
        }

        // ------- Step 1: On-device OCR -------
        let ocrResult = await VisionOCRService.extractText(from: image)

        // ------- Step 2: Decide fast-path vs fallback -------
        if ocrResult.confidence >= 0.5 && ocrResult.text.count > 10 {
            // Fast path: send extracted text to a text LLM
            let beerInfo = try await extractBeerInfoFromText(ocrResult.text)
            let elapsed = latencyMs(since: start)
            return ScanResult(beerInfo: beerInfo, scanSource: .ocrPlusText, latencyMs: elapsed)
        }

        // ------- Step 3: Vision fallback (low confidence / short text) -------
        let extractionResult = try await OpenAIService.shared.extractBeerInfo(from: image)
        let beerInfo = BeerInfo(
            name: extractionResult.name ?? "Unknown",
            brand: extractionResult.brand ?? "Unknown",
            style: extractionResult.style,
            abv: nil,
            origin: extractionResult.origin
        )
        let elapsed = latencyMs(since: start)
        return ScanResult(beerInfo: beerInfo, scanSource: .visionFallback, latencyMs: elapsed)
    }

    // MARK: - Private Helpers

    /// Use Gemini if a key is configured; otherwise fall back to OpenAI for text-based extraction.
    private func extractBeerInfoFromText(_ text: String) async throws -> BeerInfo {
        let gemini = GeminiService()
        return try await gemini.extractBeerInfo(fromText: text)
    }

    /// Milliseconds elapsed since a `CFAbsoluteTimeGetCurrent()` timestamp.
    private func latencyMs(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
}
