import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

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
    private let rawVideosBucketURL: String
    private let processingJobsCollection: String

    init(
        rawVideosBucketURL: String = FirebaseConfig.rawVideosBucketURL,
        processingJobsCollection: String = "processing_jobs"
    ) {
        self.rawVideosBucketURL = rawVideosBucketURL
        self.processingJobsCollection = processingJobsCollection
    }

    /// Uploads to `uploads/{userId}/{jobId}/video.{ext}` in the raw videos
    /// bucket (the "uploads/" prefix matters — that's what
    /// google_remote_dynaface_worker.py / firestore_function.py look for to
    /// recognize a freshly-uploaded recording), then writes the
    /// `processing_jobs/{jobId}` Firestore document that triggers processing.
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
        let inputVideoPath = "uploads/\(userId.uuidString)/\(jobId.uuidString)/video.\(fileExt)"

        let videoData = try Data(contentsOf: videoURL)
        print("[VideoUploadService] Video loaded: \(videoData.count) bytes")
        print("[VideoUploadService] Uploading to path: \(inputVideoPath)")

        let metadata = StorageMetadata()
        metadata.contentType = contentType(for: fileExt)

        let storage = Storage.storage(url: rawVideosBucketURL)
        do {
            _ = try await storage.reference(withPath: inputVideoPath).putDataAsync(videoData, metadata: metadata)
            print("[VideoUploadService] Storage upload SUCCESS")
        } catch {
            print("[VideoUploadService] Storage upload FAILED: \(error)")
            throw error
        }

        let now = FieldValue.serverTimestamp()
        let jobData: [String: Any] = [
            "id": jobId.uuidString,
            "user_id": userId.uuidString,
            "exercise_name": exerciseName,
            "input_video_path": inputVideoPath,
            "status": status,
            "created_at": now,
            "updated_at": now,
        ]

        print("[VideoUploadService] Creating job doc: id=\(jobId.uuidString), user_id=\(userId.uuidString), status=\(status)")

        do {
            try await Firestore.firestore()
                .collection(processingJobsCollection)
                .document(jobId.uuidString)
                .setData(jobData)
            print("[VideoUploadService] Firestore job doc SUCCESS")
        } catch {
            print("[VideoUploadService] Firestore job doc FAILED: \(error)")
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
        guard let user = Auth.auth().currentUser else {
            throw VideoUploadServiceError.notSignedIn
        }
        let tokenResult = try await user.getIDTokenResult()
        guard
            let appUidString = tokenResult.claims["app_uid"] as? String,
            let userId = UUID(uuidString: appUidString)
        else {
            throw VideoUploadServiceError.notSignedIn
        }

        print("[VideoUploadService] Current user app_uid: \(userId.uuidString)")

        do {
            let result = try await uploadVideoAndCreateJob(
                videoURL: videoURL,
                userId: userId,
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
