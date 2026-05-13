import SwiftUI

// MARK: - AddEditEventSheet
//
// Shared form used for both "Add event" (any signed-in user, depending
// on RLS) and "Edit event" (clinicians only — the patient path never
// reaches this code path because TimelinePage gates the tap-to-edit
// gesture). Mode controls the title, the initial values, and whether
// Save calls insert or update.

struct AddEditEventSheet: View {
    enum Mode {
        case add
        case edit(TimelineEvent)
    }

    @EnvironmentObject var authService: AuthenticationService
    @EnvironmentObject var timelineService: TimelineService
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var type: TimelineEventType = .clinicVisit
    @State private var occurredAt: Date = Date()
    @State private var notes: String = ""
    @State private var isSaving = false

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .add:
            // Defaults are set above; nothing to copy in.
            break
        case .edit(let event):
            _type        = State(initialValue: event.type)
            _occurredAt  = State(initialValue: event.occurredAt)
            _notes       = State(initialValue: event.notes)
        }
    }

    private var title: String {
        switch mode {
        case .add:    return "New event"
        case .edit:   return "Edit event"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $type) {
                        ForEach(TimelineEventType.allCases) { t in
                            Label(t.displayName, systemImage: t.symbolName)
                                .tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Date") {
                    DatePicker(
                        "Occurred on",
                        selection: $occurredAt,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                }

                Section("Notes") {
                    TextField(
                        "Optional details (e.g. Botox 12 units to left orbicularis)",
                        text: $notes,
                        axis: .vertical
                    )
                    .lineLimit(3...8)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    // MARK: - Actions

    private func save() async {
        guard
            case .signedIn(let profile) = authService.authState,
            let creatorId = UUID(uuidString: profile.id)
        else { return }

        timelineService.errorMessage = nil
        isSaving = true

        switch mode {
        case .add:
            await timelineService.addEvent(
                type:       type,
                occurredAt: occurredAt,
                notes:      notes.trimmingCharacters(in: .whitespacesAndNewlines),
                createdBy:  creatorId
            )
        case .edit(let event):
            await timelineService.updateEvent(
                event,
                type:       type,
                occurredAt: occurredAt,
                notes:      notes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        isSaving = false
        if timelineService.errorMessage == nil {
            dismiss()
        }
        // On error, leave the sheet open so the user can retry; the
        // alert surfaces in the parent (TimelinePage / PatientDetailView).
    }
}
