//
//  QRScannerView.swift
//  Kantine Koning
//
//  Created by Hedde van der Heide on 16/08/2025.
//

import SwiftUI
import AVFoundation

struct QRScannerView: UIViewControllerRepresentable {
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let parent: QRScannerView
        init(parent: QRScannerView) { self.parent = parent }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let stringValue = object.stringValue else { return }
            parent.onScanned(stringValue)
        }
    }

    let onScanned: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onScanned = onScanned
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

final class ScannerViewController: UIViewController {
    var onScanned: ((String) -> Void)?
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    weak var delegate: (any AVCaptureMetadataOutputObjectsDelegate)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let session = AVCaptureSession()
        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoInput) else {
            return
        }
        session.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else { return }
        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(delegate, queue: DispatchQueue.main)
        metadataOutput.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.layer.bounds
        view.layer.addSublayer(preview)

        self.captureSession = session
        self.previewLayer = preview

        session.startRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }
}


