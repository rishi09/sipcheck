import Foundation
import UIKit
import Vision

/// On-device OCR using Apple Vision framework for beer label text extraction.
/// Uses fast recognition first, with small accurate repairs for stylized text.
/// Fully on-device - no network required.
enum VisionOCRService {

    /// Pay Vision's one-time model load while the user is looking at the check
    /// screen, not after they choose a frame. This never touches the network;
    /// the recognizer work runs off the main actor.
    static func warmUp() async {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: 900, height: 1_200)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 72),
                .foregroundColor: UIColor.black
            ]
            ("SAMPLE BREWERY" as NSString).draw(at: CGPoint(x: 110, y: 380), withAttributes: attributes)
            ("PALE ALE" as NSString).draw(at: CGPoint(x: 240, y: 500), withAttributes: attributes)
            ("6.5% ABV" as NSString).draw(at: CGPoint(x: 270, y: 620), withAttributes: attributes)
        }
        guard let cgImage = image.cgImage else { return }
        _ = await Task.detached(priority: .utility) {
            recognize(cgImage, level: .fast)
        }.value
    }

    /// Extract all recognized text from an image using Vision OCR.
    /// - Parameter image: The source UIImage (e.g., a photo of a beer label).
    /// - Returns: A tuple of the combined recognized text and the average confidence score (0.0-1.0).
    ///           Returns empty text with 0.0 confidence if no text is found or the image cannot be processed.
    static func extractText(from image: UIImage) async -> (text: String, confidence: Float) {
        guard let cgImage = preparedCGImage(from: image) else {
            return ("", 0.0)
        }

        // Normal labels take the fast path. Real grocery photos showed that
        // Vision's fast confidence can sit around 0.4-0.6 while a stylized
        // logo is still badly fragmented, so reserve that result for genuinely
        // clear frames and repair the rest with accurate recognition.
        let fast = await Task.detached(priority: .userInitiated) {
            recognize(cgImage, level: .fast)
        }.value
        if fast.confidence >= 0.65, fast.text.rangeOfCharacter(from: .letters) != nil {
            return fast
        }

        return await Task.detached(priority: .userInitiated) {
            recognize(cgImage, level: .accurate)
        }.value
    }

    private static func recognize(
        _ cgImage: CGImage,
        level: VNRequestTextRecognitionLevel
    ) -> (text: String, confidence: Float) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = true

        // `preparedCGImage` renders orientation into the pixels and caps large
        // camera frames, so Vision always receives an upright bounded image.
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observations = request.results,
              !observations.isEmpty else { return ("", 0.0) }

        let sorted = observations.sorted { a, b in
            if abs(a.boundingBox.midY - b.boundingBox.midY) > 0.02 {
                return a.boundingBox.midY > b.boundingBox.midY
            }
            return a.boundingBox.midX < b.boundingBox.midX
        }

        var lines = sorted.compactMap { observation -> (text: String, confidence: Float, box: CGRect)? in
            let alternatives = observation.topCandidates(5)
            guard let candidate = alternatives.first(where: { unexpectedCharacterCount(in: $0.string) == 0 })
                    ?? alternatives.first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return (text, candidate.confidence, observation.boundingBox)
        }

        // Fast OCR is usually enough, but stylized logos can be returned with
        // symbol substitutions ("Q¢ion"). Re-read only that word's small
        // rectangle accurately; this is much cheaper than a second full-frame
        // request and preserves the responsive default path.
        if level == .fast,
           let repairIndex = lines.firstIndex(where: { shouldRepair($0.text) }) {
            let region = expandedRegion(around: lines[repairIndex].box)
            let repairImage = croppedImage(cgImage, to: region) ?? cgImage
            let repair = recognize(repairImage, level: .accurate)
            let replacement = BeerResolver.suggestedLabelName(from: repair.text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !replacement.isEmpty,
               recognitionNoiseScore(in: replacement) < recognitionNoiseScore(in: lines[repairIndex].text) {
                lines[repairIndex].text = replacement
                lines[repairIndex].confidence = repair.confidence
            }
        }

        guard !lines.isEmpty else { return ("", 0.0) }

        let totalConfidence = lines.reduce(Float.zero) { $0 + $1.confidence }
        return (lines.map(\.text).joined(separator: "\n"), totalConfidence / Float(lines.count))
    }

    /// Fast recognition occasionally ranks a symbol-confused string (for
    /// example "Q¢ion") above a clean alternate. Vision's candidates are
    /// already confidence-ordered, so take the first one made of ordinary
    /// label characters before falling back to its top result.
    private static func unexpectedCharacterCount(in text: String) -> Int {
        var allowed = CharacterSet.alphanumerics
        allowed.formUnion(.whitespacesAndNewlines)
        allowed.formUnion(CharacterSet(charactersIn: "&'\".,;:!?()-+–—/\\%$#@"))
        return text.unicodeScalars.count { !allowed.contains($0) }
    }

    private static func shouldRepair(_ text: String) -> Bool {
        let letterCount = text.unicodeScalars.count(where: CharacterSet.letters.contains)
        return letterCount >= 4 && text.count <= 42 && recognitionNoiseScore(in: text) > 0
    }

    /// Commas and periods are valid label characters, but inside an all-letter
    /// word they are a common fast-OCR substitution ("BIP.VIET" for
    /// "BIA VIET"). Count them as light noise so the existing accurate crop
    /// can repair the logo without penalizing normal punctuation elsewhere.
    private static func recognitionNoiseScore(in text: String) -> Int {
        let characters = Array(text)
        let internalPunctuation: Int
        if characters.count >= 3 {
            internalPunctuation = (1..<(characters.count - 1)).count { index in
                (characters[index] == "." || characters[index] == ",")
                    && characters[index - 1].isLetter
                    && characters[index + 1].isLetter
            }
        } else {
            internalPunctuation = 0
        }
        return unexpectedCharacterCount(in: text) * 10 + internalPunctuation
    }

    private static func expandedRegion(around box: CGRect) -> CGRect {
        let horizontal = max(0.04, box.width * 0.45)
        let vertical = max(0.025, box.height * 1.25)
        return box
            .insetBy(dx: -horizontal, dy: -vertical)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Vision boxes use a bottom-left normalized origin; CGImage crop rects use
    /// top-left pixels. Cropping before the accurate request avoids paying its
    /// full-frame preprocessing cost for a single suspicious logo word.
    private static func croppedImage(_ image: CGImage, to region: CGRect) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let pixelRect = CGRect(
            x: region.minX * width,
            y: (1 - region.maxY) * height,
            width: region.width * width,
            height: region.height * height
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard pixelRect.width >= 8, pixelRect.height >= 8 else { return nil }
        return image.cropping(to: pixelRect)
    }

    /// Normalize orientation and limit the longest edge before OCR. Rendering
    /// at scale 1 keeps the requested dimensions in pixels rather than points.
    private static func preparedCGImage(from image: UIImage, maxDimension: CGFloat = 1_800) -> CGImage? {
        guard let source = image.cgImage else { return nil }

        let swapsAxes: Bool
        switch image.imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            swapsAxes = true
        default:
            swapsAxes = false
        }

        let sourceWidth = CGFloat(swapsAxes ? source.height : source.width)
        let sourceHeight = CGFloat(swapsAxes ? source.width : source.height)
        let scale = min(1, maxDimension / max(sourceWidth, sourceHeight))
        let targetSize = CGSize(
            width: max(1, (sourceWidth * scale).rounded()),
            height: max(1, (sourceHeight * scale).rounded())
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let normalized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return normalized.cgImage
    }
}
