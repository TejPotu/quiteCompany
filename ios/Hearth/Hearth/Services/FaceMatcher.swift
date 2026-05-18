import Foundation
import UIKit
import Vision

// First-stage retrieval for the People tab. Apple's Vision framework gets
// us a fast ranked shortlist by face-print distance; Gemma's vision model
// then re-ranks (actually just verifies) that shortlist pairwise to catch
// the cases where the closest fingerprint is the wrong person but the 2nd
// or 3rd is right.
//
// Why this split: a single feature-print comparison costs ~1 ms; a Gemma
// vision call costs ~1–2 s. We want Gemma to spend its compute on the
// hard part (deciding identity) and let cheap math do the easy part
// (narrowing 50 candidates down to 3).

enum FaceMatcher {

    /// Compute and serialize a face fingerprint for an indexed portrait.
    /// Returns nil if no face is detected — caller can prompt the caregiver
    /// to retake the photo.
    static func computeFingerprint(for image: UIImage) async -> Data? {
        guard let crop = await detectAndCropFace(in: image) else { return nil }
        guard let observation = await featurePrint(of: crop) else { return nil }
        return try? NSKeyedArchiver.archivedData(
            withRootObject: observation,
            requiringSecureCoding: true
        )
    }

    /// Rank indexed entries by face-print distance to the captured photo.
    /// Returns the top `k` candidates (those with a usable fingerprint),
    /// closest first. Falls back to a whole-image feature print if face
    /// detection fails on the captured photo (small face, screen glare,
    /// awkward angle) — the ranking is noisier in that case but better
    /// than an empty shortlist.
    static func topCandidates(
        captured: UIImage,
        against entries: [PersonEntry],
        k: Int = 3
    ) async -> [Candidate] {
        let target = await detectAndCropFace(in: captured) ?? captured
        guard let queryPrint = await featurePrint(of: target) else { return [] }

        var scored: [Candidate] = []
        for entry in entries {
            guard
                let data = entry.featurePrintData,
                let indexed = try? NSKeyedUnarchiver.unarchivedObject(
                    ofClass: VNFeaturePrintObservation.self,
                    from: data
                )
            else { continue }

            var distance: Float = .greatestFiniteMagnitude
            do {
                try queryPrint.computeDistance(&distance, to: indexed)
            } catch {
                continue
            }
            scored.append(Candidate(entry: entry, distance: distance))
        }
        scored.sort { $0.distance < $1.distance }
        return Array(scored.prefix(k))
    }

    struct Candidate: Equatable {
        let entry: PersonEntry
        let distance: Float
    }

    // MARK: - Internals

    private static func detectAndCropFace(in image: UIImage) async -> UIImage? {
        guard let cg = image.cgImage else { return nil }

        let face: VNFaceObservation? = await withCheckedContinuation { (cont: CheckedContinuation<VNFaceObservation?, Never>) in
            let request = VNDetectFaceRectanglesRequest { req, _ in
                let largest = (req.results as? [VNFaceObservation])?
                    .max(by: { $0.boundingBox.area < $1.boundingBox.area })
                cont.resume(returning: largest)
            }
            let handler = VNImageRequestHandler(cgImage: cg, orientation: image.cgOrientation, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([request])
            }
        }

        guard let face else { return nil }

        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let pad: CGFloat = 0.25
        var rect = CGRect(
            x: face.boundingBox.minX * w,
            y: (1 - face.boundingBox.maxY) * h,
            width: face.boundingBox.width * w,
            height: face.boundingBox.height * h
        )
        rect = rect.insetBy(dx: -rect.width * pad, dy: -rect.height * pad)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))

        guard let cropped = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    private static func featurePrint(of image: UIImage) async -> VNFeaturePrintObservation? {
        guard let cg = image.cgImage else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<VNFeaturePrintObservation?, Never>) in
            let request = VNGenerateImageFeaturePrintRequest { req, _ in
                cont.resume(returning: (req.results as? [VNFeaturePrintObservation])?.first)
            }
            let handler = VNImageRequestHandler(cgImage: cg, orientation: image.cgOrientation, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([request])
            }
        }
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}

private extension UIImage {
    var cgOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up:            return .up
        case .down:          return .down
        case .left:          return .left
        case .right:         return .right
        case .upMirrored:    return .upMirrored
        case .downMirrored:  return .downMirrored
        case .leftMirrored:  return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default:    return .up
        }
    }
}
