import SwiftUI
import AVKit

struct RecordingPage: View {
    enum Phase {
        case recording
        case review(url: URL)
        case error(message: String)
    }
    
    var exerciseName: String
    var onFinish: ((URL?) -> Void)? = nil
    
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var authService: AuthenticationService
    @State private var phase: Phase = .recording
    @State private var isUploading = false
    @State private var uploadErrorMessage: String?
    @State private var uploadStarted = false
    
    var body: some View {
        Group {
            switch phase {
            case .recording:
                VStack(spacing: 0) {
                    header(text: "Your turn to practice!")

                    // Camera view - it will call onFinishRecording when recording is completed
                    CameraRecorderView(exerciseName: exerciseName) { url in
                        print("RecordingPage: Camera callback received with URL: \(String(describing: url))")
                        // Use explicit main thread dispatch to ensure state updates happen correctly
                        DispatchQueue.main.async {
                            if let url = url {
                                print("RecordingPage: Transitioning to review phase")
                                phase = .review(url: url)
                            } else {
                                // Camera failed or was cancelled
                                print("RecordingPage: Camera failed, showing error")
                                phase = .error(message: "Camera recording failed. Please try again or check camera permissions.")
                            }
                        }
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
                            // Delete the file and retake
                            if FileManager.default.fileExists(atPath: url.path) {
                                try? FileManager.default.removeItem(at: url)
                            }
                            uploadStarted = false
                            uploadErrorMessage = nil
                            phase = .recording
                        } label: {
                            Label("Retake", systemImage: "arrow.counterclockwise") // [Phase 1]
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        
                        Button {
                            // If upload already completed, continue; otherwise upload is still running automatically.
                            if !isUploading, uploadStarted {
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
                            print("RecordingPage: Exit button tapped due to camera error")
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
        .onAppear {
            print("RecordingPage: Appeared for exercise: \(exerciseName)")
        }
        .onDisappear {
            print("RecordingPage: Disappeared for exercise: \(exerciseName)")
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

// MARK: - Notification Name used by PageOne to refresh streak/calendar
extension Notification.Name {
    static let recordingAccepted = Notification.Name("recordingAccepted")
}

