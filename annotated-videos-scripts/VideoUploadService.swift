import Foundation
import Supabase

struct QueuedProcessingJob {
    let jobId: UUID
    let userId: UUID
    let inputVideoPath: String
    let status: String
}

enum VideoUploadServiceError: LocalizedError {
    case fileNotFound(URL)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Video file not found at path: \(url.path)"
        }
    }
}

struct VideoUploadService {
    private let supabase: SupabaseClient
    private let rawVideosBucket: String
    private let processingJobsTable: String

    init(
        supabase: SupabaseClient = SupabaseClient(
            supabaseURL: URL(string: SupabaseConfig.projectURL)!,
            supabaseKey: SupabaseConfig.anonKey
        ),
        rawVideosBucket: String = "raw-videos",
        processingJobsTable: String = "processing_jobs"
    ) {
        self.supabase = supabase
        self.rawVideosBucket = rawVideosBucket
        self.processingJobsTable = processingJobsTable
    }

    func uploadVideoAndCreateJob(
        videoURL: URL,
        userId: UUID,
        exerciseName: String,
        status: String = "queued"
    ) async throws -> QueuedProcessingJob {
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw VideoUploadServiceError.fileNotFound(videoURL)
        }

        let jobId = UUID()
        let fileExt = videoURL.pathExtension.isEmpty ? "mov" : videoURL.pathExtension.lowercased()
        let inputVideoPath = "raw-videos/\(userId.uuidString)/\(jobId.uuidString)/video.\(fileExt)"

        let videoData = try Data(contentsOf: videoURL)

        try await supabase.storage
            .from(rawVideosBucket)
            .upload(
                path: inputVideoPath,
                file: videoData,
                options: FileOptions(contentType: contentType(for: fileExt))
            )

        struct ProcessingJobInsert: Encodable {
            let id: UUID
            let user_id: UUID
            let exercise_name: String
            let input_video_path: String
            let status: String
        }

        let row = ProcessingJobInsert(
            id: jobId,
            user_id: userId,
            exercise_name: exerciseName,
            input_video_path: inputVideoPath,
            status: status
        )

        try await supabase
            .from(processingJobsTable)
            .insert(row)
            .execute()

        return QueuedProcessingJob(
            jobId: jobId,
            userId: userId,
            inputVideoPath: inputVideoPath,
            status: status
        )
    }

    func uploadVideoAndCreateJobForCurrentUser(
        videoURL: URL,
        exerciseName: String,
        status: String = "queued"
    ) async throws -> QueuedProcessingJob {
        let session = try await supabase.auth.session
        return try await uploadVideoAndCreateJob(
            videoURL: videoURL,
            userId: session.user.id,
            exerciseName: exerciseName,
            status: status
        )
    }

    private func contentType(for fileExt: String) -> String {
        switch fileExt.lowercased() {
        case "mov": return "video/quicktime"
        case "mp4": return "video/mp4"
        case "avi": return "video/x-msvideo"
        default: return "application/octet-stream"
        }
    }
}
