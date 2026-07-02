import Foundation
import UIKit
import Vision

/// On-device OCR using Apple Vision framework for beer label text extraction.
/// Uses .accurate recognition level to handle stylized fonts common on beer labels.
/// Fully on-device - no network required.
enum VisionOCRService {

    /// Extract all recognized text from an image using Vision OCR.
    /// - Parameter image: The source UIImage (e.g., a photo of a beer label).
    /// - Returns: A tuple of the combined recognized text and the average confidence score (0.0-1.0).
    ///           Returns empty text with 0.0 confidence if no text is found or the image cannot be processed.
    static func extractText(from image: UIImage) async -> (text: String, confidence: Float) {
        guard let cgImage = image.cgImage else {
            return ("", 0.0)
        }

        return await withCheckedContinuation { continuation in
            // VNRecognizeTextRequest's completion runs synchronously inside
            // handler.perform on this thread; the flag guards the (rare) path
            // where perform throws after the completion already resumed.
            var resumed = false
            let resumeOnce: ((text: String, confidence: Float)) -> Void = { result in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: result)
            }

            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation],
                      !observations.isEmpty else {
                    resumeOnce(("", 0.0))
                    return
                }

                // Sort observations top-to-bottom, left-to-right for natural reading order
                let sorted = observations.sorted { a, b in
                    // Vision coordinates have origin at bottom-left; higher y = higher on screen
                    if abs(a.boundingBox.midY - b.boundingBox.midY) > 0.02 {
                        return a.boundingBox.midY > b.boundingBox.midY
                    }
                    return a.boundingBox.midX < b.boundingBox.midX
                }

                var texts: [String] = []
                var totalConfidence: Float = 0.0

                for observation in sorted {
                    // Take the top candidate for each observation
                    guard let candidate = observation.topCandidates(1).first else {
                        continue
                    }
                    let line = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !line.isEmpty {
                        texts.append(line)
                        totalConfidence += candidate.confidence
                    }
                }

                if texts.isEmpty {
                    resumeOnce(("", 0.0))
                    return
                }

                let combinedText = texts.joined(separator: "\n")
                let averageConfidence = totalConfidence / Float(texts.count)

                resumeOnce((combinedText, averageConfidence))
            }

            // Configure for beer label text: accurate recognition handles stylized fonts better
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            // CRITICAL: pass the photo's orientation. UIImagePickerController's
            // portrait captures store landscape pixels + an orientation flag;
            // without it Vision OCRs the label sideways and reads nothing.
            let orientation = cgOrientation(from: image.imageOrientation)
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

            do {
                try handler.perform([request])
            } catch {
                resumeOnce(("", 0.0))
            }
        }
    }

    /// UIImage.Orientation → CGImagePropertyOrientation (no built-in bridge).
    private static func cgOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
