import Foundation

// MARK: - Shared filename helpers for native recordings and imported uploads.
//
// Native recordings (CameraRecorderView) and imported uploads (UploadVideoPage)
// both store videos in Documents as "<ExerciseTitle>_<N>.mov". Keeping the
// numbering and save logic in one place guarantees both flows agree on the
// next available index, and that `ExerciseHistoryPage.exerciseName(from:)` can
// parse filenames produced by either pathway.

enum RecordingFilesError: Error {
    case documentsUnavailable
    case copyFailed(underlying: Error)
}

/// Scans `directory` for files matching `<exerciseName>_*.mov` and returns the
/// next integer suffix to use. Starts at 1.
func nextFileNumber(for exerciseName: String, in directory: URL) -> Int {
    do {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        let matching = files.filter {
            $0.pathExtension.lowercased() == "mov"
            && $0.lastPathComponent.hasPrefix("\(exerciseName)_")
        }
        let numbers: [Int] = matching.compactMap { url in
            let parts = url.lastPathComponent.split(separator: "_")
            guard let tail = parts.last?.split(separator: ".").first else { return nil }
            return Int(tail)
        }
        return (numbers.max() ?? 0) + 1
    } catch {
        return 1
    }
}

/// Copies a video at `sourceURL` into the app's Documents directory under
/// the canonical `<exerciseTitle>_<N>.mov` name. The source file extension is
/// discarded — we always save as .mov so the History filter picks it up. The
/// byte-level content is not transcoded.
///
/// Throws `RecordingFilesError` on failure. Returns the destination URL.
@discardableResult
func saveImportedVideo(from sourceURL: URL, exerciseTitle: String) throws -> URL {
    guard let documentsURL = FileManager.default.urls(
        for: .documentDirectory, in: .userDomainMask
    ).first else {
        throw RecordingFilesError.documentsUnavailable
    }

    let n = nextFileNumber(for: exerciseTitle, in: documentsURL)
    let destURL = documentsURL.appendingPathComponent("\(exerciseTitle)_\(n).mov")

    do {
        // Defensive: if a stale file already exists at this exact path (shouldn't
        // happen because nextFileNumber guards against collisions, but belt-and-
        // suspenders), remove it before copying.
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)
    } catch {
        throw RecordingFilesError.copyFailed(underlying: error)
    }

    return destURL
}
