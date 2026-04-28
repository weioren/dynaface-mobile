import SwiftUI

// MARK: - AddPatientSheet
//
// Sheet for adding a new patient. V1 captures only `name`. DOB / MRN are
// deferred until the HIPAA path is confirmed (Hopkins IT meeting outcome).
//
// On Save, calls PatientService.addPatient(...) with the current clinician's
// id. Dismisses on success.

struct AddPatientSheet: View {
    @EnvironmentObject var patientService: PatientService
    @EnvironmentObject var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var isSaving = false

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Patient name") {
                    TextField("e.g. Jane Doe", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(false)
                        .submitLabel(.done)
                        .onSubmit { if canSave { save() } }
                }

                Section {
                    Text("Additional patient details (date of birth, MRN, etiology) will be added once HIPAA-compliant storage is in place.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("New patient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    // MARK: - Save action

    private func save() {
        guard canSave else { return }
        guard
            case .signedIn(let profile) = authService.authState,
            let clinicianId = UUID(uuidString: profile.id)
        else { return }

        isSaving = true
        Task {
            await patientService.addPatient(name: trimmedName, clinicianId: clinicianId)
            await MainActor.run {
                isSaving = false
                // Only dismiss if no error; otherwise leave the sheet open
                // so the user can retry. The error itself surfaces via the
                // alert on PatientListPage.
                if patientService.errorMessage == nil {
                    dismiss()
                }
            }
        }
    }
}
