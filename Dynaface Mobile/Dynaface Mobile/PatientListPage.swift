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

    @State private var searchText = ""

    private var filtered: [PatientCandidate] {
        patientService.searchedPatientProfiles(matching: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if patientService.isLoading && patientService.patientProfiles.isEmpty {
                    ProgressView("Loading patients…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if patientService.patientProfiles.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
        }
        .task { await reloadIfNeeded() }
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
    }

    private var list: some View {
        List {
            ForEach(filtered) { candidate in
                // Push PatientDetailView — V1 contains the Timeline section
                // only; future iterations attach Alex's annotated-video and
                // analysis sections alongside the existing init.
                NavigationLink {
                    PatientDetailView(patient: candidate)
                } label: {
                    PatientRow(candidate: candidate)
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
        if patientService.patientProfiles.isEmpty { await reload() }
    }

    private func reload() async {
        await patientService.loadAllPatientProfiles()
    }
}

// MARK: - PatientRow
private struct PatientRow: View {
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
                    .frame(width: 44, height: 44)
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
        }
        .padding(.vertical, 4)
    }
}
