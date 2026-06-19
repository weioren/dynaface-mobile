import SwiftUI

// MARK: - AddPatientSheet
//
// Clinician "My Patients" → add a new patient. Per the 6/14 meeting the
// search-and-claim flow was removed from this sheet (search now lives only
// on the pre-recording patient picker, RecordingPatientPickerSheet). This
// sheet simply creates a new clinician-owned patient row.

struct AddPatientSheet: View {
    @EnvironmentObject var patientService: PatientService
    @EnvironmentObject var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var isCreating = false
    @FocusState private var nameFieldFocused: Bool

    private var canCreate: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("New patient")
                        .font(.headline)
                    Text("Add a patient to your roster.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("First name", text: $firstName)
                        .textContentType(.givenName)
                        .focused($nameFieldFocused)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    TextField("Last name", text: $lastName)
                        .textContentType(.familyName)
                        .focused($nameFieldFocused)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)

                    Button {
                        Task { await createUnregistered() }
                    } label: {
                        HStack {
                            if isCreating { ProgressView().tint(.white) }
                            Text("Add patient")
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
            .navigationTitle("Add patient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCreating)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { nameFieldFocused = false }
                }
            }
            .interactiveDismissDisabled(isCreating)
        }
    }

    // MARK: - Actions

    private func createUnregistered() async {
        guard
            case .signedIn(let profile) = authService.authState,
            let clinicianId = UUID(uuidString: profile.id)
        else { return }

        let first = firstName.trimmingCharacters(in: .whitespaces)
        let last  = lastName.trimmingCharacters(in: .whitespaces)
        patientService.errorMessage = nil
        isCreating = true
        nameFieldFocused = false
        await patientService.addPatient(name: "\(first) \(last)", clinicianId: clinicianId)
        isCreating = false

        if patientService.errorMessage == nil {
            dismiss()
        }
    }
}
