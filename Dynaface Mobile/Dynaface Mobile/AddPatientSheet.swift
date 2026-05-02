import SwiftUI

// MARK: - AddPatientSheet
//
// Search-and-claim flow: clinician searches existing patient-role
// profiles by username/email, taps a result, and the app inserts a
// `patients` row linked to that profile via `claimed_user_id`.
// Already-claimed candidates show greyed out and aren't tappable.
// There is no free-text fallback — a profile must exist first.

struct AddPatientSheet: View {
    @EnvironmentObject var patientService: PatientService
    @EnvironmentObject var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var candidates: [PatientCandidate] = []
    @State private var isSearching = false
    @State private var addingId: UUID? = nil

    private var alreadyClaimedIds: Set<UUID> {
        Set(patientService.patients.compactMap { $0.claimedUserId })
    }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Add patient")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search by name or email"
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(addingId != nil)
                    }
                }
        }
        .interactiveDismissDisabled(addingId != nil)
        .task(id: searchText) { await searchAfterDebounce() }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var content: some View {
        if trimmedQuery.isEmpty {
            promptView
        } else if isSearching && candidates.isEmpty {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if candidates.isEmpty {
            noMatchesView
        } else {
            resultsList
        }
    }

    private var promptView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.gray.opacity(0.5))
            Text("Search for a patient by name or email.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var noMatchesView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 50))
                .foregroundColor(.gray.opacity(0.5))
            Text("No patients match \"\(trimmedQuery)\"")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var resultsList: some View {
        List {
            ForEach(candidates) { candidate in
                let alreadyAdded = alreadyClaimedIds.contains(candidate.id)
                CandidateRow(
                    candidate: candidate,
                    isAlreadyAdded: alreadyAdded,
                    isAdding: addingId == candidate.id
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !alreadyAdded, addingId == nil else { return }
                    Task { await add(candidate) }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Actions

    private func searchAfterDebounce() async {
        let q = trimmedQuery
        guard !q.isEmpty else {
            candidates = []
            isSearching = false
            return
        }
        do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        guard !Task.isCancelled else { return }
        isSearching = true
        let result = await patientService.searchPatientProfiles(matching: q)
        guard !Task.isCancelled else { return }
        candidates = result
        isSearching = false
    }

    private func add(_ candidate: PatientCandidate) async {
        guard
            case .signedIn(let profile) = authService.authState,
            let clinicianId = UUID(uuidString: profile.id)
        else { return }

        patientService.errorMessage = nil
        addingId = candidate.id
        await patientService.addPatientFromProfile(candidate, clinicianId: clinicianId)
        addingId = nil

        if patientService.errorMessage == nil {
            dismiss()
        }
    }
}

// MARK: - CandidateRow

private struct CandidateRow: View {
    let candidate: PatientCandidate
    let isAlreadyAdded: Bool
    let isAdding: Bool

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
                    .font(.caption2).fontWeight(.semibold)
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
            if isAdding {
                ProgressView()
            } else if isAlreadyAdded {
                Text("Already added")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity(isAlreadyAdded ? 0.5 : 1.0)
    }
}
