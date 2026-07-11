import SwiftUI
import UIKit

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
    @State private var showingInvite = false

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
        .sheet(isPresented: $showingInvite) {
            InvitePatientSheet()
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
        HStack(spacing: 18) {
            Text("Patients")
                .font(.largeTitle).fontWeight(.bold)
            Spacer()
            Button { showingInvite = true } label: {
                Image(systemName: "person.badge.plus")
                    .font(.title2)
                    .foregroundColor(Color(red: 0.12, green: 0.29, blue: 0.64))
            }
            .accessibilityLabel("Invite patient")
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

// MARK: - InvitePatientSheet
//
// Clinician-facing. Generates a short, single-use invite code and lets the
// clinician copy / share it. The patient enters it under
// Profile -> My clinicians -> "Connect with a clinician", which links them to
// this clinician via the `redeem_invite` Cloud Function. No email infra.
struct InvitePatientSheet: View {
    @EnvironmentObject var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss

    @State private var patientNote = ""
    @State private var code: String?
    @State private var isWorking = false
    @State private var errorMessage: String?

    private let accent = Color(red: 0.12, green: 0.29, blue: 0.64)

    /// The signed-in clinician's app_uid + display name, or nil if somehow
    /// not signed in (button is disabled in that case).
    private var clinician: (id: String, name: String)? {
        if case .signedIn(let profile) = authService.authState {
            return (profile.id, profile.username)
        }
        return nil
    }

    private var shareMessage: String {
        let name = clinician?.name ?? "Your clinician"
        return "\(name) invited you to connect on Dynaface. Open the app and go to "
            + "Profile → My clinicians → Connect with a clinician, then enter code: \(code ?? "")"
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Share a code with your patient. When they enter it in the app, they'll be connected to you.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let code {
                        codeCard(code)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Patient name (optional)")
                                .font(.footnote).foregroundColor(.secondary)
                            TextField("For your reference", text: $patientNote)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundColor(.red)
                    }

                    Button {
                        Task { await generate() }
                    } label: {
                        HStack(spacing: 8) {
                            if isWorking { ProgressView().tint(.white) }
                            Text(code == nil ? "Generate code" : "Generate a new code")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(accent)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isWorking || clinician == nil)

                    Text("Codes expire in 14 days and can be used once.")
                        .font(.caption).foregroundColor(.secondary)

                    Spacer(minLength: 0)
                }
                .padding()
            }
            .navigationTitle("Invite patient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func codeCard(_ code: String) -> some View {
        VStack(spacing: 14) {
            Text(code)
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .kerning(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(.systemGray6))
                .cornerRadius(14)

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = code
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color(.systemGray5)).cornerRadius(10)
                }
                ShareLink(item: shareMessage) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color(.systemGray5)).cornerRadius(10)
                }
            }
            .foregroundColor(accent)
        }
    }

    private func generate() async {
        guard let clinician else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            code = try await InviteService.createInvite(
                clinicianId: clinician.id,
                clinicianName: clinician.name,
                patientName: patientNote
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
