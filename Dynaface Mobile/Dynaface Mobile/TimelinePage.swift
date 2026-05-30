import SwiftUI

// MARK: - TimelinePage
//
// Vertical list of clinical events for a single patient. Lives inside
// PatientDetailView. Both clinicians and the owning patient can add
// events (via the toolbar `+`); only clinicians can tap a row to edit
// it (RLS rejects patient updates).
//
// V1 stops at the linear list. Calendar / global facial-score
// graphing comes later when iPad / desktop is in scope.

struct TimelinePage: View {
    private let resultsBucket = "results"

    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var timelineService: TimelineService

    /// "Add event" trigger lives on PatientDetailView's toolbar so the
    /// navigation back button doesn't get clobbered by nested toolbars.
    /// PatientDetailView passes a binding so the toolbar button flips
    /// this flag and TimelinePage owns the actual sheet presentation.
    @Binding var showingAddSheet: Bool
    @State private var editingEvent: TimelineEvent?
    // Phase 9: assessment-event tap-to-play state.
    @State private var selectedAssessmentVideo: AssessmentVideoPlayback?
    @State private var loadingAssessmentJobId: UUID?
    @State private var assessmentPlaybackError: String?

    private var isClinician: Bool {
        if case .signedIn(let profile) = authService.authState {
            return profile.accountType == .clinician
        }
        return false
    }

    var body: some View {
        Group {
            if timelineService.isLoading && timelineService.events.isEmpty {
                ProgressView("Loading timeline…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if timelineService.events.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddEditEventSheet(mode: .add)
        }
        .sheet(item: $editingEvent) { event in
            AddEditEventSheet(mode: .edit(event))
        }
        .sheet(item: $selectedAssessmentVideo) { video in
            HistoryDetailView(
                videoURL: video.playbackURL,
                exerciseTitle: video.exerciseTitle,
                recordingDate: video.recordingDate
            )
        }
        .refreshable { await timelineService.loadEvents() }
        .task { await reloadIfNeeded() }
        .alert(
            "Couldn't load timeline",
            isPresented: Binding(
                get: { timelineService.errorMessage != nil },
                set: { if !$0 { timelineService.errorMessage = nil } }
            ),
            presenting: timelineService.errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
        .alert(
            "Can't play video",
            isPresented: Binding(
                get: { assessmentPlaybackError != nil },
                set: { if !$0 { assessmentPlaybackError = nil } }
            ),
            presenting: assessmentPlaybackError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
    }

    // MARK: - Subviews

    private var list: some View {
        List {
            ForEach(timelineService.events) { event in
                HStack(spacing: 0) {
                    TimelineEventRow(event: event)
                    if loadingAssessmentJobId == event.jobId, event.type == .assessment {
                        ProgressView()
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    handleTap(event)
                }
            }
        }
        .listStyle(.plain)
    }

    private func handleTap(_ event: TimelineEvent) {
        // Assessment rows always try to open the linked processed video,
        // regardless of role (RLS gates what the user can actually load).
        if event.type == .assessment {
            Task { await openAssessmentVideo(event) }
            return
        }
        // Manual event types: clinician can edit, patient is read-only.
        guard isClinician else { return }
        editingEvent = event
    }

    @MainActor
    private func openAssessmentVideo(_ event: TimelineEvent) async {
        guard let jobId = event.jobId else {
            assessmentPlaybackError = "This assessment isn't linked to a recording."
            return
        }
        loadingAssessmentJobId = jobId
        defer { loadingAssessmentJobId = nil }

        do {
            // `event.createdBy` is the uploader's profile.id by
            // construction (set at insert time in both flows), which
            // matches the storage path prefix the worker writes under.
            // Using auth.uid() here would break cross-user playback.
            let url = try await signedAssessmentURL(for: jobId, uploaderId: event.createdBy)
            let dateText = TimelineEventRow.displayDateFormatter.string(from: event.occurredAt)
            selectedAssessmentVideo = AssessmentVideoPlayback(
                id: jobId,
                playbackURL: url,
                exerciseTitle: event.notes.isEmpty ? "Assessment" : event.notes,
                recordingDate: dateText
            )
        } catch is CancellationError {
            return
        } catch {
            assessmentPlaybackError = "Video is still being processed or unavailable."
        }
    }

    /// Resolve a playback URL using the canonical worker convention:
    /// `{uploader_id}/{job_id}/annotated.{mp4|mov}` in the `results`
    /// bucket. `uploaderId` comes from `event.createdBy`, which is
    /// always the original uploader (either the patient who self-
    /// recorded or the clinician who recorded on the patient's behalf).
    private func signedAssessmentURL(for jobId: UUID, uploaderId: UUID) async throws -> URL {
        let candidates = [
            "\(uploaderId.uuidString)/\(jobId.uuidString)/annotated.mp4",
            "\(uploaderId.uuidString)/\(jobId.uuidString)/annotated.mov",
        ]
        var lastError: Error?
        for path in candidates {
            do {
                let signed = try await authService.supabaseClient.storage
                    .from(resultsBucket)
                    .createSignedURL(path: path, expiresIn: 3600)
                return signed
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError ?? NSError(domain: "TimelinePage", code: 404, userInfo: [NSLocalizedDescriptionKey: "Not found"])
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.6))
            Text("No events yet")
                .font(.title3).fontWeight(.semibold)
            Text(isClinician
                 ? "Add a surgery, injection, clinic visit, or note to start this patient's timeline."
                 : "Tap + to log a clinical event. Your clinician will see it on their side.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showingAddSheet = true
            } label: {
                Label("Add event", systemImage: "plus")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.12, green: 0.29, blue: 0.64))
            .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - Actions

    private func reloadIfNeeded() async {
        if timelineService.events.isEmpty {
            await timelineService.loadEvents()
        }
    }
}

// MARK: - AssessmentVideoPlayback

private struct AssessmentVideoPlayback: Identifiable {
    let id: UUID
    let playbackURL: URL
    let exerciseTitle: String
    let recordingDate: String
}

// MARK: - TimelineEventRow

private struct TimelineEventRow: View {
    let event: TimelineEvent

    static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Date column on the left so eyes can scan vertically by date.
            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.dateFormatter.string(from: event.occurredAt))
                    .font(.caption).fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .frame(width: 90, alignment: .trailing)

            // Vertical guideline + dot, the timeline rail.
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Color.gray.opacity(0.25))
                    .frame(width: 2)
                Circle()
                    .fill(Color(red: 0.12, green: 0.29, blue: 0.64))
                    .frame(width: 10, height: 10)
                    .offset(y: 6)
            }
            .frame(width: 12)

            // Event card.
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: event.type.symbolName)
                        .font(.caption)
                        .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64))
                    Text(event.type.displayName)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                if !event.notes.isEmpty {
                    Text(event.notes)
                        .font(.body)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
