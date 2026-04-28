import SwiftUI

// MARK: - PatientDetailPlaceholder
//
// Throwaway view, replaced by Alex's `PatientDetailView` in his follow-up
// PR. Lives at the destination of `PatientListPage`'s row tap (clinician
// flow) and `PatientRootView`'s "Patient detail" tab (patient flow).
//
// Alex's PR will likely:
//   - Rename this file to `PatientDetailView.swift` (or replace its content)
//   - Add a 4-tab sub-navigation (Timeline / Record / Past videos / Analysis)
//   - Wire Record/Past videos to scoped recording/history queries

struct PatientDetailPlaceholder: View {
    let patient: Patient

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.6))
            Text(patient.name)
                .font(.title2).fontWeight(.semibold)
            Text("Patient detail view coming soon")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Alex's follow-up PR will replace this with the Timeline, Record, Past videos, and Analysis sub-tabs.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(patient.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
