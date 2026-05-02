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
        // Dashboard 在外层 NavigationView 上设了 .navigationBarHidden(true),
        // iOS 16/17 上 push 进来的 destination 会继承隐藏状态,导致 back 按钮
        // 也消失。这里强制显示。
        .toolbar(.visible, for: .navigationBar)
    }
}
