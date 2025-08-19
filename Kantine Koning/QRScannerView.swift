import SwiftUI
import AVFoundation

struct QRScannerView: UIViewRepresentable {
    final class ScannerView: UIView {
        let captureSession = AVCaptureSession()
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let parent: QRScannerView
        init(parent: QRScannerView) { self.parent = parent }
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let value = object.stringValue else { return }
            parent.onScan(value)
        }
    }

    let onScan: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> ScannerView {
        let view = ScannerView()
        view.previewLayer.videoGravity = .resizeAspectFill
        configureSession(on: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: ScannerView, context: Context) {}

    private func configureSession(on view: ScannerView, coordinator: Coordinator) {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        let session = view.captureSession
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) { session.addOutput(output) }
        output.setMetadataObjectsDelegate(coordinator, queue: DispatchQueue.main)
        output.metadataObjectTypes = [.qr]
        view.previewLayer.session = session
        session.startRunning()
    }
}


