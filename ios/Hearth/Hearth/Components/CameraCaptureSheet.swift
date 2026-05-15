import SwiftUI
import UIKit

// Thin SwiftUI wrapper around UIImagePickerController(.camera). Used in two
// places on the People tab: (1) auto-opens when the patient enters the tab
// so they can snap whoever's in front of them, (2) lets the caregiver shoot
// the indexed portrait directly without bouncing through Photos.
//
// Falls back gracefully if the simulator (no camera) presents it — the
// picker will simply not show, and the caller's onCancel fires.
struct CameraCaptureSheet: UIViewControllerRepresentable {
    var preferFrontCamera: Bool = false
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
            if preferFrontCamera,
               UIImagePickerController.isCameraDeviceAvailable(.front) {
                picker.cameraDevice = .front
            }
        } else {
            // Simulator / no camera — fall back to photo library so the demo
            // still works on a dev machine.
            picker.sourceType = .photoLibrary
        }
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCaptureSheet
        init(_ parent: CameraCaptureSheet) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let img = info[.originalImage] as? UIImage {
                parent.onCapture(img)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}
