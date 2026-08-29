import SwiftUI
import AVFoundation

/// SwiftUI wrapper around an `AVCaptureVideoPreviewLayer`.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
