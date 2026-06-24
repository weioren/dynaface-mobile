import SwiftUI
import AVKit


struct PracticePage: View {
    enum PracticePhase: Equatable {
        case exercising
        case review
        case rerecording(Int)
    }

    let exercises: [Exercise]
    /// The patient this assessment is for. Clinician path: the patient
    /// picked before recording. Patient self-record: nil (defaults to self).
    var target: PatientRef? = nil
    @State private var index: Int = 0
    @State private var recordings: [Int: URL] = [:]
    @State private var showRecorder = false
    @State private var phase: PracticePhase = .exercising
    @State private var expandedExerciseIndex: Int? = nil
    @State private var showRerecorder = false
    @State private var isUploadingAll = false
    @State private var uploadErrorMessage: String?
    @State private var uploadedCount: Int = 0
    @AppStorage("videoUploadsEnabled") private var videoUploadsEnabled = true
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject private var authService: AuthenticationService
    // Phase 8: needed so the attribution sheet inherits these via explicit
    // .environmentObject() — sheets sometimes lose env chain on push.
    @EnvironmentObject private var patientService: PatientService
    @EnvironmentObject private var attributionService: JobAttributionService

    var body: some View {
        if exercises.isEmpty {
            Text("No exercises selected.")
                .padding()
        } else {
            switch phase {
            case .exercising:
                exercisingView
            case .review, .rerecording:
                reviewView
            }
        }
    }

    // MARK: - Exercising Phase
    private var exercisingView: some View {
        let current = exercises[index]
        return VStack(spacing: 0) {
            if let target {
                Text("Recording for \(target.displayName)")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64))
                    .padding(.top, 8)
            }
            // Exercise title and instructions
            VStack(spacing: 6) {
                Text(current.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(current.instructions)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, 8)
            .padding(.bottom, 8)

            // Demo video
            if let video = current.videoFileName {
                ExercisePlayerView(videoName: video)
                    .id(video)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
                    .cornerRadius(10)
                    .padding(.horizontal)
            } else {
                Text("No video available for this exercise.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Start Exercise button
            Button {
                showRecorder = true
            } label: {
                Text("Start Exercise")
                    .foregroundColor(.white)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(red: 0.12, green: 0.29, blue: 0.64))
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Bottom step progress bar
            StepProgressBar(
                totalSteps: exercises.count,
                currentStep: index,
                completedSteps: Set(recordings.keys)
            )
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    if index > 0 {
                        if let url = recordings[index - 1] {
                            try? FileManager.default.removeItem(at: url)
                        }
                        recordings.removeValue(forKey: index - 1)
                        index -= 1
                    } else {
                        presentationMode.wrappedValue.dismiss()
                    }
                }) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showRecorder) {
            RecordingPage(
                exerciseName: current.title,
                exerciseVideoName: current.videoFileName,
                currentStep: index + 1,
                totalSteps: exercises.count,
                completedSteps: Set(recordings.keys),
                onFinish: { url in
                    DispatchQueue.main.async {
                        showRecorder = false
                        guard let url = url else {
                            return
                        }

                        recordings[index] = url
                        if index < exercises.count - 1 {
                            index += 1
                        } else {
                            phase = .review
                        }
                    }
                }
            )
            .interactiveDismissDisabled(true)
        }
    }

    // MARK: - Review Phase
    private var reviewView: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.green)
                    .padding(.top, 20)

                Text("All exercises done!")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("\(recordings.count) of \(exercises.count) recorded")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let target {
                    Text("For \(target.displayName)")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64))
                }
            }
            .padding(.bottom, 16)

            // Exercise list
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(exercises.indices, id: \.self) { i in
                        VStack(spacing: 0) {
                            // Row: left side tappable for accordion, right side for re-record
                            HStack(spacing: 0) {
                                // Tappable area: expand/collapse accordion
                                HStack(spacing: 12) {
                                    // Green circle with checkmark
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(.white)
                                        )

                                    Text("\(i + 1). \(exercises[i].title)")
                                        .font(.body)
                                        .foregroundColor(.primary)

                                    Spacer()

                                    // Chevron indicator
                                    Image(systemName: expandedExerciseIndex == i ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.gray)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        expandedExerciseIndex = (expandedExerciseIndex == i) ? nil : i
                                    }
                                }

                                // Re-record button (isolated from row tap)
                                Button(action: {
                                    expandedExerciseIndex = nil
                                    phase = .rerecording(i)
                                }) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 16))
                                        .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                }
                            }
                            .padding(.leading, 16)
                            .padding(.trailing, 4)
                            .padding(.vertical, 2)

                            // Accordion: inline video preview
                            if expandedExerciseIndex == i, let url = recordings[i] {
                                MirroredAVPlayerControllerView(url: url, loop: true)
                                    .frame(height: 220)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 10)
                                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                            }

                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
            }

            if isUploadingAll {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Uploading videos and queuing jobs... \(uploadedCount)/\(exercises.count)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)
            }

            // Upload + Finish button
            Button {
                Task {
                    await uploadAllRecordingsAndFinish()
                }
            } label: {
                Text(isUploadingAll
                     ? "Uploading..."
                     : ((videoUploadsEnabled || isClinician) ? "Upload All & Finish" : "Finish Assessment"))
                    .foregroundColor(.white)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(red: 0.12, green: 0.29, blue: 0.64))
                    .cornerRadius(10)
            }
            .disabled(isUploadingAll || recordings.count != exercises.count)
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    // Discard this assessment and return to exercise
                    // selection so the clinician can re-pick the patient.
                    cleanupRecordings()
                    presentationMode.wrappedValue.dismiss()
                }
                .disabled(isUploadingAll)
            }
        }
        .onChange(of: phase) { newPhase in
            if case .rerecording = newPhase {
                showRerecorder = true
            }
        }
        .fullScreenCover(isPresented: $showRerecorder) {
            if case .rerecording(let exerciseIndex) = phase {
                let exercise = exercises[exerciseIndex]
                RecordingPage(
                    exerciseName: exercise.title,
                    exerciseVideoName: exercise.videoFileName,
                    currentStep: exerciseIndex + 1,
                    totalSteps: exercises.count,
                    completedSteps: Set(recordings.keys),
                    onFinish: { url in
                        DispatchQueue.main.async {
                            showRerecorder = false
                            if let newURL = url {
                                // Delete old recording, store new
                                if let oldURL = recordings[exerciseIndex] {
                                    try? FileManager.default.removeItem(at: oldURL)
                                }
                                recordings[exerciseIndex] = newURL
                                // Auto-expand to show re-recorded video
                                expandedExerciseIndex = exerciseIndex
                            }
                            // If nil (cancelled), keep old recording
                            phase = .review
                        }
                    }
                )
                .interactiveDismissDisabled(true)
            }
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
    }

    @MainActor
    private func uploadAllRecordingsAndFinish() async {
        guard !isUploadingAll else { return }
        guard recordings.count == exercises.count else {
            uploadErrorMessage = "Please complete all selected exercises before uploading."
            return
        }

        // Honour the upload toggle only for patient self-records. Clinicians
        // always upload (the recordings belong to the chosen patient).
        if !videoUploadsEnabled && !isClinician {
            NotificationCenter.default.post(name: .assessmentCompleted, object: nil)
            NotificationCenter.default.post(name: .recordingAccepted, object: nil)
            presentationMode.wrappedValue.dismiss()
            return
        }

        isUploadingAll = true
        uploadErrorMessage = nil
        uploadedCount = 0

        do {
            let uploader = VideoUploadService()
            var collected: [(jobId: UUID, exerciseName: String)] = []

            for i in exercises.indices {
                guard let videoURL = recordings[i] else {
                    throw NSError(
                        domain: "PracticePage",
                        code: 1001,
                        userInfo: [NSLocalizedDescriptionKey: "Missing recording for exercise \(i + 1)."]
                    )
                }

                let job = try await uploader.uploadVideoAndCreateJobForCurrentUser(
                    videoURL: videoURL,
                    exerciseName: exercises[i].title
                )
                collected.append((job.jobId, exercises[i].title))
                uploadedCount += 1
            }

            NotificationCenter.default.post(name: .processedVideosUpdated, object: nil)

            // Auto-attribute to the pre-selected patient and auto-log the
            // assessment — no post-upload sheet, no "Add to timeline?" alert.
            await attributeAndLog(collected)

            finishAfterAttribution()
        } catch {
            uploadErrorMessage = error.localizedDescription
            isUploadingAll = false
        }
    }

    /// Attributes every uploaded job to the assessment's patient and writes
    /// one `assessment` timeline event PER exercise (so the timeline can
    /// stack them by day and replay each action individually).
    ///   - clinician: patient = the pre-selected `target`
    ///   - patient self-record: patient = themselves (the uploader)
    /// `createdBy` is ALWAYS the uploader — RLS (created_by = auth.uid())
    /// and the annotated-video storage path both depend on it.
    @MainActor
    private func attributeAndLog(_ jobs: [(jobId: UUID, exerciseName: String)]) async {
        guard
            case .signedIn(let profile) = authService.authState,
            let uploaderId = UUID(uuidString: profile.id)
        else { return }

        let patientId = target?.id ?? uploaderId

        // Clinician path: link each job to the chosen patient. A patient
        // self-record already associates via processing_jobs.user_id.
        if let target, target.id != uploaderId {
            for job in jobs {
                _ = await attributionService.attribute(
                    jobId: job.jobId,
                    patientId: target.id,
                    attributedBy: uploaderId
                )
            }
        }

        let timeline = TimelineService(patientId: patientId)
        for job in jobs {
            _ = await timeline.addAssessmentEvent(
                jobId: job.jobId,
                occurredAt: Date(),
                exerciseNames: [job.exerciseName],
                createdBy: uploaderId
            )
        }
    }


    private var isClinician: Bool {
        if case .signedIn(let profile) = authService.authState {
            return profile.accountType == .clinician
        }
        return false
    }

    private func cleanupRecordings() {
        for url in recordings.values {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func finishAfterAttribution() {
        NotificationCenter.default.post(name: .assessmentCompleted, object: nil)
        NotificationCenter.default.post(name: .recordingAccepted, object: nil)
        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - Step Progress Bar
struct StepProgressBar: View {
    let totalSteps: Int
    let currentStep: Int
    let completedSteps: Set<Int>

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Circle()
                    .fill(circleColor(for: step))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Group {
                            if completedSteps.contains(step) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            } else {
                                Text("\(step + 1)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(step == currentStep ? .white : .gray)
                            }
                        }
                    )

                if step < totalSteps - 1 {
                    Rectangle()
                        .fill(completedSteps.contains(step) ? Color.green : Color.gray.opacity(0.3))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func circleColor(for step: Int) -> Color {
        if completedSteps.contains(step) {
            return .green
        } else if step == currentStep {
            return Color(red: 0.12, green: 0.29, blue: 0.64)
        } else {
            return Color.gray.opacity(0.3)
        }
    }
}

// MARK: - PiP Demo Player (fill frame, no black bars, no controls)
struct PiPDemoPlayer: UIViewRepresentable {
    let videoName: String

    func makeUIView(context: Context) -> PiPPlayerUIView {
        let view = PiPPlayerUIView()
        view.load(videoName: videoName)
        return view
    }

    func updateUIView(_ uiView: PiPPlayerUIView, context: Context) {}
}

class PiPPlayerUIView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var loopObserver: NSObjectProtocol?

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    func load(videoName: String) {
        var url: URL?
        if let u = Bundle.main.url(forResource: videoName, withExtension: "MOV") {
            url = u
        } else if let u = Bundle.main.url(forResource: videoName, withExtension: "mp4") {
            url = u
        }
        guard let videoURL = url else { return }

        let player = AVPlayer(url: videoURL)
        player.isMuted = true
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        self.layer.addSublayer(layer)

        self.player = player
        self.playerLayer = layer

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }

        player.seek(to: .zero)
        player.play()
    }

    deinit {
        if let obs = loopObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        player?.pause()
    }
}

// MARK: - Reusable player with looping
struct ExercisePlayerView: View {
    let videoName: String
    @State private var player: AVPlayer?
    @State private var loopObserver: NSObjectProtocol?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(contentMode: .fit)
                    .onAppear {
                        player.seek(to: .zero)
                        player.play()
                        addLoopObserver()
                    }
                    .onDisappear {
                        player.pause()
                        removeLoopObserver()
                    }
            } else {
                Text("Video could not be loaded.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .onAppear(perform: load)
        .onChange(of: videoName) { _ in
            removeLoopObserver()
            player?.pause()
            player = nil
            load()
        }
    }

    private func load() {
        if let url = Bundle.main.url(forResource: videoName, withExtension: "MOV") {
            player = AVPlayer(url: url)
        } else if let url = Bundle.main.url(forResource: videoName, withExtension: "mp4") {
            player = AVPlayer(url: url)
        }
    }

    private func addLoopObserver() {
        guard let player = player, loopObserver == nil else { return }
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
    }

    private func removeLoopObserver() {
        if let obs = loopObserver {
            NotificationCenter.default.removeObserver(obs)
            loopObserver = nil
        }
    }
}
