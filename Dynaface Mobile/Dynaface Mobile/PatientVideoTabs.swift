import SwiftUI
import Supabase

// MARK: - PatientVideoTabs
//
// History + Processed sub-tab content for PatientDetailView. Both
// query the shared `processing_jobs` table filtered by user_id.
//
// V1 scope: shows only jobs where `processing_jobs.user_id` equals
// the patient's profile id — i.e. recordings the patient uploaded
// themselves. Clinician-uploaded recordings will surface here too
// once `feature/job_patient_attributions` lands and we union with
// the junction table. Until then, those clinician uploads stay
// attached to the clinician's own History tab on the Dashboard.

// MARK: - PatientHistoryTab
//
// Every processing_jobs row for this patient regardless of status.
// Renders a simple chronological list — date, exercise, status pill.

struct PatientHistoryTab: View {
    let patientId: UUID

    @EnvironmentObject private var authService: AuthenticationService

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
            Text("Recordings this patient uploads will appear here.")
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
            let rows: [PatientJobRow] = try await authService.supabaseClient
                .from("processing_jobs")
                .select("id, exercise_name, status, created_at, output_video_path, output_csv_path")
                .eq("user_id", value: patientId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
            self.jobs = rows
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
            let rows: [PatientJobRow] = try await authService.supabaseClient
                .from("processing_jobs")
                .select("id, exercise_name, status, created_at, output_video_path, output_csv_path")
                .eq("user_id", value: patientId.uuidString)
                .eq("status", value: "completed")
                .order("created_at", ascending: false)
                .execute()
                .value
            self.jobs = rows.filter {
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

// MARK: - Shared row + decode model

struct PatientJobRow: Identifiable, Decodable, Hashable {
    let id: UUID
    let exercise_name: String?
    let status: String?
    let created_at: String?
    let output_video_path: String?
    let output_csv_path: String?
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
