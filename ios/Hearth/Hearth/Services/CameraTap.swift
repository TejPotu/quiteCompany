import Foundation
import AVFoundation
import UIKit

// Headless single-still camera. Powers the presence-sensing loop on the
// Watch tab: every sample interval we spin up the front camera, snap one
// frame, tear it down. The iOS camera indicator blinks for ~1s per sample
// — visible, honest, but not "always recording."
//
// The People tab uses a different path (UIImagePickerController) for
// interactive capture; that path is mutually exclusive with this one. The
// CameraTap session is short-lived so collisions are rare and recover on
// the next interval.
final class CameraTap: NSObject, @unchecked Sendable {

    static let shared = CameraTap()

    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let configureQueue = DispatchQueue(label: "hearth.camera-tap")
    private var configured = false
    private var pendingContinuation: CheckedContinuation<Data?, Never>?

    // Ask for camera permission upfront. Returns true if we can use it.
    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:    return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }

    // Snap one still. Returns JPEG data or nil on any failure (no permission,
    // hardware busy from People tab, etc.) — caller skips that sample.
    func snap() async -> Data? {
        guard await requestPermission() else { return nil }
        guard configure() else { return nil }

        // Camera session APIs must be hit off the main thread.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            configureQueue.async { [session] in
                if !session.isRunning { session.startRunning() }
                cont.resume()
            }
        }

        let data = await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            self.pendingContinuation = cont
            let settings = AVCapturePhotoSettings()
            output.capturePhoto(with: settings, delegate: self)
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            configureQueue.async { [session] in
                if session.isRunning { session.stopRunning() }
                cont.resume()
            }
        }

        return data
    }

    // MARK: - Internals

    @discardableResult
    private func configure() -> Bool {
        if configured { return true }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(output)
        else {
            return false
        }
        session.addInput(input)
        session.addOutput(output)
        configured = true
        return true
    }
}

extension CameraTap: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data = photo.fileDataRepresentation()
        pendingContinuation?.resume(returning: data)
        pendingContinuation = nil
    }
}
