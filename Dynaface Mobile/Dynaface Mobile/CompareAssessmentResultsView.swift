import SwiftUI
import FirebaseFirestore

// MARK: - CompareAssessmentResultsView
//
// Two stacked video players (earlier date on top, later underneath) for
// the same exercise across the two selected assessments. By default we
// resolve the RAW recording (mirrors AssessmentVideoDetailView's
// "Original" segment); the "Show Dynaface annotations" toggle flips to
// the processed/annotated version (mirrors the "Processed" segment).
//
// Job lookup + signed-URL resolution use the same helpers the timeline
// uses for single-exercise playback (`signedRawVideoURL` /
// `signedProcessedVideoURL`), so playback behavior stays identical.
//
// `keyImageOnly` is plumbed through but unused in V1 — reserved for the
// follow-up that swaps the player for a single key-frame image.

struct CompareAssessmentResultsView: View {
    let patientName: String
    let exerciseTitle: String
    let firstDay: Date
    let firstJobId: UUID?
    let secondDay: Date
    let secondJobId: UUID?
    let showAnnotations: Bool
    let keyImageOnly: Bool

    @EnvironmentObject private var authService: AuthenticationService

    @State private var firstURL: URL?
    @State private var firstError: String?
    @State private var firstLoading: Bool = true

    @State private var secondURL: URL?
    @State private var secondError: String?
    @State private var secondLoading: Bool = true

    /// GMT-anchored medium date — same formatter the timeline group card
    /// uses, so the overlay reads back the date the user just selected.
    private static let dateLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.timeZone = TimeZone(identifier: "GMT")
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            videoCell(
                day: firstDay,
                url: firstURL,
                isLoading: firstLoading,
                error: firstError
            )
            Divider()
            videoCell(
                day: secondDay,
                url: secondURL,
                isLoading: secondLoading,
                error: secondError
            )
        }
        .navigationTitle(patientName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadBoth() }
    }

    // MARK: - Cell

    @ViewBuilder
    private func videoCell(day: Date, url: URL?, isLoading: Bool, error: String?) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black
            if let url {
                // `.id(url)` forces a fresh AVPlayerViewController instance
                // when the URL changes (e.g. if state ever reloads), matching
                // AssessmentVideoDetailView's behavior on segment swap.
                PlainAVPlayerControllerView(url: url).id(url)
            } else if isLoading {
                ProgressView().tint(.white)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.gray.opacity(0.7))
                    Text(error ?? "Video unavailable.")
                        .font(.subheadline)
                        .foregroundColor(.gray.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
            Text(Self.dateLabelFormatter.string(from: day))
                .font(.caption).fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.black.opacity(0.55))
                .cornerRadius(6)
                .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading
    //
    // Two independent fetches run in parallel via `async let` so a slow
    // signed-URL call on one side doesn't delay the other. Each slot
    // owns its own loading/error state; one failing doesn't poison the
    // other player.

    private func loadBoth() async {
        async let a: () = loadFirst()
        async let b: () = loadSecond()
        _ = await (a, b)
    }

    private func loadFirst() async {
        await load(jobId: firstJobId) { url, err in
            firstURL = url
            firstError = err
            firstLoading = false
        }
    }

    private func loadSecond() async {
        await load(jobId: secondJobId) { url, err in
            secondURL = url
            secondError = err
            secondLoading = false
        }
    }

    /// Fetches the processing_jobs row by id, resolves a signed URL for
    /// the raw or processed bucket (chosen by `showAnnotations`), and
    /// hands the result back to the caller's slot setter. Mirrors the
    /// resolution path used by `AssessmentVideoDetailView.resolve`.
    private func load(
        jobId: UUID?,
        commit: @MainActor (URL?, String?) -> Void
    ) async {
        guard let jobId else {
            commit(nil, "This assessment is missing the selected exercise.")
            return
        }
        do {
            let snapshot = try await Firestore.firestore()
                .collection("processing_jobs")
                .document(jobId.uuidString)
                .getDocument()
            guard let data = snapshot.data(),
                  let job = decodeJobRow(id: jobId.uuidString, data: data) else {
                commit(nil, showAnnotations
                    ? "Processed video isn't ready yet."
                    : "Original video unavailable.")
                return
            }
            let url: URL = try await (showAnnotations
                ? signedProcessedVideoURL(for: job)
                : signedRawVideoURL(for: job))
            commit(url, nil)
        } catch {
            commit(nil, showAnnotations
                ? "Processed video isn't ready yet."
                : "Original video unavailable.")
        }
    }
}
