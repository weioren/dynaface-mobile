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

// MARK: - [Phase 1] Exercise Modules
struct ExerciseModule: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let exercises: [Exercise]
}

let exerciseModules: [ExerciseModule] = [
    ExerciseModule(name: "Full Assessment", icon: "list.clipboard", exercises: allExercises),
    ExerciseModule(name: "Eye Movements", icon: "eye", exercises: allExercises.filter {
        ["Eyebrow Raise", "Brow Furrow", "Strong Eye Closure", "Weak Eye Closure"].contains($0.title)
    }),
    ExerciseModule(name: "Smile Movements", icon: "face.smiling", exercises: allExercises.filter {
        ["Full Smile", "Half Smile", "Lip Pucker", "Lip Purse"].contains($0.title)
    }),
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
                VStack(spacing: 16 * heightScale) {

                    // [Phase 1] SECTION 1: Quick-start module buttons
                    VStack(spacing: 8 * heightScale) {
                        Text("Quick Start")
                            .font(.headline)
                            .padding(.top, 20 * heightScale)

                        ForEach(exerciseModules) { module in
                            Button(action: {
                                selectedOrder = module.exercises
                                selectedIDs = Set(module.exercises.map { $0.id })
                                checkCameraPermissionAndNavigate()
                            }) {
                                HStack {
                                    Image(systemName: module.icon)
                                        .font(.system(size: 16 * widthScale))
                                    Text("\(module.name) (\(module.exercises.count))")
                                        .font(.system(size: 15 * widthScale, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(height: 42 * heightScale)
                                .frame(maxWidth: .infinity)
                                .background(Color(red: 0.12, green: 0.29, blue: 0.64))
                                .cornerRadius(49 * widthScale)
                            }
                        }
                    }
                    .padding(.horizontal, 20 * widthScale)

                    // [Phase 1] Divider
                    HStack {
                        Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
                        Text("or select exercises")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
                    }
                    .padding(.horizontal, 20 * widthScale)

                    // SECTION 2: Exercise grid for custom selection
                    let gridItems = [GridItem(.flexible()), GridItem(.flexible())]
                    LazyVGrid(columns: gridItems, spacing: 16) {
                        ForEach(allExercises) { exercise in
                            let isSelected = selectedIDs.contains(exercise.id)

                            Button {
                                if isSelected {
                                    selectedIDs.remove(exercise.id)
                                    if let idx = selectedOrder.firstIndex(where: { $0.id == exercise.id }) {
                                        selectedOrder.remove(at: idx)
                                    }
                                } else {
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

                    // SECTION 3: Practice Selected button
                    Button(action: {
                        checkCameraPermissionAndNavigate()
                    }) {
                        Text(selectedOrder.isEmpty ? "Practice Selected" : "Practice Selected (\(selectedOrder.count))")
                            .font(.system(size: 16 * widthScale, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(height: 42 * heightScale)
                            .frame(maxWidth: .infinity)
                            .background(selectedOrder.isEmpty ? Color.gray : Color(red: 0.12, green: 0.29, blue: 0.64))
                            .cornerRadius(49 * widthScale)
                    }
                    .padding(.horizontal, 20 * widthScale)
                    .disabled(selectedOrder.isEmpty)
                    .padding(.bottom, 20 * heightScale)
                }
                .frame(width: geometry.size.width, alignment: .center)

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
