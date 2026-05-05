import SwiftUI

// MARK: - PatientDetailPlaceholder
//
// Temporary destination when a clinician taps a patient row in the
// patient list. Just a "Coming soon" page until Alex builds the real
// `PatientDetailView` (the 4 sub-tab container with Timeline / Record /
// Past videos / Analysis scoped per patient).
//
// Recording / history / upload still live on the existing top-level
// Dashboard tabs as before — they're not duplicated here.

struct PatientDetailPlaceholder: View {
    let displayName: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.6))
            Text(displayName)
                .font(.title2).fontWeight(.semibold)
            Text("Patient detail view coming soon")
                .font(.subheadline).foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        // Dashboard sets .navigationBarHidden(true) on the outer NavigationView.
        // On iOS 16/17 a pushed destination inherits the hidden state and the
        // back chevron disappears with it. Force the bar visible here.
        .toolbar(.visible, for: .navigationBar)
    }
}
