import UIKit

enum ImageCompressor {
    /// Compress and resize an image for API upload or storage.
    /// - Parameters:
    ///   - image: The source UIImage to compress.
    ///   - maxDimension: The largest allowed width or height (default 512pt).
    ///   - quality: JPEG compression quality 0...1 (default 0.7).
    /// - Returns: JPEG `Data`, or `nil` if rendering fails.
    static func compress(_ image: UIImage, maxDimension: CGFloat = 512, quality: CGFloat = 0.7) -> Data? {
        // 1. Calculate new size maintaining aspect ratio
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return nil }

        let widthRatio  = maxDimension / originalSize.width
        let heightRatio = maxDimension / originalSize.height
        let scale = min(widthRatio, heightRatio, 1.0) // never upscale

        let newSize = CGSize(
            width:  originalSize.width  * scale,
            height: originalSize.height * scale
        )

        // 2. Resize using UIGraphicsImageRenderer
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        // 3. Return JPEG data at specified quality
        return resizedImage.jpegData(compressionQuality: quality)
    }
}
