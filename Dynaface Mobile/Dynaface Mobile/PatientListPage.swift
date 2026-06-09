import SwiftUI

// MARK: - PatientListPage
//
// The clinician's patient roster. Lives as a top-level Dashboard tab
// for accounts with `accountType == .clinician`. Lists every
// self-registered patient account (profiles where account_type='patient'),
// newest first. Searchable by username OR email.
//
// Note: this view does NOT wrap itself in a NavigationStack — the
// outer Dashboard already provides a NavigationView, and nesting them
// causes the same tab-freeze bug fixed in Phase 3 for ExerciseHistoryPage.

struct PatientListPage: View {
    @EnvironmentObject var patientService: PatientService
    @EnvironmentObject var authService: AuthenticationService
    // Held only so we can forward it into PatientDetailView's pushed
    // destination — NavigationLink targets don't inherit env objects
    // that were attached at TabView scope.
    @EnvironmentObject var attributionService: JobAttributionService

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var showingAddPatient = false

    private var filtered: [PatientRef] {
        patientService.searchedRoster(matching: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            Group {
                if patientService.isLoading && patientService.roster.isEmpty {
                    ProgressView("Loading patients…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if patientService.roster.isEmpty {
                    emptyState
                } else if filtered.isEmpty {
                    noMatches
                } else {
                    list
                }
            }
        }
        .task { await reloadIfNeeded() }
        .sheet(isPresented: $showingAddPatient) {
            AddPatientSheet()
                .environmentObject(patientService)
                .environmentObject(authService)
        }
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

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Text("Patients")
                .font(.largeTitle).fontWeight(.bold)
            Spacer()
            Button { showingAddPatient = true } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64))
            }
            .accessibilityLabel("Add patient")
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search by name or email", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onSubmit { isSearchFocused = false }
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
        .padding(.vertical, 8)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isSearchFocused = false }
            }
        }
    }

    private var list: some View {
        List {
            ForEach(filtered) { ref in
                // Registered (profiles.id) and unregistered (patients.id)
                // both push via displayName/patientId. Unregistered rows
                // are clinician-visible only (no patient account yet).
                NavigationLink {
                    PatientDetailView(displayName: ref.displayName, patientId: ref.id)
                        .environmentObject(authService)
                        .environmentObject(patientService)
                        .environmentObject(attributionService)
                } label: {
                    PatientRow(ref: ref)
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await reload() }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.3")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.6))
            Text("No patients yet")
                .font(.title3).fontWeight(.semibold)
            // Empty-state copy locked to English (per product). "Pull to refresh"
            // is literal — `list` already wires `.refreshable { await reload() }`.
            Text("Patients appear here after they sign up. Pull to refresh.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
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

    private func reloadIfNeeded() async {
        if patientService.roster.isEmpty { await reload() }
    }

    private func reload() async {
        // Sequential (not concurrent) so the two loads don't race on the
        // shared `isLoading` flag and flash the empty state.
        await patientService.loadAllPatientProfiles()
        await patientService.loadAllPatients()
    }
}

// MARK: - PatientRow
private struct PatientRow: View {
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
                    .frame(width: 44, height: 44)
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
        }
        .padding(.vertical, 4)
    }
}
