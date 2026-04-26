import SwiftUI
import AVKit
import Supabase

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

// MARK: - Processed Videos (Supabase results)
struct ProcessedVideosPage: View {
    private let resultsBucket = "results"

    @EnvironmentObject private var authService: AuthenticationService
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
                                .padding(.vertical, 4)
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
            let rows: [ProcessingJobRow] = try await authService.supabaseClient
                .from("processing_jobs")
                .select("*")
                .eq("status", value: "completed")
                .execute()
                .value

            jobs = rows.compactMap { row in
                let outputPath = row.output_video_path ?? row.output_csv_path
                guard let outputPath, !outputPath.isEmpty else {
                    return nil
                }
                let created = parseISODate(row.created_at) ?? .distantPast
                return ProcessedJob(
                    id: row.id,
                    exerciseName: row.exercise_name?.isEmpty == false ? row.exercise_name! : "Unknown Exercise",
                    outputPath: outputPath,
                    createdAt: created
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func openProcessedVideo(_ job: ProcessedJob) async {
        activeDownloadJobId = job.id
        defer { activeDownloadJobId = nil }

        do {
            let playbackURL = try await signedPlayableURL(for: job)
            selectedVideo = ProcessedVideoPlayback(
                id: job.id,
                playbackURL: playbackURL,
                exerciseTitle: job.exerciseName,
                recordingDate: job.displayDate
            )
        } catch is CancellationError {
            // Ignore task cancellation (e.g., user taps quickly while list refreshes).
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func signedPlayableURL(for job: ProcessedJob) async throws -> URL {
        let candidates = resultPathCandidates(from: job.outputPath)
        var lastError: Error?

        for path in candidates {
            do {
                let signedURL = try await authService.supabaseClient.storage
                    .from(resultsBucket)
                    .createSignedURL(path: path, expiresIn: 3600)
                return signedURL
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError ?? NSError(
            domain: "ProcessedVideos",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "Processed video object not found in storage."]
        )
    }

    private func normalizeResultObjectPath(_ path: String) -> String {
        let prefix = "\(resultsBucket)/"
        if path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return path
    }

    private func resultPathCandidates(from rawPath: String) -> [String] {
        let normalized = normalizeResultObjectPath(rawPath)
        var candidates: [String] = [normalized]

        if normalized.hasSuffix(".mov") {
            candidates.append(String(normalized.dropLast(4)) + ".mp4")
        } else if normalized.hasSuffix(".mp4") {
            candidates.append(String(normalized.dropLast(4)) + ".mov")
        } else if normalized.hasSuffix(".csv") {
            let base = String(normalized.dropLast(4))
            candidates.append(base + ".mp4")
            candidates.append(base + ".mov")
        }

        // Common worker output convention fallback: <user>/<job>/annotated.mp4
        let directory = (normalized as NSString).deletingLastPathComponent
        if !directory.isEmpty {
            candidates.append("\(directory)/annotated.mp4")
            candidates.append("\(directory)/annotated.mov")
        }

        // De-duplicate while preserving order
        var seen = Set<String>()
        var deduped: [String] = []
        for c in candidates where !c.isEmpty {
            if !seen.contains(c) {
                seen.insert(c)
                deduped.append(c)
            }
        }
        return deduped
    }

    private func parseISODate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let d = withFractional.date(from: raw) {
            return d
        }
        return ISO8601DateFormatter().date(from: raw)
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

private struct ProcessingJobRow: Decodable {
    let id: UUID
    let exercise_name: String?
    let output_video_path: String?
    let output_csv_path: String?
    let created_at: String?
    let status: String?
}

private struct ProcessedJob: Identifiable {
    let id: UUID
    let exerciseName: String
    let outputPath: String
    let createdAt: Date

    var fileName: String {
        URL(fileURLWithPath: outputPath).lastPathComponent
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
