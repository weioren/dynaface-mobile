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
    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var timelineService: TimelineService

    /// "Add event" trigger lives on PatientDetailView's toolbar so the
    /// navigation back button doesn't get clobbered by nested toolbars.
    /// PatientDetailView passes a binding so the toolbar button flips
    /// this flag and TimelinePage owns the actual sheet presentation.
    @Binding var showingAddSheet: Bool
    @State private var editingEvent: TimelineEvent?

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
            ForEach(timelineService.events) { event in
                TimelineEventRow(event: event)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Only clinicians can edit (RLS would reject otherwise);
                        // tapping as patient is a no-op so the row doesn't feel
                        // broken when nothing happens.
                        guard isClinician else { return }
                        editingEvent = event
                    }
            }
        }
        .listStyle(.plain)
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

// MARK: - TimelineEventRow

private struct TimelineEventRow: View {
    let event: TimelineEvent

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
