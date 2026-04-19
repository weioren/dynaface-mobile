import SwiftUI
import AVKit


struct PracticePage: View {
    let exercises: [Exercise]
    @State private var index: Int = 0
    @State private var showRecorder = false
    @State private var showCompletionAlert = false
    @State private var isUploading = false
    @State private var uploadErrorMessage: String?
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject private var authService: AuthenticationService

    var body: some View {
        if exercises.isEmpty {
            Text("No exercises selected.")
                .padding()
        } else {
            let current = exercises[index]
            VStack(alignment: .center, spacing: 20) {
                // [Phase 1] Progress bar
                VStack(spacing: 8) {
                    Text("Exercise \(index + 1) of \(exercises.count)")
                        .font(.title3)
                    ProgressView(value: Double(index + 1), total: Double(exercises.count))
                        .progressViewStyle(LinearProgressViewStyle(tint: Color(red: 0.12, green: 0.29, blue: 0.64)))
                        .padding(.horizontal)
                }
                .padding(.top, 12)

                Text(current.title)
                    .font(.title)
                    .fontWeight(.semibold)

                Text(current.instructions)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 10)

                if let video = current.videoFileName {
                    ExercisePlayerView(videoName: video)
                        .id(video)                // 🔑 force rebuild when video changes
                        .frame(maxWidth: .infinity)
                        .cornerRadius(10)
                        .padding(.horizontal)
                } else {
                    Text("No video available for this exercise.")
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }

                Spacer()

                Button {
                    print("PracticePage: Start Exercise button tapped for exercise \(index + 1)")
                    showRecorder = true
                } label: {
                    Text("Start Exercise")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(red: 0.12, green: 0.29, blue: 0.64))
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                .disabled(isUploading)
                .fullScreenCover(isPresented: $showRecorder) {
                    // Recorder presents review (playback) and calls onFinish only on Accept
                    RecordingPage(
                        exerciseName: current.title,
                        onFinish: { url in
                            print("PracticePage: onFinish called with URL: \(String(describing: url))")

                            // Ensure UI updates happen on main thread
                            DispatchQueue.main.async {
                                showRecorder = false

                                guard let url = url else {
                                    print("PracticePage: Recording failed or was cancelled, staying on exercise \(index + 1)")
                                    return
                                }

                                Task {
                                    await MainActor.run {
                                        isUploading = true
                                        uploadErrorMessage = nil
                                    }

                                    do {
                                        let uploader = VideoUploadService(supabase: authService.supabaseClient)
                                        let job = try await uploader.uploadVideoAndCreateJobForCurrentUser(
                                            videoURL: url,
                                            exerciseName: current.title
                                        )

                                        print("PracticePage: Uploaded video and queued job \(job.jobId)")

                                        await MainActor.run {
                                            isUploading = false

                                            if index < exercises.count - 1 {
                                                index += 1
                                                print("PracticePage: Moving to next exercise: \(index + 1) of \(exercises.count)")
                                            } else {
                                                print("PracticePage: All exercises completed!")
                                                showCompletionAlert = true
                                            }
                                        }
                                    } catch {
                                        print("PracticePage: Upload or queue failed: \(error)")
                                        await MainActor.run {
                                            isUploading = false
                                            uploadErrorMessage = error.localizedDescription
                                        }
                                    }
                                }
                            }
                        }
                    )
                    .interactiveDismissDisabled(true) // can't swipe away
                }
                .onChange(of: showRecorder) { isShowing in
                    // Handle when the recorder is dismissed
                    if !isShowing {
                        print("PracticePage: Recorder dismissed, checking if we should proceed to next exercise")
                        // The onFinish callback should handle the flow, but if it doesn't,
                        // we can add additional logic here if needed
                    }
                }
            }
            .navigationBarBackButtonHidden(true) // prevent bypass
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                }
            }
            .onAppear {
                print("PracticePage: Appeared with \(exercises.count) exercises, current index: \(index)")
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
            .overlay {
                if isUploading {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                            Text("Uploading video and queuing job...")
                                .font(.headline)
                        }
                        .padding(24)
                        .background(Color.white)
                        .cornerRadius(14)
                        .shadow(radius: 10)
                    }
                }
            }
            // [Phase 1] Completion — dismiss back to Dashboard
            .alert("All exercises completed", isPresented: $showCompletionAlert) {
                Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            } message: {
                Text("Great job! You've finished all \(exercises.count) exercises.")
            }
        }
    }
}

// Reusable player (unchanged)
struct ExercisePlayerView: View {
    let videoName: String
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(contentMode: .fit)
                    .onAppear { player.seek(to: .zero); player.play() }
                    .onDisappear { player.pause() }
            } else {
                Text("Video could not be loaded.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .onAppear(perform: load)
        .onChange(of: videoName) { _ in
            player?.pause()
            player = nil
            load()
        }
    }

    private func load() {
        // Try MOV first, then fall back to mp4
        if let url = Bundle.main.url(forResource: videoName, withExtension: "MOV") {
            player = AVPlayer(url: url)
        } else if let url = Bundle.main.url(forResource: videoName, withExtension: "mp4") {
            player = AVPlayer(url: url)
        }
    }
}
