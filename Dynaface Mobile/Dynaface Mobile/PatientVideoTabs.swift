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

    // Mirrors the "Upload videos to cloud" toggle in ProfilePage. When OFF,
    // patient self-view falls back to local FileManager recordings — the
    // cloud is intentionally empty in that case so we shouldn't render an
    // empty list when the user actually has recordings on the device.
    @AppStorage("videoUploadsEnabled") private var videoUploadsEnabled = true

    @State private var jobs: [PatientJobRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && jobs.isEmpty {
                ProgressView("Loading recordings…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if jobs.isEmpty {
                emptyState
            } else {
                List(jobs) { job in
                    PatientJobListRow(job: job)
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
    }

    private var emptyState: some View {
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

    @MainActor
    private func reloadIfNeeded() async {
        if jobs.isEmpty { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }

        // Toggle-driven data source. When patient views their own detail
        // and has cloud uploads disabled, show their device-local
        // recordings instead — otherwise My care would always look empty
        // for that patient.
        if isOwnDetail(patientId, authService: authService) && !videoUploadsEnabled {
            self.jobs = loadLocalRecordings()
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
            print("[PatientHistoryTab] ERROR loading recordings:")
            print("  type: \(type(of: error))")
            print("  description: \(error)")
            print("  localized: \(error.localizedDescription)")
            errorMessage = "Couldn't load recordings: \(error.localizedDescription)"
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

    @EnvironmentObject private var authService: AuthenticationService
    @EnvironmentObject private var attributionService: JobAttributionService

    @AppStorage("videoUploadsEnabled") private var videoUploadsEnabled = true

    @State private var jobs: [PatientJobRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

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
                    PatientJobListRow(job: job)
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
            print("[PatientProcessedTab] ERROR loading processed videos:")
            print("  type: \(type(of: error))")
            print("  description: \(error)")
            print("  localized: \(error.localizedDescription)")
            errorMessage = "Couldn't load processed videos: \(error.localizedDescription)"
        }
    }
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

    print("[fetchAllJobs] start patient=\(patientId.uuidString) onlyCompleted=\(onlyCompleted)")

    // 1. Pull the attribution job IDs first. If the network blip happens
    //    here we still return whatever the user-side query gives.
    let attributedIds = await attributionService.loadAttributedJobIds(forPatient: patientId)
    print("[fetchAllJobs] attributedIds count=\(attributedIds.count) ids=\(attributedIds.map { $0.uuidString })")

    // 2. Self-recorded jobs (processing_jobs.user_id == patientId).
    var selfQuery = supabase
        .from("processing_jobs")
        // Select all columns — the table may not have output_video_path /
        // output_csv_path (Alex's worker adds these later). PostgREST
        // errors on missing named columns, but "*" tolerates absence.
        .select()
        .eq("user_id", value: patientId.uuidString)
    if onlyCompleted {
        selfQuery = selfQuery.eq("status", value: "completed")
    }

    let selfJobs: [PatientJobRow]
    do {
        selfJobs = try await selfQuery
            .order("created_at", ascending: false)
            .execute()
            .value
        print("[fetchAllJobs] selfJobs count=\(selfJobs.count)")
    } catch {
        print("[fetchAllJobs] SELF QUERY FAILED type=\(type(of: error)) error=\(error)")
        throw error
    }

    // 3. Attribution-linked jobs that aren't already in selfJobs.
    let selfIds = Set(selfJobs.map(\.id))
    let extraIds = attributedIds.subtracting(selfIds)
    print("[fetchAllJobs] extraIds count=\(extraIds.count)")

    var attributedJobs: [PatientJobRow] = []
    if !extraIds.isEmpty {
        var attrQuery = supabase
            .from("processing_jobs")
            // Select all columns — the table may not have output_video_path /
        // output_csv_path (Alex's worker adds these later). PostgREST
        // errors on missing named columns, but "*" tolerates absence.
        .select()
            .in("id", values: extraIds.map { $0.uuidString })
        if onlyCompleted {
            attrQuery = attrQuery.eq("status", value: "completed")
        }
        do {
            attributedJobs = try await attrQuery
                .execute()
                .value
            print("[fetchAllJobs] attributedJobs count=\(attributedJobs.count)")
        } catch {
            print("[fetchAllJobs] ATTR QUERY FAILED type=\(type(of: error)) error=\(error)")
            throw error
        }
    }

    // 4. Merge + sort newest first by the raw created_at string. The
    //    server returns ISO 8601, which sorts lexicographically.
    return (selfJobs + attributedJobs)
        .sorted { ($0.created_at ?? "") > ($1.created_at ?? "") }
}

// MARK: - Self-view detection
//
// True when the signed-in user is looking at THEIR OWN PatientDetailView
// (via Profile → My care). Used to gate the local-FileManager fallback
// when cloud uploads are off — we don't want a clinician's local files
// surfacing when they're viewing a patient.

@MainActor
private func isOwnDetail(_ patientId: UUID, authService: AuthenticationService) -> Bool {
    if case .signedIn(let profile) = authService.authState,
       let uuid = UUID(uuidString: profile.id) {
        return uuid == patientId
    }
    return false
}

// MARK: - Local file fallback
//
// Scans the app's Documents directory for `.mov` recordings and maps each
// one to a synthetic `PatientJobRow`. Used by patient self-view when the
// "Upload videos to cloud" toggle is off — otherwise the History tab is
// always empty even though the device clearly holds recordings.
//
// The synthetic row carries:
//   - id: a deterministic UUID derived from the filename (so SwiftUI's
//         List preserves identity across reloads)
//   - status: "local" so the existing status pill differentiates from
//             queued/processing/completed cloud rows
//   - created_at: ISO 8601 of the file's creation date (lexicographic
//                 sort works the same as for cloud rows)

@MainActor
private func loadLocalRecordings() -> [PatientJobRow] {
    let docs: URL
    if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
        docs = url
    } else {
        return []
    }

    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    do {
        let files = try FileManager.default.contentsOfDirectory(
            at: docs,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let movs = files.filter { $0.pathExtension.lowercased() == "mov" }
        return movs.map { url in
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let date = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
            return PatientJobRow(
                id: stableUUID(from: url.lastPathComponent),
                exercise_name: exerciseNameFromMovURL(url),
                status: "local",
                created_at: isoFormatter.string(from: date),
                output_video_path: nil,
                output_csv_path: nil,
                user_id: nil
            )
        }
        .sorted { ($0.created_at ?? "") > ($1.created_at ?? "") }
    } catch {
        print("[loadLocalRecordings] FAILED type=\(type(of: error)) error=\(error)")
        return []
    }
}

/// Filename of the form "Cheek Puff_5.mov" → "Cheek Puff".
private func exerciseNameFromMovURL(_ url: URL) -> String {
    let filename = url.lastPathComponent
    let comps = filename.split(separator: "_")
    guard comps.count >= 2 else { return filename }
    return comps.dropLast().joined(separator: " ")
}

/// Maps a String → a deterministic UUID by padding/truncating UTF-8 bytes
/// to 16. Used so re-loading the same file yields the same id and SwiftUI
/// List doesn't blow away cells on every reload.
private func stableUUID(from string: String) -> UUID {
    let bytes = Array(string.utf8.prefix(16))
    var padded = bytes
    while padded.count < 16 { padded.append(0) }
    let t = (
        padded[0],  padded[1],  padded[2],  padded[3],
        padded[4],  padded[5],  padded[6],  padded[7],
        padded[8],  padded[9],  padded[10], padded[11],
        padded[12], padded[13], padded[14], padded[15]
    )
    return UUID(uuid: t)
}

// MARK: - Shared row + decode model

struct PatientJobRow: Identifiable, Decodable, Hashable {
    let id: UUID
    let exercise_name: String?
    let status: String?
    let created_at: String?
    let output_video_path: String?
    let output_csv_path: String?
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
