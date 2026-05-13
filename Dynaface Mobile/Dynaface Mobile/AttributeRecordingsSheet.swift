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

    /// Called when the user finishes (either attributed or skipped).
    let onDone: () -> Void

    @EnvironmentObject private var authService: AuthenticationService
    @EnvironmentObject private var patientService: PatientService
    @EnvironmentObject private var attributionService: JobAttributionService

    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    private var filteredPatients: [PatientCandidate] {
        patientService.searchedPatientProfiles(matching: searchText)
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        finish()
                    }
                    .disabled(isSaving)
                }
            }
            .task {
                if patientService.patientProfiles.isEmpty {
                    await patientService.loadAllPatientProfiles()
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
            .interactiveDismissDisabled(isSaving)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 6) {
            Text("Who are these recordings for?")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("\(jobIds.count) recording\(jobIds.count == 1 ? "" : "s") will be attributed")
                .font(.caption)
                .foregroundColor(.secondary)
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
        if patientService.isLoading && patientService.patientProfiles.isEmpty {
            ProgressView("Loading patients…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredPatients.isEmpty {
            emptyState
        } else {
            List {
                ForEach(filteredPatients) { candidate in
                    Button {
                        Task { await attribute(to: candidate) }
                    } label: {
                        AttributePatientRow(candidate: candidate)
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

    private func attribute(to candidate: PatientCandidate) async {
        guard let clinicianId else {
            saveErrorMessage = "You must be signed in."
            return
        }
        isSaving = true
        defer { isSaving = false }

        for jobId in jobIds {
            let ok = await attributionService.attribute(
                jobId: jobId,
                patientId: candidate.id,
                attributedBy: clinicianId
            )
            if !ok {
                saveErrorMessage = attributionService.errorMessage
                    ?? "Couldn't attribute one or more recordings."
                return
            }
        }
        finish()
    }

    private func finish() {
        onDone()
        dismiss()
    }
}

// MARK: - AttributePatientRow

private struct AttributePatientRow: View {
    let candidate: PatientCandidate

    private var initials: String {
        let parts = candidate.username.split(separator: " ")
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
                Text(candidate.username)
                    .font(.body).fontWeight(.medium)
                    .foregroundColor(.primary)
                Text(candidate.email)
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
