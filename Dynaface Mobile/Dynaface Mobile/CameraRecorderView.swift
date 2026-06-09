import SwiftUI
import AVFoundation
import Vision

// [Phase 1] DEV ONLY: set to true to use a fake video on simulator (no camera needed)
private let simulatorMode = false

struct CameraRecorderView: UIViewControllerRepresentable {

    let exerciseName: String
    var onFinishRecording: ((URL?) -> Void)?

    func makeUIViewController(context: Context) -> CameraRecorderViewController {
        let vc = CameraRecorderViewController()
        vc.exerciseName = exerciseName
        vc.onFinishRecording = onFinishRecording
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraRecorderViewController, context: Context) {
        uiViewController.onFinishRecording = onFinishRecording
    }
}

// MARK: - Face Guide Overlay (dashed oval that turns green when face is aligned)
class FaceGuideOverlayView: UIView {

    private(set) var isFaceAligned: Bool = false
    private var isDismissed: Bool = false
    private var lightingMessage: String? = nil
    var onFaceAlignmentChanged: ((Bool) -> Void)?

    private let feedbackLabel: UILabel = {
        let l = UILabel()
        l.textAlignment = .center
        l.font = .systemFont(ofSize: 15, weight: .medium)
        l.textColor = .white.withAlphaComponent(0.8)
        l.text = "Position your face in the oval"
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let ovalLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = 2.5
        return layer
    }()

    var ovalRect: CGRect {
        let w = bounds.width * 0.6
        let h = w * 1.35
        let x = (bounds.width - w) / 2
        let y = (bounds.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        layer.addSublayer(ovalLayer)
        addSubview(feedbackLabel)

        NSLayoutConstraint.activate([
            feedbackLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            feedbackLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20)
        ])

        updateOvalAppearance(aligned: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !isDismissed else { return }
        let path = UIBezierPath(ovalIn: ovalRect)
        ovalLayer.path = path.cgPath
    }

    private func updateOvalAppearance(aligned: Bool) {
        if aligned {
            ovalLayer.strokeColor = UIColor.systemGreen.cgColor
            ovalLayer.lineDashPattern = nil // solid line
            ovalLayer.lineWidth = 3.0
        } else {
            ovalLayer.strokeColor = UIColor.white.withAlphaComponent(0.6).cgColor
            ovalLayer.lineDashPattern = [8, 6]
            ovalLayer.lineWidth = 2.5
        }
        refreshFeedbackText()
    }

    /// Prioritized feedback:
    /// 1. Face not aligned → "Center your face"
    /// 2. Face aligned but lighting flagged → lighting message ("Too dark"/"Too bright")
    /// 3. Both OK → label cleared
    private func refreshFeedbackText() {
        feedbackLabel.textColor = .white.withAlphaComponent(0.8)
        if !isFaceAligned {
            feedbackLabel.text = "Center your face"
        } else if let message = lightingMessage {
            feedbackLabel.text = message
        } else {
            feedbackLabel.text = nil
        }
    }

    /// Called by the controller on every face detection result
    func updateFaceAlignment(faceInOval: Bool) {
        guard !isDismissed else { return }

        if faceInOval != isFaceAligned {
            isFaceAligned = faceInOval
            updateOvalAppearance(aligned: faceInOval)
            onFaceAlignmentChanged?(faceInOval)
        }
    }

    /// Called by the controller after each lighting evaluation. Pass `nil`
    /// when lighting is OK, or a short message ("Too dark" / "Too bright")
    /// when the gate should block recording.
    func updateLighting(message: String?) {
        guard !isDismissed else { return }
        if message != lightingMessage {
            lightingMessage = message
            refreshFeedbackText()
        }
    }

    /// Immediately hide (called when recording starts)
    func dismiss() {
        isDismissed = true
        isHidden = true
    }

    /// Re-activate after a previous dismiss (e.g. camera flip after recording).
    func reset() {
        isDismissed = false
        isHidden = false
        isFaceAligned = false
        lightingMessage = nil
        updateOvalAppearance(aligned: false)
        setNeedsLayout()
    }
}

// MARK: - Camera Recorder
class CameraRecorderViewController: UIViewController, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {

    var captureSession: AVCaptureSession?
    var videoOutput = AVCaptureMovieFileOutput()
    private var videoDataOutput = AVCaptureVideoDataOutput()
    private let videoDataQueue = DispatchQueue(label: "com.dynaface.facedetection", qos: .userInteractive)

    var previewLayer: AVCaptureVideoPreviewLayer?
    var exerciseName: String = ""
    var recordButton: UIButton!
    var buttonContainer: UIView!
    private var flipCameraObserver: NSObjectProtocol?

    var onFinishRecording: ((URL?) -> Void)?

    private var isSetupComplete = false
    private var recordedFileURL: URL?
    private var currentCameraPosition: AVCaptureDevice.Position = .front

    // Face guide
    private var faceGuideOverlay: FaceGuideOverlayView!
    private var faceDetectionRequest: VNDetectFaceRectanglesRequest?
    private var isProcessingFrame = false
    private var faceGuideCompleted = false

    // Recording readiness gate — record button enabled only when face
    // is aligned AND lighting is OK. State updated from captureOutput.
    private var isFaceAligned = false
    private var lightingState: LightingState = .ok

    private enum LightingState {
        case ok, tooDark, tooBright

        var feedbackMessage: String? {
            switch self {
            case .ok:        return nil
            case .tooDark:   return "Too dark"
            case .tooBright: return "Too bright"
            }
        }
    }

    // Hysteresis on average Y in 0..255 so the gate doesn't flicker.
    private let lightingDarkLow:    Double = 45.0   // .ok      → .tooDark   when avg < 45
    private let lightingDarkHigh:   Double = 55.0   // .tooDark → .ok        when avg > 55
    private let lightingBrightHigh: Double = 225.0  // .ok      → .tooBright when avg > 225
    private let lightingBrightLow:  Double = 215.0  // .tooBright → .ok      when avg < 215

    override func viewDidLoad() {
        super.viewDidLoad()

        if simulatorMode {
            setupSimulatorMode()
            return
        }

        setupUI()
        setupFaceGuide()
        setupCamera()
    }

    // MARK: - Face Guide
    private func setupFaceGuide() {
        faceGuideOverlay = FaceGuideOverlayView(frame: .zero)
        faceGuideOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(faceGuideOverlay)

        NSLayoutConstraint.activate([
            faceGuideOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            faceGuideOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            faceGuideOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            faceGuideOverlay.bottomAnchor.constraint(equalTo: buttonContainer.topAnchor)
        ])

        faceGuideOverlay.onFaceAlignmentChanged = { [weak self] aligned in
            guard let self = self else { return }
            self.isFaceAligned = aligned
            self.updateRecordingReadiness()
        }

        view.bringSubviewToFront(faceGuideOverlay)
        view.bringSubviewToFront(buttonContainer)

        // Listen for flip camera notification from SwiftUI layer
        flipCameraObserver = NotificationCenter.default.addObserver(
            forName: .flipCamera, object: nil, queue: .main
        ) { [weak self] _ in
            self?.flipCamera()
        }

        faceDetectionRequest = VNDetectFaceRectanglesRequest { [weak self] request, _ in
            guard let self = self else { return }
            let faces = request.results as? [VNFaceObservation]
            DispatchQueue.main.async {
                self.processFaceResult(faces: faces)
            }
        }
    }

    private func processFaceResult(faces: [VNFaceObservation]?) {
        guard let previewLayer = previewLayer, !faceGuideCompleted else { return }

        guard let face = faces?.first else {
            faceGuideOverlay.updateFaceAlignment(faceInOval: false)
            return
        }

        // Convert Vision coordinates to preview layer coordinates
        let faceBounds = previewLayer.layerRectConverted(fromMetadataOutputRect: face.boundingBox)
        let faceCenter = CGPoint(x: faceBounds.midX, y: faceBounds.midY)

        // Check if face center is within the guide oval
        let oval = faceGuideOverlay.ovalRect
        let cx = oval.midX, cy = oval.midY
        let a = oval.width / 2, b = oval.height / 2
        let dx = faceCenter.x - cx, dy = faceCenter.y - cy
        let inOval = (dx * dx) / (a * a) + (dy * dy) / (b * b) <= 1.3

        faceGuideOverlay.updateFaceAlignment(faceInOval: inOval)
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !faceGuideCompleted, !isProcessingFrame else { return }
        isProcessingFrame = true

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let request = faceDetectionRequest else {
            isProcessingFrame = false
            return
        }

        let orientation: CGImagePropertyOrientation = (currentCameraPosition == .front) ? .leftMirrored : .right
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        try? handler.perform([request])

        // Lighting gate — cheap pass over the same pixel buffer (32x32 sample
        // grid). Computed on the data queue, applied on main so the state
        // (and downstream UI) stays single-threaded.
        let avgLuma = computeAverageLuminance(pixelBuffer: pixelBuffer)
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.faceGuideCompleted else { return }
            let newState = self.evaluateLighting(avgLuma: avgLuma)
            if newState != self.lightingState {
                self.lightingState = newState
                self.faceGuideOverlay?.updateLighting(message: newState.feedbackMessage)
                self.updateRecordingReadiness()
            }
        }

        isProcessingFrame = false
    }

    // MARK: - Recording readiness helpers

    /// Combined gate. Skipped once recording has started
    /// (`faceGuideCompleted` is set to `true` in `toggleRecording`).
    private func updateRecordingReadiness() {
        guard !faceGuideCompleted else { return }
        let ready = isFaceAligned && (lightingState == .ok)
        recordButton.isEnabled = ready
        recordButton.backgroundColor = ready
            ? UIColor(red: 0.12, green: 0.29, blue: 0.64, alpha: 1.0)
            : UIColor.gray
    }

    /// Apply hysteresis around the dark/bright thresholds so a borderline
    /// frame doesn't flicker the state every other capture.
    private func evaluateLighting(avgLuma: Double) -> LightingState {
        switch lightingState {
        case .ok:
            if avgLuma < lightingDarkLow    { return .tooDark }
            if avgLuma > lightingBrightHigh { return .tooBright }
            return .ok
        case .tooDark:
            if avgLuma > lightingDarkHigh { return .ok }
            return .tooDark
        case .tooBright:
            if avgLuma < lightingBrightLow { return .ok }
            return .tooBright
        }
    }

    /// 32x32 grid average over the pixel buffer's luminance. Handles the two
    /// most common iOS capture formats: bi-planar YUV (uses Y plane directly)
    /// and BGRA (Rec. 601 luminance from RGB).
    private func computeAverageLuminance(pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width  = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)

        let samples = 32
        let xStride = max(1, width  / samples)
        let yStride = max(1, height / samples)

        if format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
           format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
            // YUV: Y plane is plane 0; values map directly to luminance.
            guard let yPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return 128 }
            let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let yPtr = yPlane.assumingMemoryBound(to: UInt8.self)

            var total = 0
            var count = 0
            var y = 0
            while y < height {
                var x = 0
                while x < width {
                    total += Int(yPtr[y * yBytesPerRow + x])
                    count += 1
                    x += xStride
                }
                y += yStride
            }
            return count > 0 ? Double(total) / Double(count) : 128
        } else {
            // BGRA fallback. iOS may deliver BGRA when video settings request it.
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 128 }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let ptr = base.assumingMemoryBound(to: UInt8.self)

            var total = 0.0
            var count = 0
            var y = 0
            while y < height {
                var x = 0
                while x < width {
                    let pixel = ptr.advanced(by: y * bytesPerRow + x * 4)
                    let b = Double(pixel[0])
                    let g = Double(pixel[1])
                    let r = Double(pixel[2])
                    total += 0.299 * r + 0.587 * g + 0.114 * b
                    count += 1
                    x += xStride
                }
                y += yStride
            }
            return count > 0 ? total / Double(count) : 128
        }
    }

    // MARK: - Simulator Mode
    private func setupSimulatorMode() {
        view.backgroundColor = .darkGray

        let label = UILabel()
        label.text = "📷 Simulator Mode\nTap button to fake a recording"
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        let button = UIButton(type: .system)
        button.setTitle("Simulate Recording", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 20, weight: .bold)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .systemGreen
        button.layer.cornerRadius = 12
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(simulateRecording), for: .touchUpInside)
        view.addSubview(button)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 30),
            button.widthAnchor.constraint(equalToConstant: 250),
            button.heightAnchor.constraint(equalToConstant: 56),
        ])
    }

    @objc private func simulateRecording() {
        let extensions = ["MOV", "mp4"]
        var sourceURL: URL?
        for ext in extensions {
            if let url = Bundle.main.url(forResource: "FullSmile", withExtension: ext) {
                sourceURL = url
                break
            }
        }
        guard let source = sourceURL else {
            onFinishRecording?(nil)
            return
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dest = docs.appendingPathComponent("\(exerciseName)_sim.mov")
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: source, to: dest)
        onFinishRecording?(dest)
    }

    // MARK: - Camera Setup
    func setupCamera() {
        guard !isSetupComplete else { return }

        let session = AVCaptureSession()
        session.beginConfiguration()

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let videoInput = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(videoInput)
        else {
            print("Failed to access front camera.")
            showCameraUnavailableAlert()
            return
        }
        session.addInput(videoInput)

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        // Video data output for face detection
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataQueue)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        }

        session.commitConfiguration()

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(previewLayer, at: 0)
        self.previewLayer = previewLayer

        self.captureSession = session
        isSetupComplete = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
            DispatchQueue.main.async {
                // Button stays disabled until face is aligned
                self?.recordButton.isEnabled = false
                self?.recordButton.backgroundColor = UIColor.gray
                self?.updatePreviewLayerFrame()
                print("Camera setup complete and running")
            }
        }
    }

    private func updatePreviewLayerFrame() {
        guard let previewLayer = previewLayer else { return }

        let buttonHeight: CGFloat = 90
        let cameraPreviewHeight = view.bounds.height - buttonHeight

        previewLayer.frame = CGRect(
            x: 0, y: 0,
            width: view.bounds.width,
            height: cameraPreviewHeight
        )

        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            let orientation = UIDevice.current.orientation
            switch orientation {
            case .portrait: connection.videoOrientation = .portrait
            case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
            case .landscapeLeft: connection.videoOrientation = .landscapeRight
            case .landscapeRight: connection.videoOrientation = .landscapeLeft
            default: connection.videoOrientation = .portrait
            }
        }

        previewLayer.setNeedsLayout()
    }

    func showCameraUnavailableAlert() {
        let alert = UIAlertController(
            title: "Camera Unavailable",
            message: "The front camera is not available on this device.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.onFinishRecording?(nil)
        })
        present(alert, animated: true)
    }

    // MARK: - UI Setup
    func setupUI() {
        buttonContainer = UIView()
        buttonContainer.backgroundColor = UIColor.clear
        view.addSubview(buttonContainer)
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false

        recordButton = UIButton(type: .system)
        recordButton.setTitle("Start", for: .normal)
        recordButton.setTitleColor(.white, for: .normal)
        recordButton.backgroundColor = UIColor.gray
        recordButton.layer.cornerRadius = 10
        recordButton.isEnabled = false
        recordButton.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)

        buttonContainer.addSubview(recordButton)
        recordButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            buttonContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            buttonContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            buttonContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            buttonContainer.heightAnchor.constraint(equalToConstant: 90)
        ])

        NSLayoutConstraint.activate([
            recordButton.heightAnchor.constraint(equalToConstant: 50),
            recordButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor, constant: 20),
            recordButton.trailingAnchor.constraint(equalTo: buttonContainer.trailingAnchor, constant: -20),
            recordButton.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor, constant: -20)
        ])

        view.bringSubviewToFront(buttonContainer)
    }

    // MARK: - Layout
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePreviewLayerFrame()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if isSetupComplete {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.startRunning()
                DispatchQueue.main.async {
                    self?.updatePreviewLayerFrame()
                }
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if isSetupComplete {
            updatePreviewLayerFrame()
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(orientationChanged),
            name: UIDevice.orientationDidChangeNotification, object: nil
        )
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(
            self, name: UIDevice.orientationDidChangeNotification, object: nil
        )
        if let obs = flipCameraObserver {
            NotificationCenter.default.removeObserver(obs)
            flipCameraObserver = nil
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }

    @objc private func orientationChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.updatePreviewLayerFrame()
        }
    }

    func requestRecordedFile() {
        onFinishRecording?(recordedFileURL)
    }

    var hasRecordedFile: Bool {
        return recordedFileURL != nil
    }

    // MARK: - Camera Flip
    @objc private func flipCamera() {
        guard let session = captureSession, !videoOutput.isRecording else { return }

        let newPosition: AVCaptureDevice.Position = (currentCameraPosition == .front) ? .back : .front

        guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
              let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }

        session.beginConfiguration()

        // Remove existing video input
        if let currentInput = session.inputs.first(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true }) {
            session.removeInput(currentInput)
        }

        if session.canAddInput(newInput) {
            session.addInput(newInput)
            currentCameraPosition = newPosition
        }

        session.commitConfiguration()

        // Reset face guide and require checks for both cameras.
        faceGuideOverlay?.reset()
        isFaceAligned = false
        lightingState = .ok
        faceGuideCompleted = false
        recordButton.isEnabled = false
        recordButton.backgroundColor = UIColor.gray
    }

    // MARK: - Recording
    @objc func toggleRecording() {
        guard let captureSession = captureSession, captureSession.isRunning else {
            print("Capture session is not running")
            return
        }

        if videoOutput.isRecording {
            print("CameraRecorder: Stopping recording")
            videoOutput.stopRecording()
            recordButton.setTitle("Start", for: .normal)
            recordButton.backgroundColor = UIColor(red: 0.12, green: 0.29, blue: 0.64, alpha: 1.0)
            NotificationCenter.default.post(name: .recordingStateChanged, object: false) // Not recording
        } else {
            // Dismiss face guide when recording starts
            faceGuideOverlay?.dismiss()
            faceGuideCompleted = true
            NotificationCenter.default.post(name: .recordingStateChanged, object: true) // Recording

            print("CameraRecorder: Starting recording")
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let nextNumber = nextFileNumber(for: exerciseName, in: documentsURL)
            let fileName = "\(exerciseName)_\(nextNumber).mov"

            let outputPath = NSTemporaryDirectory() + fileName
            let outputFileURL = URL(fileURLWithPath: outputPath)
            videoOutput.startRecording(to: outputFileURL, recordingDelegate: self)
            recordButton.setTitle("Finish", for: .normal)
            recordButton.backgroundColor = UIColor.systemRed
        }
    }

    // MARK: - AVCaptureFileOutputRecordingDelegate
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {

        print("CameraRecorder: Recording finished, error: \(String(describing: error))")

        DispatchQueue.main.async { [weak self] in
            self?.recordButton.setTitle("Start", for: .normal)
            self?.recordButton.backgroundColor = UIColor(red: 0.12, green: 0.29, blue: 0.64, alpha: 1.0)
        }

        if error == nil {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fileName = outputFileURL.lastPathComponent
            let destinationURL = documentsURL.appendingPathComponent(fileName)

            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: outputFileURL, to: destinationURL)
                print("CameraRecorder: File saved successfully at \(destinationURL)")

                DispatchQueue.main.async { [weak self] in
                    self?.recordedFileURL = destinationURL
                    self?.onFinishRecording?(destinationURL)
                }
            } catch {
                print("Error moving recorded file: \(error)")
                DispatchQueue.main.async { [weak self] in
                    self?.recordedFileURL = nil
                    self?.onFinishRecording?(nil)
                }
            }
        } else {
            print("Recording error: \(String(describing: error))")
            DispatchQueue.main.async { [weak self] in
                self?.recordedFileURL = nil
                self?.onFinishRecording?(nil)
            }
        }
    }
}
