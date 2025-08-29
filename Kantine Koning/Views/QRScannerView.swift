import SwiftUI
import AVFoundation

// Matches the old app's scanner API and layout control
struct QRScannerView: UIViewControllerRepresentable {
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let parent: QRScannerView
        weak var controller: ScannerViewController?
        private var didEmit = false
        init(parent: QRScannerView) { self.parent = parent }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !didEmit,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let stringValue = object.stringValue else { return }
            didEmit = true
            parent.onScanned(stringValue)
            controller?.setActive(false)
        }
    }

    let isActive: Bool
    let onScanned: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onScanned = onScanned
        vc.delegate = context.coordinator
        context.coordinator.controller = vc
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        uiViewController.setActive(isActive)
    }
}

final class ScannerViewController: UIViewController {
    var onScanned: ((String) -> Void)?
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    weak var delegate: (any AVCaptureMetadataOutputObjectsDelegate)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupDevelopmentPasteButton()
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoInput) else {
            Logger.qr("❌ Could not create video input or add to session")
            return
        }
        session.addInput(videoInput)

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else {
            Logger.qr("❌ Cannot add metadata output")
            return
        }
        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(delegate, queue: DispatchQueue.main)
        metadataOutput.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.layer.bounds
        view.layer.addSublayer(preview)

        self.captureSession = session
        self.previewLayer = preview
        Logger.qr("✅ Camera configured. Ready to start")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    func setActive(_ active: Bool) {
        guard let session = captureSession else { return }
        if active {
            if !session.isRunning {
                Logger.qr("▶️ Starting session")
                session.startRunning()
            }
        } else {
            if session.isRunning {
                Logger.qr("⏹️ Stopping session")
                session.stopRunning()
            }
        }
    }
    
    private func setupDevelopmentPasteButton() {
        #if DEBUG
        addPasteButton()
        #elseif ENABLE_LOGGING
        // Release Testing scheme with logging enabled
        addPasteButton()
        #endif
    }
    
    private func addPasteButton() {
        let pasteButton = UIButton(type: .system)
        pasteButton.setTitle("📋 Paste QR", for: .normal)
        pasteButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        pasteButton.setTitleColor(.white, for: .normal)
        pasteButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
        pasteButton.layer.cornerRadius = 8
        pasteButton.translatesAutoresizingMaskIntoConstraints = false
        
        pasteButton.addTarget(self, action: #selector(pasteButtonTapped), for: .touchUpInside)
        
        view.addSubview(pasteButton)
        
        NSLayoutConstraint.activate([
            pasteButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            pasteButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            pasteButton.widthAnchor.constraint(equalToConstant: 100),
            pasteButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        Logger.qr("🔧 Development paste button added for QR testing")
    }
    
    @objc private func pasteButtonTapped() {
        guard let clipboardString = UIPasteboard.general.string else {
            Logger.qr("📋 No text found in clipboard")
            return
        }
        
        Logger.qr("📋 Pasting from clipboard: \(clipboardString.prefix(50))...")
        onScanned?(clipboardString)
    }
}


