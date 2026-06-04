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
            ForEach(items) { item in
                switch item {
                case .manual(let event):
                    TimelineEventRow(event: event)
                        .contentShape(Rectangle())
                        .onTapGesture { handleTap(event) }
                case .assessmentGroup(let day, let events):
                    TimelineAssessmentGroupRow(
                        day: day,
                        events: events,
                        loadingJobId: loadingAssessmentJobId,
                        onPlay: { e in Task { await openAssessmentVideo(e) } }
                    )
                }
            }
        }
        .listStyle(.plain)
    }

    /// GMT calendar so day-grouping matches the UTC-midnight dates the
    /// decoder produces (occurred_at is a date-only column).
    private static let gmtCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "GMT")!
        return c
    }()

    /// Groups same-day assessment events into one "Clinical Assessment"
    /// stack; manual events (surgery / clinic visit / note) stay individual.
    /// Sorted by clinical date (occurred_at) descending.
    private var items: [TimelineItem] {
        var assessmentsByDay: [Date: [TimelineEvent]] = [:]
        var manuals: [TimelineEvent] = []
        for event in timelineService.events {
            if event.type == .assessment {
                let day = Self.gmtCalendar.startOfDay(for: event.occurredAt)
                assessmentsByDay[day, default: []].append(event)
            } else {
                manuals.append(event)
            }
        }
        var result: [TimelineItem] = assessmentsByDay.map { day, evs in
            .assessmentGroup(day: day, events: evs.sorted { $0.createdAt > $1.createdAt })
        }
        result.append(contentsOf: manuals.map { TimelineItem.manual($0) })
        return result.sorted {
            $0.primaryDate != $1.primaryDate
                ? $0.primaryDate > $1.primaryDate
                : $0.secondaryDate > $1.secondaryDate
        }
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
            let url = try await signedAssessmentURL(for: jobId)
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
            assessmentPlaybackError = "Can't load video: \(error.localizedDescription)"
            print("[Timeline] playback failed for job \(jobId.uuidString): \(error)")
        }
    }

    /// Resolve a playback URL the same way the working Processed-tab
    /// playback does: look up the job's stored output path and try the
    /// candidate variants in `results`; fall back to the raw recording in
    /// `raw-videos` for jobs that haven't been processed yet.
    /// Reuse the Processed tab's playback verbatim: fetch the same
    /// PatientJobRow for this assessment's job, then call the shared
    /// `signedProcessedVideoURL`. (The timeline only has the jobId, so the
    /// one extra step is fetching that row.)
    private func signedAssessmentURL(for jobId: UUID) async throws -> URL {
        let job: PatientJobRow = try await authService.supabaseClient
            .from("processing_jobs")
            .select()
            .eq("id", value: jobId.uuidString)
            .single()
            .execute()
            .value
        return try await signedProcessedVideoURL(for: job, supabase: authService.supabaseClient)
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
                 ? "Add a surgery or clinic visit to start this patient's timeline."
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

// MARK: - TimelineItem (grouped list model)

private enum TimelineItem: Identifiable {
    case manual(TimelineEvent)
    case assessmentGroup(day: Date, events: [TimelineEvent])

    var id: String {
        switch self {
        case .manual(let e):             return "m-\(e.id.uuidString)"
        case .assessmentGroup(let d, _): return "a-\(Int(d.timeIntervalSince1970))"
        }
    }
    var primaryDate: Date {
        switch self {
        case .manual(let e):             return e.occurredAt
        case .assessmentGroup(let d, _): return d
        }
    }
    var secondaryDate: Date {
        switch self {
        case .manual(let e):              return e.createdAt
        case .assessmentGroup(_, let ev): return ev.map(\.createdAt).max() ?? Date(timeIntervalSince1970: 0)
        }
    }
}

// Shared GMT date formatter so labels match the UTC-midnight occurred_at.
private let timelineDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    f.timeZone = TimeZone(identifier: "GMT")
    return f
}()

// MARK: - TimelineAssessmentGroupRow
//
// Same-day assessment events folded into one "Clinical Assessment" card.
// Tap to expand a dropdown of the individual movements; tap a movement to
// replay its video (per-exercise jobId).

private struct TimelineAssessmentGroupRow: View {
    let day: Date
    let events: [TimelineEvent]
    let loadingJobId: UUID?
    let onPlay: (TimelineEvent) -> Void

    @State private var expanded = false
    private let accent = Color(red: 0.12, green: 0.29, blue: 0.64)

    /// If the day's movements exactly match a preset module, show its name
    /// (e.g. "Full Assessment"); otherwise "Clinical Assessment" and the
    /// dropdown lists every individual movement (no omission).
    private var title: String {
        let names = Set(events.map { $0.notes })
        for module in exerciseModules where Set(module.exercises.map { $0.title }) == names {
            return module.name
        }
        return "Clinical Assessment"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(timelineDateFormatter.string(from: day))
                    .font(.caption).fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .frame(width: 90, alignment: .trailing)

            ZStack(alignment: .top) {
                Rectangle().fill(Color.gray.opacity(0.25)).frame(width: 2)
                Circle().fill(accent).frame(width: 10, height: 10).offset(y: 6)
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "video.fill")
                            .font(.caption).foregroundColor(accent)
                        Text(title)
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(events.count) \(events.count == 1 ? "movement" : "movements")")
                            .font(.caption).foregroundColor(.secondary)
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(events) { e in
                            Button { onPlay(e) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.circle")
                                        .font(.body).foregroundColor(accent)
                                    Text(e.notes.isEmpty ? "Assessment" : e.notes)
                                        .font(.body).foregroundColor(.primary)
                                    Spacer()
                                    if loadingJobId == e.jobId {
                                        ProgressView()
                                    }
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            if e.id != events.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - TimelineEventRow

private struct TimelineEventRow: View {
    let event: TimelineEvent

    static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        f.timeZone = TimeZone(identifier: "GMT")
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Date column on the left so eyes can scan vertically by date.
            VStack(alignment: .trailing, spacing: 2) {
                Text(timelineDateFormatter.string(from: event.occurredAt))
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
