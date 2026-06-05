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
    // Tapping a movement opens a detail screen with Original / Processed tabs.
    @State private var selectedAssessmentVideo: AssessmentVideoRef?
    /// Timeline filter: nil = show all; otherwise only this event type.
    @State private var selectedFilter: TimelineEventType?

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
                VStack(spacing: 0) {
                    filterBar
                    if items.isEmpty {
                        filterEmptyState
                    } else {
                        list
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddEditEventSheet(mode: .add)
        }
        .sheet(item: $editingEvent) { event in
            AddEditEventSheet(mode: .edit(event))
        }
        .sheet(item: $selectedAssessmentVideo) { video in
            AssessmentVideoDetailView(
                jobId: video.id,
                title: video.title,
                dateText: video.dateText
            )
            .environmentObject(authService)
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
                        onPlay: { e in presentAssessmentVideo(e) }
                    )
                }
            }
        }
        .listStyle(.plain)
    }

    /// Eastern calendar so assessments group by the US Eastern day they were
    /// recorded — derived from createdAt (a real timestamp) rather than the
    /// UTC date the date-only occurred_at column would give. (A late-evening
    /// ET recording would otherwise land on the next UTC day.)
    private static let easternCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    /// Groups same-day assessment events into one "Clinical Assessment"
    /// stack; manual events (surgery / clinic visit / note) stay individual.
    /// Sorted by clinical date (occurred_at) descending.
    private var items: [TimelineItem] {
        var assessmentsByDay: [Date: [TimelineEvent]] = [:]
        var manuals: [TimelineEvent] = []
        let events = timelineService.events.filter {
            selectedFilter == nil || $0.type == selectedFilter
        }
        for event in events {
            if event.type == .assessment {
                let day = Self.easternCalendar.startOfDay(for: event.createdAt)
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

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Filter by:")
                .font(.caption)
                .foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([TimelineEventType.assessment, .surgery, .clinicVisit], id: \.self) { type in
                        let isSelected = selectedFilter == type
                        Button {
                            selectedFilter = isSelected ? nil : type
                        } label: {
                            Text(type.displayName)
                                .font(.subheadline)
                                .foregroundColor(isSelected ? .white : .primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isSelected ? Color(red: 0.12, green: 0.29, blue: 0.64) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var filterEmptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 44))
                .foregroundColor(.gray.opacity(0.5))
            Text("No \(selectedFilter?.displayName.lowercased() ?? "") events")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleTap(_ event: TimelineEvent) {
        if event.type == .assessment {
            presentAssessmentVideo(event)
            return
        }
        // Manual event types: clinician can edit, patient is read-only.
        guard isClinician else { return }
        editingEvent = event
    }

    /// Open the per-movement video detail screen (Original / Processed
    /// sub-tabs). The fetch + storage reads happen inside that view.
    private func presentAssessmentVideo(_ event: TimelineEvent) {
        guard let jobId = event.jobId else { return }
        selectedAssessmentVideo = AssessmentVideoRef(
            id: jobId,
            title: event.notes.isEmpty ? "Assessment" : event.notes,
            dateText: TimelineEventRow.displayDateFormatter.string(from: event.occurredAt)
        )
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

// MARK: - AssessmentVideoRef

private struct AssessmentVideoRef: Identifiable {
    let id: UUID          // jobId
    let title: String
    let dateText: String
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

// Each movement's "time recorded", fixed to US Eastern Time so every
// viewer (regardless of device timezone) sees the same value.
private let timelineTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "h:mm a 'ET'"
    f.timeZone = TimeZone(identifier: "America/New_York")
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
                                    Text(timelineTimeFormatter.string(from: e.createdAt))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
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
