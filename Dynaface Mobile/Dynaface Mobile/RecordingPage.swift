import SwiftUI
import AVKit

struct RecordingPage: View {
    enum Phase {
        case recording
        case review(url: URL)
        case error(message: String)
    }

    var exerciseName: String
    var exerciseVideoName: String? = nil
    var currentStep: Int = 1
    var totalSteps: Int = 1
    var completedSteps: Set<Int> = []
    var onFinish: ((URL?) -> Void)? = nil

    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var authService: AuthenticationService
    @State private var phase: Phase = .recording
    @State private var isUploading = false
    @State private var uploadErrorMessage: String?
    @State private var uploadStarted = false
    
    @State private var showDemoVideo = true
    @State private var isRecording = false

    var body: some View {
        Group {
            switch phase {
            case .recording:
                ZStack {
                    // Main: Camera view
                    VStack(spacing: 0) {
                        CameraRecorderView(exerciseName: exerciseName) { url in
                            DispatchQueue.main.async {
                                if let url = url {
                                    phase = .review(url: url)
                                } else {
                                    phase = .error(message: "Camera recording failed. Please try again or check camera permissions.")
                                }
                            }
                        }
                    }

                    // Overlay UI
                    VStack(spacing: 0) {
                        // Top bar: back button + title
                        HStack {
                            Button(action: {
                                onFinish?(nil)
                                presentationMode.wrappedValue.dismiss()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text("Back")
                                        .font(.body)
                                }
                                .foregroundColor(.white)
                                .padding(.leading, 20)
                                .padding(.vertical, 12)
                            }
                            Spacer()
                            Text(exerciseName)
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                            // Camera flip button
                            if !isRecording {
                                Button(action: {
                                    NotificationCenter.default.post(name: .flipCamera, object: nil)
                                }) {
                                    Image(systemName: "camera.rotate")
                                        .font(.system(size: 18))
                                        .foregroundColor(.white)
                                        .padding(.vertical, 12)
                                        .padding(.trailing, 8)
                                }
                            }
                            // Toggle demo video visibility
                            Button(action: { showDemoVideo.toggle() }) {
                                Image(systemName: showDemoVideo ? "pip.fill" : "pip")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                                    .padding(.trailing, 20)
                                    .padding(.vertical, 12)
                            }
                        }
                        .padding(.top, 4)
                        .background(
                            LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                        )
                        .onReceive(NotificationCenter.default.publisher(for: .recordingStateChanged)) { notification in
                            if let recording = notification.object as? Bool {
                                isRecording = recording
                            }
                        }

                        // PiP demo video (top-right)
                        HStack {
                            Spacer()
                            if showDemoVideo, let videoName = exerciseVideoName {
                                PiPDemoPlayer(videoName: videoName)
                                    .frame(width: 100, height: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .shadow(radius: 4)
                                    .padding(.trailing, 16)
                                    .padding(.top, 4)
                                    .transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: showDemoVideo)

                        Spacer()
                    }
                }
                .background(Color.black)
                .navigationBarBackButtonHidden(true)
                .navigationBarHidden(true)
                .interactiveDismissDisabled(true)

            case .review(let url):
                VStack(spacing: 0) {
                    header(text: "Review your recording")

                    Color.clear
                        .frame(width: 0, height: 0)
                        .task(id: url) {
                            await startAutoUploadIfNeeded(url)
                        }
                    
                    // 🔁 Mirrored content-only playback, preserves native aspect, loops
                    AdaptiveMirroredPlayer(url: url, heightFraction: 0.96)
                        .background(Color.black)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    HStack(spacing: 12) {
                        Button(role: .destructive) {
                            if FileManager.default.fileExists(atPath: url.path) {
                                try? FileManager.default.removeItem(at: url)
                            }
                            uploadStarted = false
                            uploadErrorMessage = nil
                            phase = .recording
                        } label: {
                            Label("Retake", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)

                        Button {
                            // If upload already completed, continue; otherwise upload is still running automatically.
                            if !isUploading, uploadStarted {
                            DispatchQueue.main.async {
                                onFinish?(url)
                                NotificationCenter.default.post(name: .recordingAccepted, object: nil)
                                presentationMode.wrappedValue.dismiss()
                            }
                        } label: {
                            Label(uploadStarted ? "Save & Continue" : "Uploading...", systemImage: "checkmark.circle.fill") // [Phase 1]
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(isUploading || !uploadStarted)
                            Label("Continue", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.12, green: 0.29, blue: 0.64))
                    }
                    .padding()
                    .background(.ultraThinMaterial)

                    if isUploading {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Uploading video and queuing job...")
                                .foregroundColor(.white)
                        }
                        .padding(.bottom, 16)
                    }

                    if uploadStarted && !isUploading {
                        VStack(spacing: 8) {
                            Text("Upload complete")
                                .foregroundColor(.white)
                            Text("Continue to proceed.")
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.bottom, 16)
                    }
                }
                .background(Color.black.edgesIgnoringSafeArea(.all))
                .navigationBarBackButtonHidden(true)
                .navigationBarHidden(true)
<<<<<<< HEAD
                .interactiveDismissDisabled(true) // cannot swipe away; must choose Delete or Accept
                .onDisappear {
                    // Clean up video player when leaving review phase
                    print("RecordingPage: Leaving review phase, cleaning up video player")
                }

                .alert("Upload Failed", isPresented: Binding(
                    get: { uploadErrorMessage != nil },
                    set: { if !$0 { uploadErrorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) {
                        uploadErrorMessage = nil
                    }
                } message: {
                    Text(uploadErrorMessage ?? "Unknown error")
                }
                
=======
                .interactiveDismissDisabled(true)

>>>>>>> origin/main
            case .error(let message):
                VStack(spacing: 20) {
                    Spacer()

                    Image(systemName: "camera.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)

                    Text("Camera Error")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal)

                    HStack(spacing: 12) {
                        Button("Retry") {
                            phase = .recording
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)

                        Button("Exit") {
                            onFinish?(nil)
                            presentationMode.wrappedValue.dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.gray)
                    }

                    Spacer()
                }
                .background(Color.black.edgesIgnoringSafeArea(.all))
                .navigationBarBackButtonHidden(true)
                .navigationBarHidden(true)
            }
        }
    }

    // MARK: - Header
    private func header(text: String) -> some View {
        Text(text)
            .font(.title3).fontWeight(.semibold)
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.3))
    }

    @MainActor
    private func startAutoUploadIfNeeded(_ url: URL) async {
        guard !uploadStarted else { return }
        uploadStarted = true
        isUploading = true
        uploadErrorMessage = nil

        do {
            let uploader = VideoUploadService(supabase: authService.supabaseClient)
            let job = try await uploader.uploadVideoAndCreateJobForCurrentUser(
                videoURL: url,
                exerciseName: exerciseName
            )
            print("RecordingPage: Uploaded video and queued job \(job.jobId)")

            isUploading = false

            // Auto-advance immediately after upload and queue succeed.
            onFinish?(url)
            NotificationCenter.default.post(name: .recordingAccepted, object: nil)
            presentationMode.wrappedValue.dismiss()
        } catch {
            print("RecordingPage: Auto-upload failed: \(error)")
            isUploading = false
            uploadStarted = false
            uploadErrorMessage = error.localizedDescription
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let recordingAccepted = Notification.Name("recordingAccepted")
    static let assessmentCompleted = Notification.Name("assessmentCompleted")
    static let flipCamera = Notification.Name("flipCamera")
    static let recordingStateChanged = Notification.Name("recordingStateChanged")
}
