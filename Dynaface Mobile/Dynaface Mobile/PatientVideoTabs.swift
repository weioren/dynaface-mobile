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

    @State private var jobs: [PatientJobRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

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

    private var emptyState: some View {
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

    @MainActor
    private func reloadIfNeeded() async {
        if jobs.isEmpty { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
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
    var selfQuery = supabase
        .from("processing_jobs")
        .select("id, exercise_name, status, created_at, output_video_path, output_csv_path, user_id")
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
            .select("id, exercise_name, status, created_at, output_video_path, output_csv_path, user_id")
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
