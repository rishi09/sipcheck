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
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation],
                      !observations.isEmpty else {
                    continuation.resume(returning: ("", 0.0))
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
                    continuation.resume(returning: ("", 0.0))
                    return
                }

                let combinedText = texts.joined(separator: "\n")
                let averageConfidence = totalConfidence / Float(texts.count)

                continuation.resume(returning: (combinedText, averageConfidence))
            }

            // Configure for beer label text: accurate recognition handles stylized fonts better
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: ("", 0.0))
            }
        }
    }
}
