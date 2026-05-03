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
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Video file not found at path: \(url.path)"
        case .notSignedIn:
            return "No signed-in user session was found. Please sign in first."
        }
    }
}

struct VideoUploadService {
    private let supabase: SupabaseClient
    private let rawVideosBucket: String
    private let processingJobsTable: String

    init(
        supabase: SupabaseClient,
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
        let inputVideoPath = "\(userId.uuidString)/\(jobId.uuidString)/video.\(fileExt)"

        let videoData = try Data(contentsOf: videoURL)
        print("[VideoUploadService] Video loaded: \(videoData.count) bytes")
        print("[VideoUploadService] Uploading to path: \(inputVideoPath)")

        do {
            try await supabase.storage
                .from(rawVideosBucket)
                .upload(
                    path: inputVideoPath,
                    file: videoData,
                    options: FileOptions(contentType: contentType(for: fileExt))
                )
            print("[VideoUploadService] Storage upload SUCCESS")
        } catch {
            print("[VideoUploadService] Storage upload FAILED: \(error)")
            throw error
        }

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

        print("[VideoUploadService] Inserting job: id=\(jobId.uuidString), user_id=\(userId.uuidString), status=\(status)")

        do {
            try await supabase
                .from(processingJobsTable)
                .insert(row)
                .execute()
            print("[VideoUploadService] Database insert SUCCESS")
        } catch {
            print("[VideoUploadService] Database insert FAILED: \(error)")
            throw error
        }

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
        print("[VideoUploadService] Current user ID: \(session.user.id.uuidString)")
        print("[VideoUploadService] Auth token exists: \(!session.accessToken.isEmpty)")
        
        do {
            let result = try await uploadVideoAndCreateJob(
                videoURL: videoURL,
                userId: session.user.id,
                exerciseName: exerciseName,
                status: status
            )
            print("[VideoUploadService] SUCCESS: Job created with ID \(result.jobId.uuidString)")
            return result
        } catch {
            print("[VideoUploadService] UPLOAD FAILED: \(error.localizedDescription)")
            print("[VideoUploadService] Full error: \(error)")
            throw error
        }
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
