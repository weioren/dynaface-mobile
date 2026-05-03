import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

// MARK: - UploadVideoPage
// Lets the user pick a video from their Photos library and attach it to a
// facial-exercise slot. The imported video is saved to Documents with the
// canonical `<ExerciseTitle>_<N>.mov` filename so it flows through the same
// pipeline as native recordings: History auto-picks it up (and auto-expands
// the new "Today" section), HomePage streak recomputes, and Alex's future
// upload worker handles it identically.

struct UploadVideoPage: View {
    enum Phase: Equatable {
        case empty
        case loading
        case previewing(url: URL)
        case readyToSave(url: URL, exercise: Exercise)
        case saving
        case savedFlash
    }

    @State private var phase: Phase = .empty
    @State private var selectedItem: PhotosPickerItem?
    @State private var showExerciseSheet = false
    @State private var errorMessage: String?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 16) {
                Text("Upload")
                    .font(.system(size: 24))
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)

                content(in: geometry)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showExerciseSheet) { exercisePickerSheet }
        .alert(
            "Upload failed",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            presenting: errorMessage
        ) { _ in
            Button("OK", role: .cancel) { resetToEmpty() }
        } message: { msg in
            Text(msg)
        }
    }

    // MARK: - Content by phase

    @ViewBuilder
    private func content(in geometry: GeometryProxy) -> some View {
        switch phase {
        case .empty:
            emptyState
        case .loading:
            loadingState
        case .previewing(let url):
            previewState(url: url, exercise: nil)
        case .readyToSave(let url, let exercise):
            previewState(url: url, exercise: exercise)
        case .saving:
            ZStack {
                if case .readyToSave(let url, let exercise) = lastStateBeforeSaving {
                    previewState(url: url, exercise: exercise)
                        .disabled(true)
                        .opacity(0.5)
                }
                ProgressView("Saving…")
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }
        case .savedFlash:
            savedFlashState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "square.and.arrow.up.on.square")
                .font(.system(size: 64))
                .foregroundColor(.gray.opacity(0.7))
            Text("Import a video from Photos and attach it to an exercise.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            PhotosPicker(
                selection: $selectedItem,
                matching: .videos,
                preferredItemEncoding: .current
            ) {
                Label("Choose a video", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.12, green: 0.29, blue: 0.64))
                    .cornerRadius(12)
            }
            Spacer()
        }
        .onChange(of: selectedItem) { newItem in
            handlePickerSelection(newItem)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text("Loading video…")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private func previewState(url: URL, exercise: Exercise?) -> some View {
        VStack(spacing: 12) {
            MirroredAVPlayerControllerView(url: url, loop: true)
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .cornerRadius(12)
                .padding(.horizontal)

            HStack(spacing: 8) {
                Text("Selected exercise:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(exercise?.title ?? "—")
                    .font(.subheadline)
                    .fontWeight(exercise == nil ? .regular : .semibold)
                    .foregroundColor(exercise == nil ? .gray : .primary)
                Spacer()
            }
            .padding(.horizontal)

            Button {
                showExerciseSheet = true
            } label: {
                Label(exercise == nil ? "Select exercise" : "Change exercise",
                      systemImage: "list.bullet")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)

            Button {
                if case .readyToSave(let url, let ex) = phase {
                    save(url: url, exercise: ex)
                }
            } label: {
                Label("Save to history", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(exercise == nil
                                ? Color.gray.opacity(0.5)
                                : Color(red: 0.12, green: 0.29, blue: 0.64))
                    .cornerRadius(12)
            }
            .disabled(exercise == nil)
            .padding(.horizontal)

            Button(role: .destructive) {
                discardCurrentPreview(url: url)
            } label: {
                Text("Discard")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .padding(.horizontal)

            Spacer(minLength: 8)
        }
    }

    private var savedFlashState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            Text("Saved")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Your video has been added to History.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Exercise selection sheet

    private var exercisePickerSheet: some View {
        NavigationView {
            List(allExercises) { exercise in
                Button {
                    pickExercise(exercise)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.title)
                                .font(.body)
                                .foregroundColor(.primary)
                            Text(exercise.instructions)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        if case .readyToSave(_, let current) = phase, current.id == exercise.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle("Select exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { showExerciseSheet = false }
                }
            }
        }
    }

    // MARK: - State transitions

    // Used only to re-render the preview underneath the `.saving` overlay; the
    // real "source of truth" is `phase`, but once we flip to `.saving` we lose
    // the url/exercise associated values. Capture them when we flip.
    @State private var lastStateBeforeSaving: Phase = .empty

    private func handlePickerSelection(_ item: PhotosPickerItem?) {
        guard let item else { return }
        phase = .loading
        Task {
            do {
                let movie = try await item.loadTransferable(type: Movie.self)
                await MainActor.run {
                    guard let url = movie?.url else {
                        errorMessage = "Couldn't load the selected video. If it lives in iCloud, check your network connection."
                        selectedItem = nil
                        return
                    }
                    phase = .previewing(url: url)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    selectedItem = nil
                }
            }
        }
    }

    private func pickExercise(_ exercise: Exercise) {
        showExerciseSheet = false
        switch phase {
        case .previewing(let url), .readyToSave(let url, _):
            phase = .readyToSave(url: url, exercise: exercise)
        default:
            break
        }
    }

    private func save(url: URL, exercise: Exercise) {
        lastStateBeforeSaving = phase
        phase = .saving
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try saveImportedVideo(from: url, exerciseTitle: exercise.title)
                DispatchQueue.main.async {
                    // Delete the temp file now that we've copied it to Documents.
                    try? FileManager.default.removeItem(at: url)
                    NotificationCenter.default.post(name: .recordingAccepted, object: nil)
                    phase = .savedFlash
                    selectedItem = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        // Only reset if the user hasn't already moved on (e.g. picked
                        // another video in the meantime).
                        if phase == .savedFlash { phase = .empty }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = "Couldn't save the video: \(error.localizedDescription)"
                }
            }
        }
    }

    private func discardCurrentPreview(url: URL) {
        try? FileManager.default.removeItem(at: url)
        selectedItem = nil
        phase = .empty
    }

    private func resetToEmpty() {
        if case .previewing(let url) = phase { try? FileManager.default.removeItem(at: url) }
        if case .readyToSave(let url, _) = phase { try? FileManager.default.removeItem(at: url) }
        selectedItem = nil
        phase = .empty
    }
}

// MARK: - Transferable wrapper
//
// Using `FileRepresentation` (rather than `Data`) keeps the whole file on disk —
// iOS streams it from the Photos library into a temp URL and hands it to us.
// We copy it into our own temp dir because the system-vended URL is only valid
// inside the importing closure.

struct Movie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".mov")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return Self(url: dest)
        }
    }
}

// MARK: - Preview
#Preview {
    UploadVideoPage()
}
