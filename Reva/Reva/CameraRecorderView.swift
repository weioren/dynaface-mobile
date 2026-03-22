import SwiftUI
import AVFoundation

struct CameraRecorderView: UIViewControllerRepresentable {
    
    let exerciseName: String
    // Callback to notify parent when recording is finished
    var onFinishRecording: ((URL?) -> Void)?
    
    func makeUIViewController(context: Context) -> CameraRecorderViewController {
        let vc = CameraRecorderViewController()
        vc.exerciseName = exerciseName
        vc.onFinishRecording = onFinishRecording
        return vc
    }
    
    func updateUIViewController(_ uiViewController: CameraRecorderViewController, context: Context) {
        // Re-assign the callback to ensure it's always current, especially after permission changes
        uiViewController.onFinishRecording = onFinishRecording
    }
}

class CameraRecorderViewController: UIViewController, AVCaptureFileOutputRecordingDelegate {
    
    var captureSession: AVCaptureSession?
    var videoOutput = AVCaptureMovieFileOutput()
    
    var previewLayer: AVCaptureVideoPreviewLayer?
    var exerciseName: String = ""
    var recordButton: UIButton!
    var buttonContainer: UIView!
    
    // This closure will be called once recording is finished
    var onFinishRecording: ((URL?) -> Void)?
    
    // Add state tracking
    private var isSetupComplete = false
    private var recordedFileURL: URL? // Store the recorded file URL
    
    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
        // Permission is already requested on ExercisesPage, so directly setup camera
        setupCamera()
    }
    
    func setupCamera() {
        // Prevent multiple setup attempts
        guard !isSetupComplete else { return }
        
        let session = AVCaptureSession()
        session.beginConfiguration()
        
        // Use the front camera if available
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
        
        // Remove audio input - we only want video
        
        // Add movie output
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        
        session.commitConfiguration()
        
        // Preview layer
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(previewLayer, at: 0) // Insert at index 0 to be behind UI elements
        self.previewLayer = previewLayer
        
        self.captureSession = session
        isSetupComplete = true
        
        // Start session on background queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
            DispatchQueue.main.async {
                self?.recordButton.isEnabled = true
                // Ensure preview layer frame is set after session starts
                self?.updatePreviewLayerFrame()
                print("Camera setup complete and running")
            }
        }
    }
    
    private func updatePreviewLayerFrame() {
        guard let previewLayer = previewLayer else { return }
        
        // Calculate the camera preview frame to leave space for the button
        let buttonHeight: CGFloat = 90
        let cameraPreviewHeight = view.bounds.height - buttonHeight
        
        // Set the preview layer frame to leave space at the bottom
        previewLayer.frame = CGRect(
            x: 0,
            y: 0,
            width: view.bounds.width,
            height: cameraPreviewHeight
        )
        
        // Ensure the preview layer is properly oriented
        if let connection = previewLayer.connection {
            if connection.isVideoOrientationSupported {
                let orientation = UIDevice.current.orientation
                switch orientation {
                case .portrait:
                    connection.videoOrientation = .portrait
                case .portraitUpsideDown:
                    connection.videoOrientation = .portraitUpsideDown
                case .landscapeLeft:
                    connection.videoOrientation = .landscapeRight
                case .landscapeRight:
                    connection.videoOrientation = .landscapeLeft
                default:
                    connection.videoOrientation = .portrait
                }
            }
        }
        
        // Force a layout update
        previewLayer.setNeedsLayout()
    }
    
    func showCameraUnavailableAlert() {
        let alert = UIAlertController(
            title: "Camera Unavailable",
            message: "The front camera is not available on this device.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            // Notify parent that recording failed due to camera unavailability
            self?.onFinishRecording?(nil)
        })
        present(alert, animated: true)
    }
    
    func setupUI() {
        // Create a container view for the button to ensure it's above the camera preview
        buttonContainer = UIView()
        buttonContainer.backgroundColor = UIColor.clear
        view.addSubview(buttonContainer)
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        
        recordButton = UIButton(type: .system)
        recordButton.setTitle("Start", for: .normal)
        recordButton.setTitleColor(.white, for: .normal)
        recordButton.backgroundColor = UIColor.systemGreen // Green for start
        recordButton.layer.cornerRadius = 10
        recordButton.isEnabled = false // Disable until camera is ready
        recordButton.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)
        
        // Add button to the container
        buttonContainer.addSubview(recordButton)
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Constrain the container
        NSLayoutConstraint.activate([
            buttonContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            buttonContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            buttonContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            buttonContainer.heightAnchor.constraint(equalToConstant: 90)
        ])
        
        // Constrain the button within the container
        NSLayoutConstraint.activate([
            recordButton.heightAnchor.constraint(equalToConstant: 50),
            recordButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor, constant: 20),
            recordButton.trailingAnchor.constraint(equalTo: buttonContainer.trailingAnchor, constant: -20),
            recordButton.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor, constant: -20)
        ])
        
        // Ensure the button container is above the camera preview
        view.bringSubviewToFront(buttonContainer)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Update preview layer frame whenever layout changes
        updatePreviewLayerFrame()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Ensure session is running when view appears
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

        // Ensure preview layer frame is set
        if isSetupComplete {
            updatePreviewLayerFrame()
        }
        
        // Listen for orientation changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationChanged),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Remove orientation change observer
        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        
        // Stop the session when leaving the view
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }
    
    @objc private func orientationChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.updatePreviewLayerFrame()
        }
    }
    
    // Method to explicitly request the recorded file and call the completion callback
    func requestRecordedFile() {
        print("CameraRecorder: Requesting recorded file, URL: \(String(describing: recordedFileURL))")
        onFinishRecording?(recordedFileURL)
    }
    
    // Method to check if we have a recorded file ready
    var hasRecordedFile: Bool {
        return recordedFileURL != nil
    }
    
    @objc func toggleRecording() {
        guard let captureSession = captureSession, captureSession.isRunning else {
            print("Capture session is not running")
            return
        }
        
        if videoOutput.isRecording {
            // Stop recording - this will trigger the delegate method
            print("CameraRecorder: Stopping recording")
            videoOutput.stopRecording()
            recordButton.setTitle("Start", for: .normal)
            recordButton.backgroundColor = UIColor.systemGreen // Green for start
            // Don't call onFinishRecording here - wait for the delegate method
        } else {
            // Start recording
            print("CameraRecorder: Starting recording")
            let nextNumber = getNextFileNumber(for: exerciseName)
            let fileName = "\(exerciseName)_\(nextNumber).mov"
            
            let outputPath = NSTemporaryDirectory() + fileName
            let outputFileURL = URL(fileURLWithPath: outputPath)
            videoOutput.startRecording(to: outputFileURL, recordingDelegate: self)
            recordButton.setTitle("Finish", for: .normal)
            recordButton.backgroundColor = UIColor.systemRed // Red for finish
        }
    }
    
    func getNextFileNumber(for exerciseName: String) -> Int {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            let movFiles = files.filter { $0.pathExtension.lowercased() == "mov" }
            
            // Find files that match the exercise name pattern
            let exerciseFiles = movFiles.filter { file in
                let filename = file.lastPathComponent
                return filename.hasPrefix("\(exerciseName)_") && filename.hasSuffix(".mov")
            }
            
            // Extract numbers from existing files
            var existingNumbers: [Int] = []
            for file in exerciseFiles {
                let filename = file.lastPathComponent
                let components = filename.split(separator: "_")
                if components.count >= 2 {
                    let numberPart = components.last?.split(separator: ".").first ?? ""
                    if let number = Int(numberPart) {
                        existingNumbers.append(number)
                    }
                }
            }
            
            // Return the next available number
            return existingNumbers.isEmpty ? 1 : (existingNumbers.max() ?? 0) + 1
            
        } catch {
            print("Error reading directory: \(error)")
            return 1
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
            self?.recordButton.backgroundColor = UIColor.systemGreen // Reset to green
        }
        
        if error == nil {
            // Move file from temp to Documents directory
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            
            // Extract the filename from the temporary URL (it already has the correct format)
            let fileName = outputFileURL.lastPathComponent
            let destinationURL = documentsURL.appendingPathComponent(fileName)
            
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: outputFileURL, to: destinationURL)
                print("CameraRecorder: File saved successfully at \(destinationURL)")
                
                // Store the recorded file URL and notify parent that recording is ready for review
                DispatchQueue.main.async { [weak self] in
                    self?.recordedFileURL = destinationURL
                    print("CameraRecorder: Recording completed, file ready for review: \(destinationURL)")
                    // Call the callback to transition to review phase
                    self?.onFinishRecording?(destinationURL)
                }
            } catch {
                print("Error moving recorded file: \(error)")
                DispatchQueue.main.async { [weak self] in
                    self?.recordedFileURL = nil
                    // Call the callback with nil to indicate failure
                    self?.onFinishRecording?(nil)
                }
            }
        } else {
            print("Recording error: \(String(describing: error))")
            DispatchQueue.main.async { [weak self] in
                self?.recordedFileURL = nil
                // Call the callback with nil to indicate failure
                self?.onFinishRecording?(nil)
            }
        }
    }
}
