import SwiftUI
import AVKit
import FirebaseFirestore

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

        // Snapshot expansion-relevant state before we overwrite sections, so we can
        // detect newly appeared sections (e.g. a fresh "Today" after recording) and
        // auto-expand them without clobbering the user's collapse/expand choices.
        let previousDayIds = Set(dateSections.map { $0.id })
        let previousExerciseIds = Set(exerciseSections.map { $0.id })
        let isFirstLoad = previousDayIds.isEmpty && previousExerciseIds.isEmpty

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
            
            // Drop expansions for sections that no longer exist (e.g. after deletion).
            expandedDays = expandedDays.intersection(Set(newDateSections.map { $0.id }))
            expandedExercises = expandedExercises.intersection(Set(newExerciseSections.map { $0.id }))

            if isFirstLoad {
                // First-load: expand only the top section of the current sort mode.
                if sortMode == .byDate, let first = newDateSections.first?.id {
                    expandedDays = [first]
                }
                if sortMode == .byExercise, let first = newExerciseSections.first?.id {
                    expandedExercises = [first]
                }
            } else {
                // Subsequent reloads: auto-expand sections that didn't exist before
                // (new "Today" after recording, or an exercise just added). If a
                // section already existed and the user collapsed it, it stays collapsed.
                let newlyAddedDays = Set(newDateSections.map { $0.id }).subtracting(previousDayIds)
                let newlyAddedExercises = Set(newExerciseSections.map { $0.id }).subtracting(previousExerciseIds)
                expandedDays.formUnion(newlyAddedDays)
                expandedExercises.formUnion(newlyAddedExercises)
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

            PlainAVPlayerControllerView(url: videoURL)
                .background(Color.white)

            Spacer(minLength: 8)
        }
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.white.edgesIgnoringSafeArea(.all))
    }
}

// MARK: - Processed Videos (Firestore + Cloud Storage results)
struct ProcessedVideosPage: View {
    @State private var jobs: [ProcessedJob] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var activeDownloadJobId: UUID?
    @State private var selectedVideo: ProcessedVideoPlayback?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Processed Videos")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    Task { await loadProcessedJobs() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }

            if isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading processed videos...")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }

            if !isLoading && jobs.isEmpty {
                Text("No processed videos yet. Complete and upload an assessment to see videos here.")
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }

            List {
                ForEach(groupedByExercise, id: \.exerciseName) { section in
                    Section {
                        ForEach(section.jobs) { job in
                            Button {
                                Task { await openProcessedVideo(job) }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(job.displayDate)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        if activeDownloadJobId == job.id {
                                            ProgressView()
                                        }
                                    }
                                    Text(job.fileName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack {
                            Text(section.exerciseName)
                            Spacer()
                            Text("\(section.jobs.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable {
                await loadProcessedJobs()
            }
        }
        .padding()
        .task {
            await loadProcessedJobs()
        }
        .onReceive(NotificationCenter.default.publisher(for: .processedVideosUpdated)) { _ in
            Task { await loadProcessedJobs() }
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .sheet(item: $selectedVideo) { video in
            HistoryDetailView(
                videoURL: video.playbackURL,
                exerciseTitle: video.exerciseTitle,
                recordingDate: video.recordingDate
            )
        }
    }

    private var groupedByExercise: [ProcessedExerciseSection] {
        let grouped = Dictionary(grouping: jobs, by: \.exerciseName)
        return grouped.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { name in
                let sectionJobs = (grouped[name] ?? []).sorted { $0.createdAt > $1.createdAt }
                return ProcessedExerciseSection(exerciseName: name, jobs: sectionJobs)
            }
    }

    @MainActor
    private func loadProcessedJobs() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // No explicit user_id filter — same as the old Supabase query.
            // Visibility (patient sees own, clinician sees all) is enforced
            // by firestore.rules per-document, not by this query.
            let snapshot = try await Firestore.firestore()
                .collection("processing_jobs")
                .whereField("status", isEqualTo: "completed")
                .getDocuments()

            jobs = snapshot.documents.compactMap { doc -> ProcessedJob? in
                guard let row = decodeJobRow(id: doc.documentID, data: doc.data()) else { return nil }
                let outputPath = row.output_video_path ?? row.output_csv_path
                guard let outputPath, !outputPath.isEmpty else { return nil }
                return ProcessedJob(
                    row: row,
                    exerciseName: row.exercise_name?.isEmpty == false ? row.exercise_name! : "Unknown Exercise",
                    createdAt: row.created_at ?? .distantPast
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
        } catch is CancellationError {
            // SwiftUI task cancellation is expected during refresh/view transitions.
        } catch {
            if isCancellationLike(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func openProcessedVideo(_ job: ProcessedJob) async {
        activeDownloadJobId = job.id
        defer { activeDownloadJobId = nil }

        do {
            // Shared resolver (see PatientVideoTabs.swift) — same candidate-path
            // fallback logic used by the patient Processed tab.
            let playbackURL = try await signedProcessedVideoURL(for: job.row)
            selectedVideo = ProcessedVideoPlayback(
                id: job.id,
                playbackURL: playbackURL,
                exerciseTitle: job.exerciseName,
                recordingDate: job.displayDate
            )
        } catch is CancellationError {
            // Ignore task cancellation (e.g., user taps quickly while list refreshes).
        } catch {
            if isCancellationLike(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func isCancellationLike(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return true
        }

        let text = error.localizedDescription.lowercased()
        return text.contains("cancelled") || text.contains("canceled")
    }
}

private struct ProcessedExerciseSection {
    let exerciseName: String
    let jobs: [ProcessedJob]
}

private struct ProcessedVideoPlayback: Identifiable {
    let id: UUID
    let playbackURL: URL
    let exerciseTitle: String
    let recordingDate: String
}

private struct ProcessedJob: Identifiable {
    let row: PatientJobRow
    let exerciseName: String
    let createdAt: Date

    var id: UUID { row.id }

    var fileName: String {
        let path = row.output_video_path ?? row.output_csv_path ?? ""
        return URL(fileURLWithPath: path).lastPathComponent
    }

    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter.string(from: createdAt)
    }
}

// MARK: - Preview
#Preview {
    ExerciseHistoryPage()
}
