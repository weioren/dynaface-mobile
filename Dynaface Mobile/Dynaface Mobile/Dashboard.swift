import SwiftUI

struct Dashboard: View {
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                ExercisesPage()
                    .tabItem {
                        Image(systemName: "dumbbell.fill")
                        Text("Exercise")
                    }
                    .tag(0)

                ExerciseHistoryPage()
                    .tabItem {
                        Image(systemName: "video.fill")
                        Text("History")
                    }
                    .tag(1)

                ProcessedVideosPage()
                    .tabItem {
                        Image(systemName: "sparkles.tv")
                        Text("Processed")
                    }
                    .tag(2)

                ProfilePage()
                    .tabItem {
                        Image(systemName: "person.fill")
                        Text("Profile")
                    }
                    .tag(3)
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .onAppear {
            // Check if we should navigate to a specific tab
            if let tabToSelect = UserDefaults.standard.object(forKey: "selectedTab") as? Int {
                selectedTab = tabToSelect
                UserDefaults.standard.removeObject(forKey: "selectedTab")
            }
        }
    }
}

// MARK: - Preview
#Preview {
    Dashboard()
}
