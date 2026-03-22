import SwiftUI
import AVKit

// MARK: - ExerciseHistoryPage (sortable/grouped; collapsible sections)
struct ExerciseHistoryPage: View {
    let baseWidth: CGFloat = 390
    let baseHeight: CGFloat = 844
    
    // Sort modes
    enum SortMode: String, CaseIterable, Identifiable {
        case byDate = "By Date"
        case byExercise = "By Exercise"
        var id: String { rawValue }
    }
    
    // Date sections
    struct DaySection: Identifiable, Hashable {
        let id: Date          // startOfDay date
        let date: Date        // startOfDay date
        var files: [URL]
    }
    // Exercise sections
    struct ExerciseSection: Identifiable, Hashable {
        let id: String        // exercise name
        let exerciseName: String
        var files: [URL]
    }
    
    // Data
    @State private var dateSections: [DaySection] = []
    @State private var exerciseSections: [ExerciseSection] = []
    @State private var sortMode: SortMode = .byDate
    
    // Expansion state per mode
    @State private var expandedDays: Set<Date> = []
    @State private var expandedExercises: Set<String> = []
    
    // Delete
    @State private var showingDeleteAlert = false
    @State private var fileToDelete: URL? = nil
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                let widthScale = geometry.size.width / baseWidth
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Exercise History")
                        .font(.system(size: 24 * widthScale))
                        .fontWeight(.bold)
                    
                    // Count across both groupings (they mirror the same file set)
                    let totalCount = (sortMode == .byDate
                                      ? dateSections.reduce(0) { $0 + $1.files.count }
                                      : exerciseSections.reduce(0) { $0 + $1.files.count })
                    Text("\(totalCount) workouts recorded")
                        .foregroundColor(.gray)
                    
                    // Sort Picker
                    Picker("Sort by", selection: $sortMode) {
                        ForEach(SortMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: sortMode) { _ in
                        // Expand the first section of the chosen mode if none expanded
                        switch sortMode {
                        case .byDate:
                            if expandedDays.isEmpty, let first = dateSections.first?.id {
                                expandedDays = [first]
                            }
                        case .byExercise:
                            if expandedExercises.isEmpty, let first = exerciseSections.first?.id {
                                expandedExercises = [first]
                            }
                        }
                    }
                    
                    // List of sections depending on mode
                    List {
                        if sortMode == .byDate {
                            ForEach(dateSections) { section in
                                Section {
                                    if expandedDays.contains(section.id) {
                                        ForEach(section.files, id: \.self) { file in
                                            let (exerciseName, dateString) = extractExerciseAndDate(from: file)
                                            NavigationLink(
                                                destination: HistoryDetailView(
                                                    videoURL: file,
                                                    exerciseTitle: exerciseName,
                                                    recordingDate: dateString
                                                )
                                            ) {
                                                VStack(alignment: .leading, spacing: 8) {
                                                    Text(exerciseName).font(.headline)
                                                    Text(dateString).font(.subheadline).foregroundColor(.gray)
                                                }
                                                .padding(.vertical, 4)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                Button(role: .destructive) {
                                                    fileToDelete = file
                                                    showingDeleteAlert = true
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }
                                        }
                                    }
                                } header: {
                                    Button { toggleDay(section.id) } label: {
                                        HStack {
                                            Image(systemName: expandedDays.contains(section.id) ? "chevron.down" : "chevron.right")
                                                .foregroundColor(.secondary)
                                            Text(sectionTitle(for: section.date))
                                                .font(.headline)
                                            Spacer()
                                            Text("\(section.files.count)").foregroundColor(.secondary)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else {
                            ForEach(exerciseSections) { section in
                                Section {
                                    if expandedExercises.contains(section.id) {
                                        ForEach(section.files, id: \.self) { file in
                                            let (exerciseName, dateString) = extractExerciseAndDate(from: file)
                                            NavigationLink(
                                                destination: HistoryDetailView(
                                                    videoURL: file,
                                                    exerciseTitle: exerciseName,
                                                    recordingDate: dateString
                                                )
                                            ) {
                                                VStack(alignment: .leading, spacing: 8) {
                                                    // Swap the emphasis: date is the "title", exercise is sub
                                                    Text(dateString).font(.headline)
                                                    Text(exerciseName).font(.subheadline).foregroundColor(.gray)
                                                }
                                                .padding(.vertical, 4)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                Button(role: .destructive) {
                                                    fileToDelete = file
                                                    showingDeleteAlert = true
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }
                                        }
                                    }
                                } header: {
                                    Button { toggleExercise(section.id) } label: {
                                        HStack {
                                            Image(systemName: expandedExercises.contains(section.id) ? "chevron.down" : "chevron.right")
                                                .foregroundColor(.secondary)
                                            Text(section.exerciseName)
                                                .font(.headline)
                                            Spacer()
                                            Text("\(section.files.count)").foregroundColor(.secondary)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    
                    Spacer()
                }
                .padding()
                .frame(width: geometry.size.width, alignment: .topLeading)
                .onAppear { reloadSections() }
            }
            .navigationBarHidden(true)
        }
        .alert("Delete Recording", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { fileToDelete = nil }
            Button("Delete", role: .destructive) {
                if let file = fileToDelete { deleteFile(file) }
                fileToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete this recording? This action cannot be undone.")
        }
        // Refresh after practice accept / foreground
        .onReceive(NotificationCenter.default.publisher(for: .recordingAccepted)) { _ in reloadSections() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in reloadSections() }
    }
}

// MARK: - Data loading / grouping
extension ExerciseHistoryPage {
    private func reloadSections() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        var fileDatePairs: [(url: URL, created: Date)] = []
        
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: documentsURL,
                includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            let movFiles = files.filter { $0.pathExtension.lowercased() == "mov" }
            
            for url in movFiles {
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let created = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
                fileDatePairs.append((url, created))
            }
            
            // Build date sections (newest day first, newest file first)
            let calendar = Calendar.current
            var groupedByDay: [Date: [URL]] = [:]
            for pair in fileDatePairs {
                let day = calendar.startOfDay(for: pair.created)
                groupedByDay[day, default: []].append(pair.url)
            }
            let sortedDays = groupedByDay.keys.sorted(by: >)
            let newDateSections: [DaySection] = sortedDays.map { day in
                let urls = (groupedByDay[day] ?? []).sorted { a, b in
                    let va = try? a.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                    let vb = try? b.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                    let ca = va?.creationDate ?? va?.contentModificationDate ?? .distantPast
                    let cb = vb?.creationDate ?? vb?.contentModificationDate ?? .distantPast
                    return ca > cb
                }
                return DaySection(id: day, date: day, files: urls)
            }
            dateSections = newDateSections
            
            // Build exercise sections (alphabetical by exercise name; files newest first)
            var groupedByExercise: [String: [URL]] = [:]
            for pair in fileDatePairs {
                let name = exerciseName(from: pair.url)
                groupedByExercise[name, default: []].append(pair.url)
            }
            let sortedNames = groupedByExercise.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            let newExerciseSections: [ExerciseSection] = sortedNames.map { name in
                let urls = (groupedByExercise[name] ?? []).sorted { a, b in
                    let va = try? a.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                    let vb = try? b.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                    let ca = va?.creationDate ?? va?.contentModificationDate ?? .distantPast
                    let cb = vb?.creationDate ?? vb?.contentModificationDate ?? .distantPast
                    return ca > cb
                }
                return ExerciseSection(id: name, exerciseName: name, files: urls)
            }
            exerciseSections = newExerciseSections
            
            // Maintain expansions; default-expand the first section of current mode if none
            expandedDays = expandedDays.intersection(Set(newDateSections.map { $0.id }))
            expandedExercises = expandedExercises.intersection(Set(newExerciseSections.map { $0.id }))
            if sortMode == .byDate, expandedDays.isEmpty, let first = newDateSections.first?.id {
                expandedDays = [first]
            }
            if sortMode == .byExercise, expandedExercises.isEmpty, let first = newExerciseSections.first?.id {
                expandedExercises = [first]
            }
        } catch {
            print("Error loading video files: \(error)")
            dateSections = []
            exerciseSections = []
        }
    }
    
    private func deleteFile(_ file: URL) {
        do {
            try FileManager.default.removeItem(at: file)
            reloadSections()
        } catch {
            print("Error deleting file: \(error)")
        }
    }
}

// MARK: - Helpers
extension ExerciseHistoryPage {
    private func toggleDay(_ day: Date) {
        if expandedDays.contains(day) { expandedDays.remove(day) } else { expandedDays.insert(day) }
    }
    private func toggleExercise(_ name: String) {
        if expandedExercises.contains(name) { expandedExercises.remove(name) } else { expandedExercises.insert(name) }
    }
    
    /// Human-friendly section title for date mode
    private func sectionTitle(for day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d, yyyy"
        return fmt.string(from: day)
    }
    
    /// Parse exercise name from filename (prefix before last "_<number>.mov")
    private func exerciseName(from url: URL) -> String {
        let filename = url.lastPathComponent
        let comps = filename.split(separator: "_")
        guard comps.count >= 2 else { return filename }
        let parts = comps.dropLast()
        return parts.joined(separator: " ")
    }
    
    /// Extract exercise name and formatted date from file attributes
    func extractExerciseAndDate(from url: URL) -> (exerciseName: String, dateString: String) {
        let name = exerciseName(from: url)
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let creationDate = attributes[.creationDate] as? Date
            let modificationDate = attributes[.modificationDate] as? Date
            let displayDate = creationDate ?? modificationDate ?? Date()
            let fmt = DateFormatter(); fmt.dateFormat = "MMM d, yyyy 'at' h:mm a"
            return (name, fmt.string(from: displayDate))
        } catch {
            print("Error getting file attributes: \(error)")
            return (name, "Unknown date")
        }
    }
}

// MARK: - Detail view (mirrored, adaptive, looping)
struct HistoryDetailView: View {
    let videoURL: URL
    let exerciseTitle: String
    let recordingDate: String

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(exerciseTitle).font(.title2).bold()
                Text(recordingDate).font(.subheadline).foregroundColor(.secondary)
            }
            .padding(.horizontal)

            AdaptiveMirroredPlayer(url: videoURL, heightFraction: 0.96)
                .background(Color.white)

            Spacer(minLength: 8)
        }
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.white.edgesIgnoringSafeArea(.all))
    }
}

// MARK: - Preview
#Preview {
    ExerciseHistoryPage()
}
