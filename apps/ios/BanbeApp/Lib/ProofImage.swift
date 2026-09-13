import UIKit

/// Normalizes a picked receipt photo before it's handed to Supabase Storage —
/// the Swift counterpart of src/lib/proofUpload.js. See that file's header
/// comment for the full rationale: the 'pay-proof' bucket only allows
/// image/jpeg, image/png, image/webp and application/pdf, capped at 5 MB
/// (supabase/migrations/20260913000024_024_payments_and_documents.sql), and
/// a full-resolution iPhone camera photo commonly runs 6-12 MB on its own —
/// well past that cap regardless of format. `UIImage.jpegData` alone doesn't
/// know about that cap, so a `PhotosPicker` result was silently rejected by
/// the bucket for any receipt photo taken at full camera resolution.
enum ProofImage {
    static let maxBytes = 5 * 1024 * 1024
    private static let startMaxDimension: CGFloat = 2000
    private static let qualitySteps: [CGFloat] = [0.85, 0.7, 0.55, 0.4]

    /// Downscales `image` no larger than `maxDim` on its long edge, then
    /// tries each quality step until the resulting JPEG fits under
    /// `maxBytes` — shrinking further and repeating if even the lowest
    /// quality step doesn't. Always returns *something* (the smallest
    /// attempt) rather than looping forever, even if it can't get under
    /// the cap on a truly enormous source image.
    static func jpegDataUnderLimit(from image: UIImage, maxBytes: Int = maxBytes) -> Data? {
        var dim = min(startMaxDimension, max(image.size.width, image.size.height))
        var lastData: Data?
        for _ in 0..<6 {
            let scaled = resized(image, maxDimension: dim)
            for quality in qualitySteps {
                guard let data = scaled.jpegData(compressionQuality: quality) else { continue }
                lastData = data
                if data.count <= maxBytes { return data }
            }
            dim = (dim * 0.7).rounded()
        }
        return lastData // best effort — smallest size this device could produce
    }

    private static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
