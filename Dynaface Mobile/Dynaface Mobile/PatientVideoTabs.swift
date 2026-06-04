import SwiftUI
import Supabase

// MARK: - PatientVideoTabs
//
// History + Processed sub-tab content for PatientDetailView. Both
// tabs surface every recording associated with the patient via two
// independent sources, unioned client-side:
//
//   1. Self-recorded jobs — `processing_jobs.user_id = patient.id`
//      (the patient recorded on their own device).
//   2. Attribution-linked jobs — rows in `job_patient_attributions`
//      where `patient_id = patient.id` (typically a clinician
//      recorded for the patient and picked them in the post-upload
//      attribution sheet).
//
// We don't UNION server-side because the two queries have different
// shapes (one filters by user_id, the other looks up by job_id), and
// Supabase's PostgREST does not expose a single endpoint for that
// without a custom view. Two round-trips, merge in Swift.

// MARK: - PatientHistoryTab
//
// Every processing_jobs row for this patient regardless of status.
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
                supabase: authService.supabaseClient,
                attributionService: attributionService,
                onlyCompleted: false
            )
            self.jobs = merged
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
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
            let url = try await signedRawVideoURL(for: job, supabase: authService.supabaseClient)
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
        guard let raw = job.created_at,
              let parsed = ISO8601DateFormatter.flexible.date(from: raw) else {
            return "Unknown date"
        }
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return f.string(from: parsed)
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
// Only completed jobs — i.e. processing_jobs rows with status =
// 'completed' AND an output_video_path. Used by clinicians (and
// the patient themselves) to find the annotated result video.

struct PatientProcessedTab: View {
    let patientId: UUID
    private let resultsBucket = "results"

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
                supabase: authService.supabaseClient,
                attributionService: attributionService,
                onlyCompleted: true
            )
            self.jobs = merged.filter {
                let out = $0.output_video_path ?? $0.output_csv_path
                return !(out?.isEmpty ?? true)
            }
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
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
            let playbackURL = try await signedPlayableURL(for: job)
            selectedVideo = PatientProcessedPlayback(
                id: job.id,
                playbackURL: playbackURL,
                exerciseTitle: job.exercise_name?.isEmpty == false ? job.exercise_name! : "Unknown Exercise",
                recordingDate: displayDate(for: job)
            )
        } catch is CancellationError {
            return
        } catch {
            if isCancellationLike(error) { return }
            errorMessage = error.localizedDescription
        }
    }

    private func signedPlayableURL(for job: PatientJobRow) async throws -> URL {
        try await signedProcessedVideoURL(for: job, supabase: authService.supabaseClient)
    }

    private func isCancellationLike(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return true
        }
        let text = error.localizedDescription.lowercased()
        return text.contains("cancelled") || text.contains("canceled")
    }

    private func displayDate(for job: PatientJobRow) -> String {
        guard let raw = job.created_at,
              let parsed = ISO8601DateFormatter.flexible.date(from: raw) else {
            return "Unknown date"
        }
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return f.string(from: parsed)
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
// candidate object paths in the `results` bucket. Used by BOTH the
// Processed tab and TimelinePage so playback resolves identically.

func processedVideoPathCandidates(
    outputVideoPath: String?,
    outputCsvPath: String?,
    userId: UUID?,
    jobId: UUID,
    resultsBucket: String = "results"
) -> [String] {
    func normalize(_ path: String) -> String {
        let prefix = "\(resultsBucket)/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    let normalized = normalize(outputVideoPath ?? outputCsvPath ?? "")
    var candidates: [String] = [normalized]

    if normalized.hasSuffix(".mov") {
        candidates.append(String(normalized.dropLast(4)) + ".mp4")
    } else if normalized.hasSuffix(".mp4") {
        candidates.append(String(normalized.dropLast(4)) + ".mov")
    } else if normalized.hasSuffix(".csv") {
        let base = String(normalized.dropLast(4))
        candidates.append(base + ".mp4")
        candidates.append(base + ".mov")
    }

    let directory = (normalized as NSString).deletingLastPathComponent
    if !directory.isEmpty {
        candidates.append("\(directory)/annotated.mp4")
        candidates.append("\(directory)/annotated.mov")
    }

    if let userId {
        candidates.append("\(userId.uuidString)/\(jobId.uuidString)/annotated.mp4")
        candidates.append("\(userId.uuidString)/\(jobId.uuidString)/annotated.mov")
    }

    var seen = Set<String>()
    var deduped: [String] = []
    for c in candidates where !c.isEmpty {
        if !seen.contains(c) {
            seen.insert(c)
            deduped.append(c)
        }
    }
    return deduped
}

/// The one and only "play this job's processed video" resolver. Called by
/// both the Processed tab and the timeline so playback is identical.
func signedProcessedVideoURL(
    for job: PatientJobRow,
    supabase: SupabaseClient,
    resultsBucket: String = "results"
) async throws -> URL {
    let candidates = processedVideoPathCandidates(
        outputVideoPath: job.output_video_path,
        outputCsvPath: job.output_csv_path,
        userId: job.user_id,
        jobId: job.id
    )
    var lastError: Error?
    for path in candidates {
        do {
            return try await supabase.storage
                .from(resultsBucket)
                .createSignedURL(path: path, expiresIn: 3600)
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

/// "Original" (raw) recording URL: `{user_id}/{job_id}/video.{mov|mp4}` in
/// the raw-videos bucket. Used by the patient Videos "Original" segment.
func signedRawVideoURL(
    for job: PatientJobRow,
    supabase: SupabaseClient,
    rawVideosBucket: String = "raw-videos"
) async throws -> URL {
    var candidates: [String] = []
    // Prefer the exact stored upload path (mirrors how Analyzed uses
    // output_video_path), then fall back to the canonical convention.
    if let input = job.input_video_path, !input.isEmpty {
        let prefix = "\(rawVideosBucket)/"
        candidates.append(input.hasPrefix(prefix) ? String(input.dropFirst(prefix.count)) : input)
    }
    if let userId = job.user_id {
        candidates.append("\(userId.uuidString)/\(job.id.uuidString)/video.mov")
        candidates.append("\(userId.uuidString)/\(job.id.uuidString)/video.mp4")
    }
    var seen = Set<String>()
    var deduped: [String] = []
    for c in candidates where !c.isEmpty {
        if seen.insert(c).inserted { deduped.append(c) }
    }

    var lastError: Error?
    for path in deduped {
        do {
            let url = try await supabase.storage
                .from(rawVideosBucket)
                .createSignedURL(path: path, expiresIn: 3600)
            print("[Original] signed raw URL OK: \(rawVideosBucket)/\(path)")
            return url
        } catch {
            print("[Original] signed raw URL FAILED: \(rawVideosBucket)/\(path): \(error)")
            lastError = error
            continue
        }
    }
    throw lastError ?? NSError(domain: "PatientOriginal", code: 404,
                              userInfo: [NSLocalizedDescriptionKey: "Original recording not found in storage."])
}

// MARK: - Shared fetch helper
//
// Two round-trips against `processing_jobs`:
//   1. user_id = patient.id  (self-recorded)
//   2. id IN (attribution job_ids)  (clinician-recorded, attributed)
// Then merge + dedupe + sort newest first.

@MainActor
private func fetchAllJobs(
    forPatient patientId: UUID,
    supabase: SupabaseClient,
    attributionService: JobAttributionService,
    onlyCompleted: Bool
) async throws -> [PatientJobRow] {

    // 1. Pull the attribution job IDs first. If the network blip happens
    //    here we still return whatever the user-side query gives.
    let attributedIds = await attributionService.loadAttributedJobIds(forPatient: patientId)

    // 2. Self-recorded jobs (processing_jobs.user_id == patientId).
    //    Select all columns — the table may not have output_video_path /
    //    output_csv_path (Alex's worker adds these later). PostgREST
    //    errors on missing named columns, but "*" tolerates absence.
    var selfQuery = supabase
        .from("processing_jobs")
        .select()
        .eq("user_id", value: patientId.uuidString)
    if onlyCompleted {
        selfQuery = selfQuery.eq("status", value: "completed")
    }
    let selfJobs: [PatientJobRow] = try await selfQuery
        .order("created_at", ascending: false)
        .execute()
        .value

    // 3. Attribution-linked jobs that aren't already in selfJobs.
    let selfIds = Set(selfJobs.map(\.id))
    let extraIds = attributedIds.subtracting(selfIds)

    var attributedJobs: [PatientJobRow] = []
    if !extraIds.isEmpty {
        var attrQuery = supabase
            .from("processing_jobs")
            .select()
            .in("id", values: extraIds.map { $0.uuidString })
        if onlyCompleted {
            attrQuery = attrQuery.eq("status", value: "completed")
        }
        attributedJobs = try await attrQuery
            .execute()
            .value
    }

    // 4. Merge + sort newest first by the raw created_at string. The
    //    server returns ISO 8601, which sorts lexicographically.
    return (selfJobs + attributedJobs)
        .sorted { ($0.created_at ?? "") > ($1.created_at ?? "") }
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

struct PatientJobRow: Identifiable, Decodable, Hashable {
    let id: UUID
    let exercise_name: String?
    let status: String?
    let created_at: String?
    let output_video_path: String?
    let output_csv_path: String?
    let input_video_path: String?
    let user_id: UUID?
}

private struct PatientJobListRow: View {
    let job: PatientJobRow

    private var displayDate: String {
        guard let raw = job.created_at,
              let parsed = ISO8601DateFormatter.flexible.date(from: raw) else {
            return "Unknown date"
        }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: parsed)
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

// MARK: - ISO8601 helper

private extension ISO8601DateFormatter {
    static let flexible: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
