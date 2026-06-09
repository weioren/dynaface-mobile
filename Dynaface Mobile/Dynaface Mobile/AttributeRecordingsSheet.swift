import SwiftUI

// MARK: - AttributeRecordingsSheet
//
// Shown after a successful "Upload All & Finish" run on PracticePage,
// only for clinician accounts. The clinician picks which patient the
// just-uploaded recordings belong to, or skips ("Save as unattributed")
// and the recordings stay associated only with the uploader (clinician)
// — the History/Processed tab on PatientDetailView will not list them.
//
// Patients self-recording don't see this sheet — their uploads already
// have `processing_jobs.user_id == patientId`, so the union query on
// PatientDetailView picks them up without an attribution row.

struct AttributeRecordingsSheet: View {

    /// All job IDs from the just-completed upload batch.
    let jobIds: [UUID]

    /// Exercise names matching `jobIds` (same order, same length). Used
    /// to populate the assessment timeline event's notes if the user
    /// opts into logging this upload on the timeline.
    let exerciseNames: [String]

    /// Called when the user finishes (either attributed or skipped).
    let onDone: () -> Void

    @EnvironmentObject private var authService: AuthenticationService
    @EnvironmentObject private var patientService: PatientService
    @EnvironmentObject private var attributionService: JobAttributionService

    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    /// Patient just attributed — used to drive the "Add to timeline?"
    /// confirmation alert before finishing.
    @State private var pendingTimelinePatient: PatientRef?

    private var filteredPatients: [PatientRef] {
        patientService.searchedRoster(matching: searchText)
    }

    private var clinicianId: UUID? {
        if case .signedIn(let profile) = authService.authState,
           let uuid = UUID(uuidString: profile.id) {
            return uuid
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                searchField
                Divider()
                listOrEmpty
            }
            .navigationTitle("Attribute Recordings")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if patientService.roster.isEmpty {
                    await patientService.loadAllPatientProfiles()
                    await patientService.loadAllPatients()
                }
            }
            .alert(
                "Couldn't attribute",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                ),
                presenting: saveErrorMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { msg in
                Text(msg)
            }
            // Attribution is mandatory — clinicians can't dismiss until
            // they pick a patient. The candidate list already shows every
            // patient profile in the system, so there's no in-sheet
            // "Add new patient" path; the user finds the patient via search.
            .interactiveDismissDisabled(true)
            // After successful attribution, ask the clinician whether to
            // also log this as an `assessment` timeline event.
            .alert(
                "Add to timeline?",
                isPresented: Binding(
                    get: { pendingTimelinePatient != nil },
                    set: { if !$0 { pendingTimelinePatient = nil } }
                ),
                presenting: pendingTimelinePatient
            ) { patient in
                Button("Add") {
                    Task { await addToTimeline(for: patient); finish() }
                }
                Button("Skip", role: .cancel) {
                    finish()
                }
            } message: { patient in
                Text("Log this assessment on \(patient.displayName)'s timeline?")
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 6) {
            Text("Who are these recordings for?")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(.primary)
            Text("\(jobIds.count) recording\(jobIds.count == 1 ? "" : "s") must be attributed to a patient before continuing")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search by name or email", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var listOrEmpty: some View {
        if patientService.isLoading && patientService.roster.isEmpty {
            ProgressView("Loading patients…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredPatients.isEmpty {
            emptyState
        } else {
            List {
                ForEach(filteredPatients) { ref in
                    Button {
                        Task { await attribute(to: ref) }
                    } label: {
                        AttributePatientRow(ref: ref)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                }
            }
            .listStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: searchText.isEmpty ? "person.3" : "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.gray.opacity(0.5))
            Text(searchText.isEmpty
                 ? "No patients available."
                 : "No patients match \"\(searchText)\"")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Actions

    private func attribute(to ref: PatientRef) async {
        guard let clinicianId else {
            saveErrorMessage = "You must be signed in."
            return
        }
        isSaving = true
        defer { isSaving = false }

        for jobId in jobIds {
            let ok = await attributionService.attribute(
                jobId: jobId,
                patientId: ref.id,
                attributedBy: clinicianId
            )
            if !ok {
                saveErrorMessage = attributionService.errorMessage
                    ?? "Couldn't attribute one or more recordings."
                return
            }
        }
        // Attribution succeeded — defer dismissal until the timeline
        // confirmation alert resolves.
        pendingTimelinePatient = ref
    }

    /// Insert an `assessment`-type event on the candidate patient's
    /// timeline. Called from the confirmation alert's "Add" button.
    private func addToTimeline(for ref: PatientRef) async {
        guard let clinicianId else { return }
        let service = TimelineService(patientId: ref.id)
        _ = await service.addAssessmentEvent(
            jobId: jobIds.first,
            occurredAt: Date(),
            exerciseNames: exerciseNames,
            createdBy: clinicianId
        )
    }

    private func finish() {
        onDone()
        dismiss()
    }
}

// MARK: - AttributePatientRow

private struct AttributePatientRow: View {
    let ref: PatientRef

    private var initials: String {
        let parts = ref.displayName.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? "?"
        let last  = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.12, green: 0.29, blue: 0.64).opacity(0.18))
                    .frame(width: 40, height: 40)
                Text(initials)
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(ref.displayName)
                    .font(.body).fontWeight(.medium)
                    .foregroundColor(.primary)
                Text(ref.email ?? "Not registered yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - RecordingPatientPickerSheet
//
// Pre-recording patient picker (clinician only). Choose an existing
// patient from the merged roster, or create a new unregistered patient,
// BEFORE recording. The chosen patient is returned via `onSelect`; the
// recordings are then auto-attributed to them on upload (no post-upload
// step). Presented as a `.sheet`, so its own NavigationStack is safe.

struct RecordingPatientPickerSheet: View {
    let onSelect: (PatientRef) -> Void

    @EnvironmentObject private var patientService: PatientService
    @EnvironmentObject private var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var showCreate = false
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var isCreating = false
    @FocusState private var searchFocused: Bool
    @FocusState private var nameFocused: Bool

    private var filtered: [PatientRef] {
        patientService.searchedRoster(matching: searchText)
    }

    private var clinicianId: UUID? {
        if case .signedIn(let profile) = authService.authState {
            return UUID(uuidString: profile.id)
        }
        return nil
    }

    private var canCreate: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if showCreate { createForm } else { picker }
            }
            .navigationTitle(showCreate ? "New patient" : "Select patient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if showCreate {
                        Button("Back") { showCreate = false }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { searchFocused = false; nameFocused = false }
                }
            }
            .task {
                if patientService.roster.isEmpty {
                    await patientService.loadAllPatientProfiles()
                    await patientService.loadAllPatients()
                }
            }
        }
        .interactiveDismissDisabled(isCreating)
    }

    private var picker: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            List {
                Button { showCreate = true } label: {
                    Label("Add new patient", systemImage: "plus.circle.fill")
                        .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64))
                }
                ForEach(filtered) { ref in
                    Button {
                        onSelect(ref)
                        dismiss()
                    } label: {
                        AttributePatientRow(ref: ref)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search by name or email", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var createForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add a patient who doesn't have an account yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("First name", text: $firstName)
                    .textContentType(.givenName)
                    .focused($nameFocused)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                TextField("Last name", text: $lastName)
                    .textContentType(.familyName)
                    .focused($nameFocused)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                Button {
                    Task { await create() }
                } label: {
                    HStack {
                        if isCreating { ProgressView().tint(.white) }
                        Text("Add & select")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canCreate ? Color(red: 0.12, green: 0.29, blue: 0.64) : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(!canCreate || isCreating)
            }
            .padding()
        }
    }

    private func create() async {
        guard let clinicianId else { return }
        let first = firstName.trimmingCharacters(in: .whitespaces)
        let last  = lastName.trimmingCharacters(in: .whitespaces)
        patientService.errorMessage = nil
        isCreating = true
        nameFocused = false
        let created = await patientService.addPatient(name: "\(first) \(last)", clinicianId: clinicianId)
        isCreating = false
        if let created {
            onSelect(PatientRef(patient: created))
            dismiss()
        }
    }
}
