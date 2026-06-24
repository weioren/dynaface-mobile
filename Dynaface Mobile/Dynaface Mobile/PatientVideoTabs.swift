import SwiftUI
import FirebaseFirestore
import FirebaseStorage

// MARK: - PatientVideoTabs
//
// History + Processed sub-tab content for PatientDetailView. Both
// tabs surface every recording associated with the patient via two
// independent sources, unioned client-side:
//
//   1. Self-recorded jobs — `processing_jobs.user_id = patient.id`
//      (the patient recorded on their own device).
//   2. Attribution-linked jobs — documents in `job_patient_attributions`
//      where `patient_id = patient.id` (typically a clinician
//      recorded for the patient and picked them in the post-upload
//      attribution sheet).
//
// We don't union server-side because the two queries have different
// shapes (one filters by user_id, the other looks up by document ID),
// and Firestore doesn't support that kind of join either. Two round-trips,
// merge in Swift — same approach as the old Supabase version.

// MARK: - PatientHistoryTab
//
// Every processing_jobs document for this patient regardless of status.
// Renders a simple chronological list — date, exercise, status pill.

struct PatientHistoryTab: View {
    let patientId: UUID

    @EnvironmentObject private var authService: AuthenticationService
    @EnvironmentObject private var attributionService: JobAttributionService

    // Mirrors the "Upload videos to cloud" toggle in ProfilePage. When
    // OFF and the user is viewing their OWN My care, show an empty-state
    // hint explaining recordings aren't synced — we don't fall back to
    // local files per product decision.
    @AppStorage("videoUploadsEnabled") private var videoUploadsEnabled = true

    @State private var jobs: [PatientJobRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedVideo: PatientProcessedPlayback?
    @State private var activeDownloadJobId: UUID?

    private var cloudDisabledForSelf: Bool {
        isOwnDetail(patientId, authService: authService) && !videoUploadsEnabled
    }

    var body: some View {
        Group {
            if isLoading && jobs.isEmpty {
                ProgressView("Loading recordings…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if jobs.isEmpty {
                emptyState
            } else {
                List(jobs) { job in
                    Button {
                        Task { await openOriginalVideo(job) }
                    } label: {
                        HStack {
                            PatientJobListRow(job: job)
                            if activeDownloadJobId == job.id {
                                ProgressView()
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .task { await reloadIfNeeded() }
        .refreshable { await load() }
        .alert(
            "Couldn't load recordings",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            presenting: errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
        .sheet(item: $selectedVideo) { video in
            HistoryDetailView(
                videoURL: video.playbackURL,
                exerciseTitle: video.exerciseTitle,
                recordingDate: video.recordingDate
            )
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if cloudDisabledForSelf {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "icloud.slash")
                    .font(.system(size: 50))
                    .foregroundColor(.gray.opacity(0.5))
                Text("Cloud uploads are off")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Turn on \"Upload videos to cloud\" in Profile to see your recordings here.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            }
        } else {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "video.slash")
                    .font(.system(size: 50))
                    .foregroundColor(.gray.opacity(0.5))
                Text("No recordings yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Recordings uploaded for this patient will appear here.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            }
        }
    }

    @MainActor
    private func reloadIfNeeded() async {
        if jobs.isEmpty { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }

        // Patient with cloud upload disabled: don't hit the network —
        // the empty-state hint handles UX.
        if cloudDisabledForSelf {
            self.jobs = []
            return
        }

        do {
            let merged = try await fetchAllJobs(
                forPatient: patientId,
                attributionService: attributionService,
                onlyCompleted: false
            )
            self.jobs = merged
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Couldn't load recordings: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func openOriginalVideo(_ job: PatientJobRow) async {
        activeDownloadJobId = job.id
        defer { activeDownloadJobId = nil }
        do {
            let url = try await signedRawVideoURL(for: job)
            selectedVideo = PatientProcessedPlayback(
                id: job.id,
                playbackURL: url,
                exerciseTitle: (job.exercise_name?.isEmpty == false) ? job.exercise_name! : "Recording",
                recordingDate: displayDate(for: job)
            )
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Couldn't load this recording: \(error.localizedDescription)"
        }
    }

    private func displayDate(for job: PatientJobRow) -> String {
        guard let date = job.created_at else { return "Unknown date" }
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return f.string(from: date)
    }
}

// MARK: - PatientVideosTab
//
// Patient Dashboard "Videos" tab — merges the old History + Processed tabs
// into one, flippable between Original (raw recordings) and Analyzed
// (DynaFace-processed results) for the signed-in patient.

struct PatientVideosTab: View {
    @EnvironmentObject private var authService: AuthenticationService
    @State private var segment: Segment = .original

    enum Segment: String, CaseIterable, Identifiable {
        case original = "Original"
        case analyzed = "Analyzed"
        var id: String { rawValue }
    }

    private var selfId: UUID? {
        if case .signedIn(let profile) = authService.authState {
            return UUID(uuidString: profile.id)
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Videos")
                    .font(.largeTitle).fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Picker("Videos", selection: $segment) {
                ForEach(Segment.allCases) { seg in
                    Text(seg.rawValue).tag(seg)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if let selfId {
                switch segment {
                case .original:
                    PatientHistoryTab(patientId: selfId)
                case .analyzed:
                    PatientProcessedTab(patientId: selfId)
                }
            } else {
                Spacer()
                Text("Sign in to view your videos.")
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
    }
}

// MARK: - PatientProcessedTab
//
// Only completed jobs — i.e. processing_jobs documents with status =
// 'completed' AND an output_video_path. Used by clinicians (and
// the patient themselves) to find the annotated result video.

struct PatientProcessedTab: View {
    let patientId: UUID

    @EnvironmentObject private var authService: AuthenticationService
    @EnvironmentObject private var attributionService: JobAttributionService

    @AppStorage("videoUploadsEnabled") private var videoUploadsEnabled = true

    @State private var jobs: [PatientJobRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    // Playback state — mirrors ProcessedVideosPage in ExerciseHistoryPage.
    @State private var selectedVideo: PatientProcessedPlayback?
    @State private var activeDownloadJobId: UUID?

    private var cloudDisabledForSelf: Bool {
        isOwnDetail(patientId, authService: authService) && !videoUploadsEnabled
    }

    var body: some View {
        Group {
            if isLoading && jobs.isEmpty {
                ProgressView("Loading processed videos…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if jobs.isEmpty {
                emptyState
            } else {
                List(jobs) { job in
                    Button {
                        Task { await openProcessedVideo(job) }
                    } label: {
                        HStack {
                            PatientJobListRow(job: job)
                            if activeDownloadJobId == job.id {
                                ProgressView()
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .task { await reloadIfNeeded() }
        .refreshable { await load() }
        .alert(
            "Couldn't load processed videos",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            presenting: errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
        .sheet(item: $selectedVideo) { video in
            HistoryDetailView(
                videoURL: video.playbackURL,
                exerciseTitle: video.exerciseTitle,
                recordingDate: video.recordingDate
            )
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if cloudDisabledForSelf {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "icloud.slash")
                    .font(.system(size: 50))
                    .foregroundColor(.gray.opacity(0.5))
                Text("Cloud uploads are off")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Processed results live in the cloud. Turn on \"Upload videos to cloud\" in Profile to view them here.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            }
        } else {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "sparkles.tv")
                    .font(.system(size: 50))
                    .foregroundColor(.gray.opacity(0.5))
                Text("No processed videos yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Annotated results from DynaFace appear here once processing finishes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            }
        }
    }

    @MainActor
    private func reloadIfNeeded() async {
        if jobs.isEmpty { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }

        // No cloud → nothing to show on Processed. Surface a hint via
        // the empty state instead of running the query.
        if cloudDisabledForSelf {
            self.jobs = []
            return
        }

        do {
            let merged = try await fetchAllJobs(
                forPatient: patientId,
                attributionService: attributionService,
                onlyCompleted: true
            )
            self.jobs = merged.filter {
                let out = $0.output_video_path ?? $0.output_csv_path
                return !(out?.isEmpty ?? true)
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Couldn't load processed videos: \(error.localizedDescription)"
        }
    }

    // MARK: - Playback (mirrors ProcessedVideosPage in ExerciseHistoryPage)

    @MainActor
    private func openProcessedVideo(_ job: PatientJobRow) async {
        activeDownloadJobId = job.id
        defer { activeDownloadJobId = nil }

        do {
            let playbackURL = try await signedProcessedVideoURL(for: job)
            selectedVideo = PatientProcessedPlayback(
                id: job.id,
                playbackURL: playbackURL,
                exerciseTitle: job.exercise_name?.isEmpty == false ? job.exercise_name! : "Unknown Exercise",
                recordingDate: displayDate(for: job)
            )
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func displayDate(for job: PatientJobRow) -> String {
        guard let date = job.created_at else { return "Unknown date" }
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return f.string(from: date)
    }
}

// MARK: - PatientProcessedPlayback

private struct PatientProcessedPlayback: Identifiable {
    let id: UUID
    let playbackURL: URL
    let exerciseTitle: String
    let recordingDate: String
}

// MARK: - Shared processed-video path resolution
//
// Single source of truth for turning a job's stored output path into the
// candidate object paths in the results bucket. Used by BOTH the
// Processed tab and TimelinePage (via AssessmentVideoDetailView) so
// playback resolves identically. Paths are full in-bucket object paths
// (e.g. "results/{user}/{job}/annotated.mp4") exactly as
// google_remote_dynaface_worker.py writes them — no bucket-name prefix
// to strip, unlike the old Supabase setup where the bucket happened to
// also be named "results".

func processedVideoPathCandidates(
    outputVideoPath: String?,
    outputCsvPath: String?,
    userId: UUID?,
    jobId: UUID
) -> [String] {
    let base = outputVideoPath ?? outputCsvPath ?? ""
    var candidates: [String] = [base]

    if base.hasSuffix(".mov") {
        candidates.append(String(base.dropLast(4)) + ".mp4")
    } else if base.hasSuffix(".mp4") {
        candidates.append(String(base.dropLast(4)) + ".mov")
    } else if base.hasSuffix(".csv") {
        let stem = String(base.dropLast(4))
        candidates.append(stem + ".mp4")
        candidates.append(stem + ".mov")
    }

    let directory = (base as NSString).deletingLastPathComponent
    if !directory.isEmpty {
        candidates.append("\(directory)/annotated.mp4")
        candidates.append("\(directory)/annotated.mov")
    }

    // Canonical worker output convention fallback.
    if let userId {
        candidates.append("results/\(userId.uuidString)/\(jobId.uuidString)/annotated.mp4")
        candidates.append("results/\(userId.uuidString)/\(jobId.uuidString)/annotated.mov")
    }

    return dedupeNonEmpty(candidates)
}

/// The one and only "play this job's processed video" resolver. Called by
/// both the Processed tab and the timeline so playback is identical.
/// `downloadURL()` returns an authenticated, directly-playable HTTPS URL —
/// storage.rules (not a Supabase signed URL) is what gates access.
func signedProcessedVideoURL(for job: PatientJobRow) async throws -> URL {
    let candidates = processedVideoPathCandidates(
        outputVideoPath: job.output_video_path,
        outputCsvPath: job.output_csv_path,
        userId: job.user_id,
        jobId: job.id
    )
    let storage = Storage.storage(url: FirebaseConfig.resultsBucketURL)
    var lastError: Error?
    for path in candidates {
        do {
            return try await storage.reference(withPath: path).downloadURL()
        } catch {
            lastError = error
            continue
        }
    }
    throw lastError ?? NSError(
        domain: "PatientProcessedTab",
        code: 404,
        userInfo: [NSLocalizedDescriptionKey: "Processed video object not found in storage."]
    )
}

/// "Original" (raw) recording URL: `uploads/{user_id}/{job_id}/video.{mov|mp4}`
/// in the raw videos bucket. Used by the patient Videos "Original" segment.
func signedRawVideoURL(for job: PatientJobRow) async throws -> URL {
    var candidates: [String] = []
    // Prefer the exact stored upload path (mirrors how Analyzed uses
    // output_video_path), then fall back to the canonical convention.
    if let input = job.input_video_path, !input.isEmpty {
        candidates.append(input)
    }
    if let userId = job.user_id {
        candidates.append("uploads/\(userId.uuidString)/\(job.id.uuidString)/video.mov")
        candidates.append("uploads/\(userId.uuidString)/\(job.id.uuidString)/video.mp4")
    }
    let deduped = dedupeNonEmpty(candidates)

    let storage = Storage.storage(url: FirebaseConfig.rawVideosBucketURL)
    var lastError: Error?
    for path in deduped {
        do {
            return try await storage.reference(withPath: path).downloadURL()
        } catch {
            lastError = error
            continue
        }
    }
    throw lastError ?? NSError(domain: "PatientOriginal", code: 404,
                              userInfo: [NSLocalizedDescriptionKey: "Original recording not found in storage."])
}

private func dedupeNonEmpty(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var deduped: [String] = []
    for v in values where !v.isEmpty {
        if seen.insert(v).inserted { deduped.append(v) }
    }
    return deduped
}

// MARK: - AssessmentVideoDetailView
//
// Opened from a timeline movement. Flips between the Original (raw) and
// Processed (annotated) version of that one recording. Works for clinicians
// (any patient, registered or not) and the patient themselves — storage
// rules gate what each can actually read.

struct AssessmentVideoDetailView: View {
    let jobId: UUID
    let title: String
    let dateText: String

    @Environment(\.dismiss) private var dismiss

    enum Segment: String, CaseIterable, Identifiable {
        case original = "Original"
        case processed = "Processed"
        var id: String { rawValue }
    }

    @State private var segment: Segment = .original
    @State private var job: PatientJobRow?
    @State private var url: URL?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Version", selection: $segment) {
                    ForEach(Segment.allCases) { seg in
                        Text(seg.rawValue).tag(seg)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                ZStack {
                    if let url {
                        PlainAVPlayerControllerView(url: url)
                            .id(url)
                    } else if isLoading {
                        ProgressView()
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "video.slash")
                                .font(.system(size: 40))
                                .foregroundColor(.gray.opacity(0.5))
                            Text(errorMessage ?? "Video unavailable.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !dateText.isEmpty {
                    Text(dateText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: segment) { await resolve() }
        }
    }

    private func resolve() async {
        if job == nil {
            do {
                let snapshot = try await Firestore.firestore()
                    .collection("processing_jobs")
                    .document(jobId.uuidString)
                    .getDocument()
                guard let data = snapshot.data() else {
                    errorMessage = "Couldn't load this recording."
                    return
                }
                job = decodeJobRow(id: jobId.uuidString, data: data)
            } catch {
                errorMessage = "Couldn't load this recording."
                return
            }
        }
        guard let job else { return }

        isLoading = true
        errorMessage = nil
        url = nil
        defer { isLoading = false }
        do {
            switch segment {
            case .processed:
                url = try await signedProcessedVideoURL(for: job)
            case .original:
                url = try await signedRawVideoURL(for: job)
            }
        } catch {
            errorMessage = (segment == .processed)
                ? "Processed video isn't ready yet."
                : "Original video unavailable."
        }
    }
}

// MARK: - Shared fetch helper
//
// Two round-trips against `processing_jobs`:
//   1. user_id == patient.id  (self-recorded)
//   2. document ID IN (attribution job ids)  (clinician-recorded, attributed)
// Then merge + dedupe + sort newest first.

@MainActor
func fetchAllJobs(
    forPatient patientId: UUID,
    attributionService: JobAttributionService,
    onlyCompleted: Bool
) async throws -> [PatientJobRow] {

    // 1. Pull the attribution job IDs first. If the network blip happens
    //    here we still return whatever the user-side query gives.
    let attributedIds = await attributionService.loadAttributedJobIds(forPatient: patientId)

    let db = Firestore.firestore()

    // 2. Self-recorded jobs (processing_jobs.user_id == patientId).
    var selfQuery: Query = db.collection("processing_jobs")
        .whereField("user_id", isEqualTo: patientId.uuidString)
    if onlyCompleted {
        selfQuery = selfQuery.whereField("status", isEqualTo: "completed")
    }
    let selfSnapshot = try await selfQuery.getDocuments()
    let selfJobs = selfSnapshot.documents.compactMap { decodeJobRow(id: $0.documentID, data: $0.data()) }

    // 3. Attribution-linked jobs that aren't already in selfJobs. Firestore
    //    "in" queries cap at 30 values, so chunk defensively.
    let selfIds = Set(selfJobs.map(\.id))
    let extraIds = Array(attributedIds.subtracting(selfIds))

    var attributedJobs: [PatientJobRow] = []
    for chunk in chunked(extraIds, size: 30) {
        var attrQuery: Query = db.collection("processing_jobs")
            .whereField(FieldPath.documentID(), in: chunk.map { $0.uuidString })
        if onlyCompleted {
            attrQuery = attrQuery.whereField("status", isEqualTo: "completed")
        }
        let snapshot = try await attrQuery.getDocuments()
        attributedJobs.append(contentsOf: snapshot.documents.compactMap { decodeJobRow(id: $0.documentID, data: $0.data()) })
    }

    // 4. Merge + sort newest first.
    return (selfJobs + attributedJobs)
        .sorted { ($0.created_at ?? .distantPast) > ($1.created_at ?? .distantPast) }
}

private func chunked<T>(_ array: [T], size: Int) -> [[T]] {
    guard size > 0, !array.isEmpty else { return array.isEmpty ? [] : [array] }
    return stride(from: 0, to: array.count, by: size).map {
        Array(array[$0..<min($0 + size, array.count)])
    }
}

// MARK: - Self-view detection
//
// True when the signed-in user is looking at THEIR OWN PatientDetailView
// (via Profile → My care). Used to scope the "cloud uploads are off"
// empty-state hint to the patient themselves — clinicians always query
// cloud regardless of their own toggle.

@MainActor
private func isOwnDetail(_ patientId: UUID, authService: AuthenticationService) -> Bool {
    if case .signedIn(let profile) = authService.authState,
       let uuid = UUID(uuidString: profile.id) {
        return uuid == patientId
    }
    return false
}

// MARK: - Shared row + decode model

struct PatientJobRow: Identifiable, Hashable {
    let id: UUID
    let exercise_name: String?
    let status: String?
    let created_at: Date?
    let output_video_path: String?
    let output_csv_path: String?
    let input_video_path: String?
    let user_id: UUID?
}

/// Internal (not private) — reused by ExerciseHistoryPage's ProcessedVideosPage
/// so both views decode `processing_jobs` documents identically.
func decodeJobRow(id: String, data: [String: Any]) -> PatientJobRow? {
    guard let uuid = UUID(uuidString: id) else { return nil }
    let userId = (data["user_id"] as? String).flatMap(UUID.init(uuidString:))
    let createdAt = (data["created_at"] as? Timestamp)?.dateValue()
    return PatientJobRow(
        id: uuid,
        exercise_name: data["exercise_name"] as? String,
        status: data["status"] as? String,
        created_at: createdAt,
        output_video_path: data["output_video_path"] as? String,
        output_csv_path: data["output_csv_path"] as? String,
        input_video_path: data["input_video_path"] as? String,
        user_id: userId
    )
}

private struct PatientJobListRow: View {
    let job: PatientJobRow

    private var displayDate: String {
        guard let date = job.created_at else { return "Unknown date" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private var statusColor: Color {
        switch job.status ?? "" {
        case "completed": return .green
        case "failed":    return .red
        case "processing": return .orange
        default:           return .gray
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(job.exercise_name ?? "Unknown exercise")
                    .font(.body).fontWeight(.medium)
                Text(displayDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text((job.status ?? "queued").capitalized)
                .font(.caption2).fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor)
                .cornerRadius(6)
        }
        .padding(.vertical, 4)
    }
}
