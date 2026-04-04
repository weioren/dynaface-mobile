This document covers the pipeline used to process a video remotely from an uploaded recorded video as well as next steps.

# Pipeline
1. User records video and presses "Accept"
2. Call ```VideoUploadService.swfit```
2. ```VideoUploadService.swfit``` references local video URL to upload the video to Supabase Storage at ```raw-videos/{user_id}/{job_id}/video.mov```
3. ```VideoUploadService.swfit``` then inserts a row into ```processing_jobs``` table in Supabase with status "queued".
4. ```dynaface_worker.py``` will continuously run on some machine and detect new inserted rows
5. Whenever a new row is detected, the status is updated to "processing" and the video file is downloaded to the machine
6. ```dynaface_extract.py``` is run on the video file and CSV results are stored on the machine
7. CSV results are uploaded to ```results/{user_id}/{job_id}/results.csv```
8. Status is updated to "completed". 
9. ```dynaface_worker.py``` continues scanning for new job requests.

# Tests Completed So Far
- ```dynaface_worker.py``` works and the upload and porcessing table scheme works perfectly. This was tested using ```smoke_test_pipeline.py``` which uploads a local MOV file and inserts a new row in ```processing_jobs```.


# Next Steps
1. Call ```VideoUploadService.swfit``` after the user presses Accept
```
Task {
        do {
            let uploadService = VideoUploadService()

            // If user is already signed in and service can read current user
            let job = try await uploadService.uploadVideoAndCreateJobForCurrentUser(
                videoURL: acceptedVideoURL,
                exerciseName: "FullSmile" // replace with selected exercise
            )

            print("Queued job: \(job.jobId)")
            print("Input path: \(job.inputVideoPath)")
        } catch {
            print("Failed to upload/queue video: \(error)")
        }
    }
```
2. Ensure you add, SUPABASE_URL, SUPABASE_ANON_KEY, and SUPABASE_SERVICE_ROLE_KEY as environment variables on server machine running the worker file
3. Run worker file