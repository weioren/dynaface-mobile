import SwiftUI
import AVFoundation

// MARK: - Minimal model + sample data
struct Exercise: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let instructions: String
    let videoFileName: String?   // base name, e.g. "EyebrowRaise"
}

let allExercises: [Exercise] = [
    Exercise(title: "Eyebrow Raise",
             instructions: "Lift eyebrows as if surprised.",
             videoFileName: "EyebrowRaise"),
    
    Exercise(title: "Brow Furrow",
             instructions: "Pull eyebrows together forming a forehead wrinkle.",
             videoFileName: "BrowFurrow"),
    
    Exercise(title: "Strong Eye Closure",
             instructions: "Squeeze eyelids shut with full lid contact.",
             videoFileName: "StrongEyeClosure"),
    
    Exercise(title: "Weak Eye Closure",
             instructions: "Close eyes gently with full lid contact.",
             videoFileName: "WeakEyeClosure"),
    
    Exercise(title: "Nose Wrinkle",
             instructions: "Scrunch nose to form a snarl.",
             videoFileName: "NoseWrinkle"),
    
    Exercise(title: "Cheek Puff",
             instructions: "Blow air against closed lips to puff cheeks.",
             videoFileName: "Blowfish"),
    
    Exercise(title: "Full Smile",
             instructions: "Smile with teeth showing.",
             videoFileName: "FullSmile"),
    
    Exercise(title: "Half Smile",
             instructions: "Smile without teeth showing.",
             videoFileName: "HalfSmile"),
    
    Exercise(title: "Lip Pucker",
             instructions: "Pucker lips as if blowing a kiss.",
             videoFileName: "LipPucker"),
    
    Exercise(title: "Lip Purse",
             instructions: "Fold lips inward and hold.",
             videoFileName: "LipPurse")
]

// MARK: - ExercisesPage
struct ExercisesPage: View {
    let baseWidth: CGFloat = 390
    let baseHeight: CGFloat = 844

    @State private var selectedOrder: [Exercise] = []
    @State private var selectedIDs: Set<UUID> = []
    @State private var navigateToPractice = false
    @State private var showPermissionAlert = false

    var body: some View {
        GeometryReader { geometry in
            let widthScale = geometry.size.width / baseWidth
            let heightScale = geometry.size.height / baseHeight

            ScrollView {
                VStack(spacing: 30 * heightScale) {
                    // Title
                    Text("Select your exercises for today:")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    // Grid
                    let gridItems = [GridItem(.flexible()), GridItem(.flexible())]
                    LazyVGrid(columns: gridItems, spacing: 20) {
                        ForEach(allExercises) { exercise in
                            let isSelected = selectedIDs.contains(exercise.id)
                            
                            Button {
                                if isSelected {
                                    // remove from set + ordered list
                                    selectedIDs.remove(exercise.id)
                                    if let idx = selectedOrder.firstIndex(where: { $0.id == exercise.id }) {
                                        selectedOrder.remove(at: idx)
                                    }
                                } else {
                                    // add to set + append to ordered list
                                    selectedIDs.insert(exercise.id)
                                    selectedOrder.append(exercise)
                                }
                            } label: {
                                ExerciseSquare(
                                    title: exercise.title,
                                    widthScale: widthScale,
                                    heightScale: heightScale,
                                    isSelected: isSelected
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(exercise.title)
                            .accessibilityValue(isSelected ? "Selected" : "Not selected")
                        }
                    }
                    .padding(.horizontal, 20 * widthScale)
                    
                    Spacer()
                }
                .padding(.top, 40 * heightScale)
                .frame(width: geometry.size.width, alignment: .center)
                
                // PRACTICE button → Check camera permission first, then navigate to PracticePage
                Button(action: {
                    checkCameraPermissionAndNavigate()
                }) {
                    Text(selectedOrder.isEmpty ? "Practice" : "Practice (\(selectedOrder.count))")
                        .font(.system(size: 18 * widthScale))
                        .foregroundColor(.white)
                        .frame(height: 44 * heightScale)
                        .frame(maxWidth: .infinity)
                        .background(selectedOrder.isEmpty ? Color.gray : Color(red: 0.12, green: 0.29, blue: 0.64))
                        .cornerRadius(49 * widthScale)
                        .shadow(color: Color.black.opacity(0.25),
                                radius: 4 * widthScale,
                                x: 0, y: 4 * heightScale)
                }
                .padding(.horizontal, 20 * widthScale)
                .disabled(selectedOrder.isEmpty)

                // Hidden NavigationLink controlled by state
                NavigationLink(
                    destination: PracticePage(exercises: selectedOrder),
                    isActive: $navigateToPractice
                ) {
                    EmptyView()
                }
                .hidden()

                // Alert for when camera permission is denied
                .alert("Camera Access Required", isPresented: $showPermissionAlert) {
                    Button("Settings") {
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsURL)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Please enable camera access in Settings to record exercises.")
                }
            }
        }
    }

    // MARK: - Camera Permission Check
    private func checkCameraPermissionAndNavigate() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // Permission already granted, navigate immediately
            navigateToPractice = true
        case .notDetermined:
            // Request permission
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        navigateToPractice = true
                    } else {
                        showPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            // Permission denied, show alert
            showPermissionAlert = true
        @unknown default:
            showPermissionAlert = true
        }
    }
}

// MARK: - Selectable square
struct ExerciseSquare: View {
    let title: String
    let widthScale: CGFloat
    let heightScale: CGFloat
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10 * widthScale)
                .fill(Color.gray.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 10 * widthScale)
                        .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3),
                                lineWidth: isSelected ? 3 : 1)
                )
                .frame(height: 96 * heightScale)

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 16 * widthScale, weight: .semibold))
                    .foregroundColor(.black)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .imageScale(.large)
                        .foregroundColor(.blue)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Preview
// #Preview {
//    NavigationStack { ExercisesPage() }
//}
