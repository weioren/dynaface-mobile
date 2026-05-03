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
    @State private var phase: Phase = .recording
    @State private var showDemoVideo = true
    @State private var isRecording = false

    var body: some View {
        Group {
            switch phase {
            case .recording:
                ZStack {
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

                    VStack(spacing: 0) {
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

                    AdaptiveMirroredPlayer(url: url, heightFraction: 0.96)
                        .background(Color.black)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    HStack(spacing: 12) {
                        Button(role: .destructive) {
                            if FileManager.default.fileExists(atPath: url.path) {
                                try? FileManager.default.removeItem(at: url)
                            }
                            phase = .recording
                        } label: {
                            Label("Retake", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)

                        Button {
                            onFinish?(url)
                            NotificationCenter.default.post(name: .recordingAccepted, object: nil)
                            presentationMode.wrappedValue.dismiss()
                        } label: {
                            Label("Save & Continue", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.12, green: 0.29, blue: 0.64))
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
                .background(Color.black.edgesIgnoringSafeArea(.all))
                .navigationBarBackButtonHidden(true)
                .navigationBarHidden(true)
                .interactiveDismissDisabled(true)

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

    private func header(text: String) -> some View {
        Text(text)
            .font(.title3).fontWeight(.semibold)
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.3))
    }
}

extension Notification.Name {
    static let recordingAccepted = Notification.Name("recordingAccepted")
    static let assessmentCompleted = Notification.Name("assessmentCompleted")
    static let processedVideosUpdated = Notification.Name("processedVideosUpdated")
    static let flipCamera = Notification.Name("flipCamera")
    static let recordingStateChanged = Notification.Name("recordingStateChanged")
}
