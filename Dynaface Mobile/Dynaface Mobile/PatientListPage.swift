import SwiftUI

// MARK: - PatientListPage
//
// Clinician's patient roster. Searchable list + an "Add patient" button.
// Tapping a row navigates to PatientDetailPlaceholder for now — Alex's
// follow-up PR replaces this with the real PatientDetailView (the 4 sub-tab
// container with Timeline / Record / Past videos / Analysis).

struct PatientListPage: View {
    @EnvironmentObject var patientService: PatientService
    @EnvironmentObject var authService: AuthenticationService

    @State private var searchText = ""
    @State private var showingAddSheet = false

    private var filtered: [Patient] {
        patientService.searchedPatients(matching: searchText)
    }

    var body: some View {
        NavigationStack {
            Group {
                if patientService.isLoading && patientService.patients.isEmpty {
                    ProgressView("Loading patients…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if patientService.patients.isEmpty {
                    emptyState
                } else if filtered.isEmpty {
                    noMatches
                } else {
                    list
                }
            }
            .navigationTitle("Patients")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search by name")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Add patient", systemImage: "plus.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddPatientSheet()
            }
            .refreshable { await reload() }
            .alert(
                "Couldn't load patients",
                isPresented: Binding(
                    get: { patientService.errorMessage != nil },
                    set: { if !$0 { patientService.errorMessage = nil } }
                ),
                presenting: patientService.errorMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { msg in
                Text(msg)
            }
        }
    }

    // MARK: - Subviews

    private var list: some View {
        List {
            ForEach(filtered) { patient in
                NavigationLink {
                    PatientDetailPlaceholder(patient: patient)
                } label: {
                    PatientRow(patient: patient)
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.3")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.6))
            Text("No patients yet")
                .font(.title3).fontWeight(.semibold)
            Text("Tap the + button in the top right to add your first patient.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showingAddSheet = true
            } label: {
                Label("Add patient", systemImage: "plus")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.12, green: 0.29, blue: 0.64))
            .padding(.top, 8)
            Spacer()
        }
    }

    private var noMatches: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.gray.opacity(0.5))
            Text("No patients match \"\(searchText)\"")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Actions

    private func reload() async {
        guard
            case .signedIn(let profile) = authService.authState,
            let clinicianId = UUID(uuidString: profile.id)
        else { return }
        await patientService.loadPatients(for: clinicianId)
    }
}

// MARK: - PatientRow
private struct PatientRow: View {
    let patient: Patient

    private var initials: String {
        let parts = patient.name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? "?"
        let last  = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.12, green: 0.29, blue: 0.64).opacity(0.18))
                    .frame(width: 44, height: 44)
                Text(initials)
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(patient.name)
                    .font(.body).fontWeight(.medium)
                    .foregroundColor(.primary)
                Text("Added \(patient.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
