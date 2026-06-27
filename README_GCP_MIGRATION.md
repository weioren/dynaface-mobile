# Dynaface: GCP-only architecture (Firebase Auth + Firestore + Cloud Storage)

This replaces **all** Supabase usage (Auth, Postgres/RLS, Storage) with GCP/Firebase
equivalents. Supersedes `README_MIGRATE_SUPABASE_TO_GCP.md` (which proposed a
Cloud SQL + FastAPI design that was never built).

This doc was written by an AI assistant with no Xcode/Mac/GCP console access.
The Swift code compiles in my head, not in Xcode — **you will need to build,
fix any compile errors, and walk through the manual setup checklist below**
before any of this works end to end.

## Architecture

```
User records video
    -> VideoUploadService.swift uploads to gs://<raw bucket>/uploads/{uid}/{jobId}/video.ext
    -> VideoUploadService.swift writes processing_jobs/{jobId} Firestore doc (status: "queued")
    -> firestore_function.py (Eventarc trigger on processing_jobs/{jobId} create)
         - reads input_video_path + exercise_name off that doc
         - sets status: "processing"
         - calls the Cloud Run Jobs Admin API to run dynaface-worker with the real object path
    -> google_remote_dynaface_worker.py (Cloud Run Job)
         - downloads the video, runs Dynaface
         - extracts the "peak expression" frame for the given exercise
           (clinical_report_tool/extract_peak_expression_frame.py)
         - uploads annotated.mp4 + results.json + peak_frame.png to
           gs://<results bucket>/results/{uid}/{jobId}/
         - sets status: "completed" (or "failed" + error_message)
    -> App polls/reads processing_jobs/{jobId} and plays back via
       Storage downloadURL() once status == "completed"
```

Everything else (profiles, patients, job attributions, timeline events) moved
from Supabase Postgres/RLS tables to equivalent Firestore collections,
enforced by `firebase/firestore.rules` / `firebase/storage.rules` instead of
Postgres RLS policies.

## Why a custom `app_uid` claim instead of the raw Firebase UID

Every other screen in the app does `UUID(uuidString: profile.id)` (11 call
sites across 8 files) because the old Supabase `profiles.id` was a UUID.
Firebase Auth UIDs are **not** UUID-formatted, so using the raw Firebase UID
as `profile.id` would silently break all of them.

Instead: a new `create_profile` Cloud Function (Admin SDK) runs once at
signup, mints a real UUID (`app_uid`), writes `profiles/{app_uid}`, and sets
`app_uid` as a **custom claim** on the Firebase ID token. From then on:

- `profile.id` is always this UUID string — identical shape to the old
  Supabase id, so no other file needed to change.
- `firestore.rules` / `storage.rules` use `request.auth.token.app_uid` for
  every ownership check (never the raw Firebase UID).
- After `create_profile` returns, the client force-refreshes its ID token
  (`getIDToken(forcingRefresh: true)`) so the new claim is visible locally.

## Firestore schema

| Collection | Doc ID | Key fields |
|---|---|---|
| `profiles` | `app_uid` (UUID, from `create_profile`) | `email, username, username_lower, account_type, symptoms_location, symptoms_area, diagnosis, auth_uid, created_at` |
| `patients` | client-generated UUID | `name, clinician_id, claimed_user_id, archived_at, created_at, updated_at` |
| `processing_jobs` | client-generated UUID (the "job id") | `user_id, exercise_name, input_video_path, status, output_video_path, output_json_path, peak_frame_path, error_message, created_at, updated_at` |
| `job_patient_attributions` | == job id | `patient_id, attributed_by, attributed_at` |
| `timeline_events` | client-generated UUID | `patient_id, type, occurred_at, notes, created_by, created_at, updated_at, job_id` |

**Important:** document IDs for `patients` / `timeline_events` are
client-generated UUIDs (`UUID().uuidString`), not Firestore auto-IDs.
Firestore auto-IDs aren't UUID-formatted and would break every
`Patient.id` / `TimelineEvent.id` (`UUID`-typed) consumer the same way the
raw Firebase UID would have. See `PatientService.swift` / `TimelineService.swift`.

`processing_jobs.status` lifecycle: `queued` (client, on upload) ->
`processing` (firestore_function.py, before dispatch) -> `completed` or
`failed` (the worker, at the very end / on exception).

## Cloud Storage layout

Unchanged convention from before, now actually wired end-to-end:
- Raw: `gs://<raw bucket>/uploads/{user_id}/{jobId}/video.{ext}`
- Results: `gs://<results bucket>/results/{user_id}/{jobId}/{annotated.mp4, results.json, peak_frame.png}`

Writing the *real* `input_video_path` into the Firestore doc (instead of the
old hardcoded `uploads/unknown/{job_id}/video.mp4` guess) is what lets
`firestore_function.py` skip its bucket-scanning fallback.

## Peak-expression-frame extraction

`clinical_report_tool/extract_peak_expression_frame.py` maps each exercise
name to the per-frame metric that best represents its "maximum expression"
(e.g. `brow_elevation` max for Eyebrow Raise, `eye_aperture_l/r` min for the
eye-closure exercises, `dental_show_proxy` max for Full Smile — see
`EXERCISE_METRIC_MAP` in that file for the full table and the two cases that
use a proxy metric). The worker imports it directly (it's on the same
`sys.path` as `clinical_facial_report.py`), finds the peak frame against the
metrics it already computed in-memory, re-opens the already-downloaded local
video file to grab that exact frame, and uploads it as `peak_frame.png`
alongside `annotated.mp4` / `results.json`. It's also runnable standalone:

```
python clinical_report_tool/extract_peak_expression_frame.py \
    --video video.mov --exercise "Eyebrow Raise" --results results.json --output peak.png
```

If an exercise has no metric mapping, or the job document has no
`exercise_name`, extraction is skipped (logged, not fatal) — it's a nice-to-have
on top of the core metrics, not something that should fail a job.

## What changed, file by file

**Swift** (all in `Dynaface Mobile/Dynaface Mobile/`):
- `SupabaseConfig.swift` — no longer used; delete it (see checklist below).
- `FirebaseConfig.swift` — **new**. Bucket URLs + the `create_profile` function URL.
- `Authentication.swift` — Firebase Auth + manual Firestore profile read/write
  + `create_profile` call + token refresh.
- `VideoUploadService.swift` — Storage upload + `processing_jobs` doc write.
- `JobAttributionService.swift`, `PatientService.swift`, `TimelineService.swift`
  — Firestore equivalents of their old Supabase queries.
- `PatientVideoTabs.swift` — Firestore queries; `StorageReference.downloadURL()`
  replaces Supabase signed URLs (gated by `storage.rules` instead).
- `ExerciseHistoryPage.swift` — only the `ProcessedVideosPage` section changed,
  reusing `PatientJobRow` / `signedProcessedVideoURL` from `PatientVideoTabs.swift`.
- `PracticePage.swift`, `ProfilePage.swift` — one-line fixes (call site + copy).
- `DynafaceMobileApp.swift` — `FirebaseApp.configure()`.
- `Models.swift` — added a plain memberwise initializer to `TimelineEvent`
  (its hand-written `init(from decoder:)` for Supabase's date-only column
  suppressed Swift's auto-synthesized one; nothing else changed).

Every public method signature and model shape was kept identical on purpose,
so none of the ~20 other Swift files that consume these types/services
needed any changes.

**Python / backend:**
- `clinical_report_tool/extract_peak_expression_frame.py` — new, see above.
- `gcp-backend/create_profile/main.py` — new Cloud Function, see above.
- `firestore_function.py` — reads real `input_video_path`/`exercise_name`
  off the job doc, sets `status: "processing"` before dispatch and
  `status: "failed"` if dispatch fails.
- `google_remote_dynaface_worker.py` — Firestore client, reads `exercise_name`,
  runs peak-frame extraction, writes `status: "processing"` (defensive) /
  `"completed"` / `"failed"` at every exit path.

**New `dynaface-mobile/firebase/`:** `firestore.rules`, `storage.rules`,
`firebase.json`, `firestore.indexes.json` — translate the old Supabase RLS
migrations (`dynaface-mobile/supabase/migrations/`) into Firestore/Storage
security rules using `request.auth.token.app_uid`.

## Manual setup checklist (you'll need to do these — I can't from here)

1. **Xcode project file.** I didn't hand-edit `project.pbxproj` (too risky to
   do blind). You need to, in Xcode:
   - File > Add Package Dependencies > `https://github.com/firebase/firebase-ios-sdk`
     -> add **FirebaseAuth**, **FirebaseFirestore**, **FirebaseStorage**, **FirebaseCore**.
   - Remove the `supabase-swift` package dependency.
   - Add the new files to the target: `FirebaseConfig.swift`. (`Authentication.swift`,
     `VideoUploadService.swift`, etc. already existed in the project, so editing
     them in place didn't require this — only genuinely new files do.)
   - Delete `SupabaseConfig.swift` from the project.
2. **Firebase console** (same GCP project the worker already uses):
   - Enable Firebase on the project, register the iOS app (bundle ID), download
     `GoogleService-Info.plist` and drag it into the Xcode target.
   - Authentication > Sign-in method > enable Email/Password.
   - Firestore Database > create database (production mode).
   - Storage > add your two *existing* GCS buckets (the ones `RAW_BUCKET` /
     `RESULTS_BUCKET` already point to) as additional Storage buckets.
   - Fill in `FirebaseConfig.swift`'s `rawVideosBucketURL` / `resultsBucketURL`
     (format: `gs://bucket-name`) and `createProfileFunctionURL` (the deployed
     `create_profile` URL from step 4).
3. **Deploy security rules** from `dynaface-mobile/firebase/`:
   - Fill in the two real bucket names in `firebase.json`.
   - `firebase deploy --only firestore:rules,storage:rules` (run `firebase init`
     first if this is the first time using the Firebase CLI in this repo).
   - I could not test the `firestore.get(...)` cross-service call in
     `storage.rules` — double check that syntax against your Firestore
     database ID the first time you deploy.
4. **Deploy/redeploy the two Cloud Functions:**
   - `create_profile` (new) — see the deploy command in
     `gcp-backend/create_profile/main.py`'s docstring.
   - `firestore_function.py` (updated) — redeploy with the same command you
     used before. **Also confirm/update its Eventarc trigger's watched
     document path is `processing_jobs/{jobId}`** — if it was wired to watch
     a different/wildcard path before, update it.
   - Grant the worker's service account (the one `dynaface-worker` Cloud Run
     Job runs as) the `roles/datastore.user` IAM role — it now reads/writes
     Firestore, which it never did before.
5. **Build in Xcode** and fix whatever doesn't compile — report errors back
   and I'll fix them. Areas I'd double-check first: `Storage.storage(url:)`
   and `StorageReference.putDataAsync` / `.downloadURL()` async APIs (I used
   the SDK surface as I remember it, but didn't have a way to confirm exact
   signatures against the version Xcode resolves).
6. **End-to-end walkthrough:**
   - Sign up as both a patient and a clinician; confirm `profiles/{app_uid}`
     documents appear in the Firestore console with the right `account_type`.
   - Record/upload an exercise; watch `processing_jobs/{jobId}` go
     `queued -> processing -> completed` and confirm `peak_frame.png` lands
     in the results bucket next to `annotated.mp4` / `results.json`.
   - As a clinician, confirm you can see other patients' jobs/timeline/profile
     data; as a patient, confirm you can only see your own (this is what
     `firestore.rules` is enforcing — if something's visible that shouldn't
     be, or vice versa, that's the file to fix).
   - Password reset: Firebase's reset email uses the action URL configured
     in Firebase console > Authentication > Templates, not a per-call
     `redirectTo` like Supabase had — configure that template if you want
     the email to deep-link back into the app.

## Known gaps / unverified

- I have no Mac/Xcode, so **none of the Swift code has been compiled.**
- The exact Firebase iOS SDK async API surface (`putDataAsync`, `downloadURL()`
  as `async throws`) was written from memory of recent SDK versions — verify
  against whatever version Xcode actually resolves.
- Firestore composite-index requirements: a couple of queries combine an
  equality filter with `order(by:)` on a different field (e.g.
  `loadAllPatientProfiles`). This is normally covered by Firestore's
  automatic indexing, but if the console prompts you to create a composite
  index the first time you run the app, that's expected — follow the link it
  gives you.
- No end-to-end run yet: a real upload through the app (or a manual
  `gcloud run jobs execute dynaface-worker --args=<object-path>`) hasn't been
  exercised against the rebuilt worker image. Steps 1-4 below are done; this
  is the first thing to verify once Xcode is wired up.

## Backend deployment status (done as of 2026-06-18)

- `dynaface-worker` Cloud Run Job rebuilt and redeployed with the new
  Firestore-aware code + peak-frame extraction
  (`us-east4-docker.pkg.dev/dynaface-mobile-496023/dynaface/dynaface-worker:latest`).
  This required restoring `clinical_report_tool/clinical_facial_report.py`,
  `clinical_report_tool/dynaface_video_to_csv.py`, and
  `google-remote-scripts/requirements.txt` from the `backend-analysis`
  branch — they were missing on `gcp-branch` and the build would have failed
  without them. Also fixed `cloudbuild-worker.yaml`, which referenced a
  Dockerfile path that no longer exists and pushed to the wrong registry
  (`gcr.io/...` instead of the Artifact Registry path the Job actually
  pulls from).
- IAM: `dynaface-worker-sa@...` granted `roles/datastore.user`;
  `660576181256-compute@developer.gserviceaccount.com` (used by both
  `create-profile` and `firestore-function-revised`) granted
  `roles/firebaseauth.admin`. Both already had `roles/editor` at the project
  level, which covers Firestore read/write and triggering Cloud Run Job
  executions.
- `firestore.rules` / `storage.rules` deployed via `firebase deploy` — the
  `firestore.get(...)` cross-service syntax in `storage.rules` compiled and
  released successfully, so that's confirmed working, not just written.
- Cleaned up Eventarc trigger sprawl: 3 stale triggers with no document-path
  filter (firing on *every* Firestore document creation, not just
  `processing_jobs`) were deleted. Only `trigger-ix4ibbqr` →
  `firestore-function-revised`, scoped to `processing_jobs/{jobId}`, remains.
