# How Dynaface Mobile actually works (GCP/Firebase architecture, end to end)

This is a from-scratch explanation of the deployed system as it exists right now —
every GCP resource, what it does, why it exists, and how a request flows through
all of them. It assumes no prior context. For the history of *why* this replaced
Supabase, see `README_GCP_MIGRATION.md`; this doc is "what's true today," not "what changed."

GCP project: **`dynaface-mobile-496023`** (project number `660576181256`), region **`us-east4`**.

---

## 1. The mental model in one paragraph

The iOS app talks directly to three Firebase/GCP client SDKs (Auth, Firestore,
Storage) — there is no traditional "backend API server" the app calls for normal
CRUD. The only custom backend code is two small pieces of glue: **`create_profile`**
(an HTTPS Cloud Function the app calls exactly once, right after signup, to mint
the app's notion of "user id") and **`firestore_function.py`** (a Firestore-triggered
function that notices a new video-processing job and kicks off a Cloud Run Job to
actually do the face-analysis work). Firestore Security Rules and Storage Security
Rules — not a server — are what enforce "patients can only see their own data,
clinicians can see everyone's."

---

## 2. GCP resource inventory

| Resource | Name | Purpose |
|---|---|---|
| Firebase Auth / Identity Platform | (project-level) | Email/password signup & login. Issues JWT ID tokens; supports custom claims (used for `app_uid`, see §4). |
| Firestore database | `(default)`, Native mode, `us-east4` | 5 collections: `profiles`, `patients`, `processing_jobs`, `job_patient_attributions`, `timeline_events`. |
| Cloud Storage bucket | `dynaface-mobile-496023-dynaface-raw` | Raw uploaded videos: `uploads/{userId}/{jobId}/video.{ext}` |
| Cloud Storage bucket | `dynaface-mobile-496023-dynaface-results` | Worker output: `results/{userId}/{jobId}/{annotated.mp4, results.json, peak_frame.png}` |
| Cloud Storage bucket | `dynaface-mobile-496023.firebasestorage.app` | Firebase's auto-created default bucket. Not used by this pipeline (the two buckets above predate Firebase being enabled on the project). |
| Cloud Run **Job** | `dynaface-worker` | Runs `google_remote_dynaface_worker.py` — downloads a video, runs the Dynaface ML pipeline, uploads results. One-shot per invocation, not a server. |
| Cloud Run **Service** | `firestore-function-revised` | Runs `firestore_function.py`. Triggered by Eventarc when a `processing_jobs` document is created; dispatches a `dynaface-worker` execution. |
| Cloud Run **Service** / Cloud Function (2nd gen) | `create-profile` / `create_profile` | Runs `gcp-backend/create_profile/main.py`. HTTPS-triggered, called once by the app per signup. |
| Eventarc trigger | `trigger-ix4ibbqr` | Watches Firestore for document-creation events matching path pattern `processing_jobs/{jobId}`; routes them to `firestore-function-revised`. |
| Artifact Registry repo | `dynaface` (in `us-east4-docker.pkg.dev`) | Holds the `dynaface-worker` Docker image. |

**Leftover/orphaned, safe to ignore (or delete later):**
- `firestore-function` (Cloud Run service, deployed 2026-06-09) — an earlier version of the trigger function. No Eventarc trigger points at it anymore; superseded by `firestore-function-revised`.
- `firestore-dynaface-bridge`, `test-fxn` — Cloud Run services that used to be targets of broad, unfiltered Eventarc triggers (fired on *every* Firestore write, not just `processing_jobs`). Those triggers were deleted; these services are now unreachable and cost nothing (Cloud Run scales to zero).

---

## 3. Identity & Auth — `create_profile`, tokens, and custom claims (the important part)

### The problem this solves

Firebase Auth UIDs are short opaque strings, **not** UUID-formatted (e.g. `aB3xY...`,
not `550e8400-e29b-...`). But the rest of the iOS app — `Patient.clinicianId`,
`TimelineEvent.createdBy`, and about a dozen other call sites across 8 files — does
`UUID(uuidString: profile.id)`, because the app's data model was originally built
against a Postgres `uuid` column. If `profile.id` were the raw Firebase UID, every
one of those calls would return `nil` and silently break.

### The fix: a second, app-level identity (`app_uid`)

Instead of using the Firebase UID as the user's identity throughout the app, a
**separate real UUID called `app_uid`** is minted once per user, at signup, and
used as the `profiles` document ID and as "the user id" everywhere else in the
app. The Firebase UID still exists (Firebase needs it internally for the Auth
user record) but the rest of the system never sees it directly — it only sees
`app_uid`.

### The exact flow

1. **App calls `Auth.auth().createUser(withEmail:password:)`.** Firebase creates
   an Auth user and hands back a Firebase UID + an ID token (JWT) for that user.
   At this point there is no Firestore profile yet, and the ID token has no
   `app_uid` claim.

2. **App calls `create_profile`** (`gcp-backend/create_profile/main.py`,
   `Authentication.swift`'s `callCreateProfile`), sending:
   - Header: `Authorization: Bearer <idToken from step 1>`
   - Body (snake_case!): `email`, `username`, `account_type` (`"clinician"` or
     `"patient"`), optionally `symptoms_location`, `symptoms_area`, `diagnosis`.

3. **Inside `create_profile` (server-side, using the Firebase Admin SDK — this
   code runs with elevated trust, bypassing all client-side security rules):**
   - Verifies the ID token itself (`firebase_auth.verify_id_token`) — never
     trusts a client-supplied UID, only the cryptographically verified one
     embedded in the token.
   - Re-checks username uniqueness server-side (queries `profiles` where
     `username_lower == username.lower()`) — defense in depth, since this
     function is the *only* code path allowed to create a `profiles` document.
   - Generates `app_uid = str(uuid.uuid4())`.
   - Writes `profiles/{app_uid}` via the Admin SDK (`email`, `username`,
     `username_lower`, `account_type`, `symptoms_location`, `symptoms_area`,
     `diagnosis`, `auth_uid` [the real Firebase UID, kept for reference],
     `created_at`).
   - **Sets a custom claim on the Firebase Auth user:**
     `firebase_auth.set_custom_user_claims(firebase_uid, {"app_uid": app_uid})`.
     This permanently attaches `app_uid` to that Firebase user — every ID token
     minted for them from now on will include it.
   - Returns `{"app_uid": app_uid}`.

4. **App force-refreshes its ID token:** `user.getIDToken(forcingRefresh: true)`
   (`Authentication.swift`, `completeProfile`). This is the step that's easy to
   forget and silently break things — **custom claims are baked into the JWT at
   mint time.** The token from step 1 was minted *before* the claim existed, so
   it will never show `app_uid` no matter how long you wait; you must request a
   brand new token after the claim is set.

5. **From here on, `profile.id == app_uid`** — a real UUID string, indistinguishable
   in shape from the old Supabase `profiles.id`. Every `UUID(uuidString: profile.id)`
   call site in the app keeps working, completely unmodified.

6. **On every subsequent app launch / session check** (`checkCurrentSession()`,
   `signIn()` in `Authentication.swift`), the app reads
   `tokenResult.claims["app_uid"] as? String` to resolve "who is signed in" — it
   never uses `Auth.auth().currentUser!.uid` (the raw Firebase UID) as an
   application-level identity anywhere.

7. **Firestore/Storage Security Rules check `request.auth.token.app_uid`**, not
   `request.auth.uid`, for every ownership check (see §6). This is what makes the
   whole scheme actually secure: a client cannot forge this claim — only the
   `create_profile` function (running as a trusted server, with the Admin SDK)
   can set it, and Firebase signs the resulting token.

**Important operational note:** `create_profile` is a *mint-once* operation. If
the app's signup flow ever calls it twice for the same user (e.g. a retry after a
network blip that actually succeeded), the user would get a second, different
`app_uid`, a second orphaned `profiles` document, and the custom claim would just
get overwritten — not append. The app should guard against double-calling this
(e.g. only call it once, right after `createUser` succeeds, not on every login).

### How to test this without the app

See the curl-based recipe using the Identity Toolkit REST API (`accounts:signUp`)
and the Secure Token API (`securetoken.googleapis.com`) to mint tokens and decode
the resulting JWT — covered in detail earlier in this project's working notes; the
short version is: sign up via REST, call `create_profile` with the resulting
`idToken`, then mint a *fresh* token via the refresh token and decode its payload
to confirm `app_uid` is present.

---

## 4. The video-processing pipeline, step by step

```
App records/selects a video for an exercise
  │
  ▼
VideoUploadService.swift
  - generates a new jobId = UUID()
  - uploads the file to gs://dynaface-mobile-496023-dynaface-raw/
        uploads/{app_uid}/{jobId}/video.{ext}
  - writes Firestore doc processing_jobs/{jobId}:
        { id, user_id: app_uid, exercise_name, input_video_path, status: "queued" }
  │
  ▼  (this document's *creation* is the trigger)
Eventarc trigger "trigger-ix4ibbqr"
  - watches: type = google.cloud.firestore.document.v1.created,
             database = (default),
             document path pattern = processing_jobs/{jobId}
  - routes the event to → firestore-function-revised
  │
  ▼
firestore_function.py : hello_firestore()  (Cloud Run service "firestore-function-revised")
  - job_id = last segment of the created document's path
  - reads input_video_path + exercise_name straight off the new document's fields
    (falls back to a hardcoded uploads/unknown/{job_id}/video.mp4 guess ONLY if
    input_video_path is somehow missing — not expected in normal operation)
  - sets processing_jobs/{job_id}.status = "processing"
  - calls the Cloud Run Jobs Admin API directly:
        POST https://run.googleapis.com/v2/projects/{PROJECT}/locations/us-east4/
             jobs/dynaface-worker:run
        body overrides container args = [input_video_path]
    (authenticates this call using its own runtime service account's credentials)
  - on any auth/dispatch failure: sets status = "failed" + error_message and stops
  │
  ▼  (this POST starts a brand-new EXECUTION of the Job)
google_remote_dynaface_worker.py  (Cloud Run Job "dynaface-worker")
  - sys.argv[1] = input_video_path (e.g. uploads/{userId}/{jobId}/video.mp4)
  - parses user_id / job_id straight back out of that path
  - downloads the video from the raw bucket
  - (defensively) sets status = "processing" again
  - reads processing_jobs/{job_id} from Firestore to get exercise_name
    (the worker fetches this itself — the dispatch call only carries the object path)
  - runs the full Dynaface pipeline: per-frame landmark/measurement metrics,
    renders annotated.mp4
  - extract_peak_expression_frame.py: maps exercise_name → the metric that best
    represents "maximum expression" for that exercise (e.g. max brow_elevation
    for "Eyebrow Raise", min eye_aperture for the eye-closure exercises), finds
    that frame, re-opens the already-downloaded video to grab it as peak_frame.png.
    Skipped (logged, not fatal) if exercise_name is missing or unmapped.
  - uploads annotated.mp4, results.json, and (if produced) peak_frame.png to
        gs://dynaface-mobile-496023-dynaface-results/results/{userId}/{jobId}/
  - sets processing_jobs/{job_id}.status = "completed", with
    output_video_path / output_json_path / peak_frame_path filled in
  - on ANY uncaught exception anywhere above (including a top-level handler in
    __main__): sets status = "failed" + error_message instead, so a job never
    just hangs forever at "processing" with no explanation
  │
  ▼
App (PatientVideoTabs.swift / ExerciseHistoryPage.swift)
  - reads/polls processing_jobs/{jobId}; once status == "completed", fetches a
    download URL for annotated.mp4 (and peak_frame.png) via
    Storage.storage(url:).reference(withPath:).downloadURL() — gated by
    storage.rules, not a signed-URL scheme
```

### Why two different services exist for "Firestore trigger" vs "the actual work"

`firestore-function-revised` is deliberately tiny and fast — its only job is to
read the new document and fire off a Cloud Run Job execution. The actual ML
processing (`dynaface-worker`) needs the full Dynaface/torch/opencv stack (a
multi-hundred-MB image, GPU-friendly dependencies, minutes of runtime) and runs as
a **Job**, not a request-serving **Service** — Cloud Run Jobs are built for
run-to-completion batch work like this, whereas Cloud Run Services are built for
request/response HTTP traffic. Trying to do the ML work inline inside an
HTTP-triggered function would hit request timeout limits and wouldn't scale the
same way.

---

## 5. Firestore schema

| Collection | Document ID | Key fields | Written by |
|---|---|---|---|
| `profiles` | `app_uid` (UUID, minted by `create_profile`) | `email, username, username_lower, account_type, symptoms_location, symptoms_area, diagnosis, auth_uid, created_at` | `create_profile` (create, Admin SDK only); the owning user (update, via rules) |
| `patients` | client-generated UUID | `name, clinician_id, claimed_user_id, archived_at, created_at, updated_at` | Clinicians (`PatientService.swift`) |
| `processing_jobs` | client-generated UUID (the "job id") | `id, user_id, exercise_name, input_video_path, status (queued\|processing\|completed\|failed), output_video_path, output_json_path, peak_frame_path, error_message, created_at, updated_at` | Client creates (`status: "queued"` only); `firestore_function.py` / the worker advance `status` via the Admin SDK (rules forbid client updates entirely) |
| `job_patient_attributions` | == the job's id (so writes are naturally upserts) | `patient_id, attributed_by, attributed_at` | Whoever (clinician or self) links a job to a patient (`JobAttributionService.swift`) |
| `timeline_events` | client-generated UUID | `patient_id, type, occurred_at (Timestamp), notes, created_by, created_at, updated_at, job_id` | `TimelineService.swift` |

**Why client-generated UUIDs, not Firestore auto-IDs:** same reasoning as `app_uid`
— Firestore's own auto-generated document IDs aren't UUID-formatted either, and
`Patient.id` / `TimelineEvent.id` are `UUID`-typed in the Swift model. Using an
auto-ID would silently break those types the same way a raw Firebase UID would.

---

## 6. Security rules (`dynaface-mobile/firebase/firestore.rules`, `storage.rules`)

Both are deployed (confirmed live via `firebase deploy --only firestore:rules,storage:rules`).
Every check is keyed on `request.auth.token.app_uid` (the custom claim from §3) —
**never** the raw Firebase UID.

- `isClinician()` does a Firestore `get()` on the caller's own `profiles/{app_uid}`
  document and checks `account_type == "clinician"`. Clinicians get broad read
  access (any patient's profile/jobs/timeline); patients only see their own.
- `profiles`: `allow create: if false` — the client can **never** create this
  document; only `create_profile`'s Admin SDK call can (that's the whole point —
  it's the one place `app_uid` minting happens, and it can't be spoofed).
- `processing_jobs`: client can create a doc, but only with `status == "queued"`
  and `user_id == callerAppUid()`; `allow update, delete: if false` — once
  created, only the Admin SDK (the worker / the trigger function) can ever change
  it, which is how `status` transitions stay trustworthy.
- `storage.rules` mirrors this for the two GCS buckets: owner can read/write their
  own `uploads/{userId}/...`, clinicians can read (not write) any patient's
  uploads, and **nobody** can write to `results/...` from the client — only the
  worker (via its own GCS client, which bypasses Storage Rules entirely) writes
  results. `storage.rules` uses a cross-service `firestore.get(...)` call to check
  `isClinician()` from inside Storage Rules — confirmed to compile and deploy
  correctly.

---

## 7. Build & deploy mechanics

### `dynaface-worker` (Cloud Run Job)

- **Source layout:** the Docker build context is the *top-level* `Dynaface` folder
  (the parent of both `dynaface-mobile` and `dynaface-main`), not `dynaface-mobile`
  itself — the worker script (`google_remote_dynaface_worker.py`) and the
  `Dockerfile` both live at that top level.
- **`Dockerfile`:** `python:3.11-slim` base → installs `ffmpeg`/`libgl1`/
  `libglib2.0-0` (OS packages Dynaface/OpenCV need) → `COPY . /app` (the *entire*
  top-level folder, so both `dynaface-mobile/` and `dynaface-main/` end up inside
  the image) → `pip install -r dynaface-mobile/google-remote-scripts/requirements.txt`
  (flask/gunicorn leftovers from an earlier HTTP-server version, plus
  `google-cloud-storage`, `google-cloud-firestore`, opencv/numpy/pandas/scipy/pillow)
  → `pip install -e dynaface-main/dynaface-lib` (the actual Dynaface ML package —
  pulls in torch, facenet-pytorch, onnxruntime, etc. via its own setup.py) →
  downloads/initializes the ML models into `/opt/dynaface-models` **at build
  time** (baked into the image, not fetched at runtime) → entrypoint
  `python google_remote_dynaface_worker.py`.
- **`cloudbuild-worker.yaml`:** one step — `docker build -f Dockerfile .` — tagged
  and pushed to `us-east4-docker.pkg.dev/dynaface-mobile-496023/dynaface/dynaface-worker:latest`.
  Triggered manually: `gcloud builds submit --config=cloudbuild-worker.yaml .`
  from the top-level folder.
- **Important gotcha:** pushing a new image to the `:latest` tag does **not**
  automatically update an already-deployed Cloud Run Job — a Job pins to the
  resolved image digest at the moment you deploy/update it, not a live mutable
  tag. After every rebuild you must also run:
  `gcloud run jobs update dynaface-worker --image=us-east4-docker.pkg.dev/dynaface-mobile-496023/dynaface/dynaface-worker:latest --region=us-east4`
- **Env vars on the Job:** `PROJECT_ID`, `BUCKET_NAME` / `RAW_BUCKET`
  (`dynaface-mobile-496023-dynaface-raw`), `RESULTS_BUCKET`
  (`dynaface-mobile-496023-dynaface-results`), `DYNAFACE_MODEL_PATH`.
- **Service account:** `dynaface-worker-sa@dynaface-mobile-496023.iam.gserviceaccount.com`
  — has `roles/storage.objectAdmin` (read/write both buckets) and
  `roles/datastore.user` (read/write Firestore, for the status updates). Also
  carries unused legacy roles (`roles/cloudsql.client`, `roles/cloudtasks.enqueuer`)
  from an earlier design that was never built.

### `create_profile` (real Cloud Function, 2nd gen)

Deployed the conventional way:
```
gcloud functions deploy create_profile \
  --gen2 --runtime=python312 --region=us-east4 \
  --source=dynaface-mobile/gcp-backend/create_profile \
  --entry-point=create_profile --trigger-http --allow-unauthenticated
```
(`--allow-unauthenticated` is required because the caller is the mobile app
passing a Firebase ID token in the `Authorization` header — not an IAM-authenticated
GCP caller. Auth is verified *inside* the function, against Firebase, not via
Cloud Run's IAM layer.) This shows up in `gcloud functions list` as a real
Cloud Functions resource, and Cloud Functions auto-creates its underlying Cloud
Run service (`create-profile`) plus a `cloudfunctions.net` URL alias.

Runs as the **default compute service account**
(`660576181256-compute@developer.gserviceaccount.com`), which has broad
project-level `roles/editor` (covers its Firestore reads/writes) plus an
explicitly-added `roles/firebaseauth.admin` (needed for
`set_custom_user_claims` — Editor alone doesn't reliably cover Firebase Auth
admin operations).

### `firestore-function-revised` (pasted directly into the Cloud Run console)

This one was **not** deployed via `gcloud functions deploy` — it was created by
pasting `firestore_function.py` directly into the Cloud Run console's inline
"create a function" editor. The practical difference: it's a genuine Cloud Run
**Service**, not a Cloud Functions resource (it does *not* appear in
`gcloud functions list`), and its Eventarc wiring (`trigger-ix4ibbqr`) was set up
as a separate, manually-configured trigger rather than something Cloud Functions
wires up automatically.

**This distinction caused a real bug:** real (`gcloud functions deploy`-managed)
2nd-gen Cloud Functions automatically inject a `GOOGLE_CLOUD_PROJECT` /
`GCP_PROJECT` environment variable. A console-pasted-into-Cloud-Run service does
**not** get this for free. `firestore_function.py` does:
```python
TARGET_PROJECT = os.environ.get("GCP_PROJECT") or os.environ.get("GOOGLE_CLOUD_PROJECT") or "your-project-id"
```
Since neither env var was actually set on `firestore-function-revised`, every
call to the Cloud Run Jobs Admin API was literally targeting a project named
`your-project-id` — producing exactly the "Cloud Run Admin API has not been used
in project your-project-id" error. **Fix applied:** explicitly set
`GOOGLE_CLOUD_PROJECT=dynaface-mobile-496023` as an env var on the
`firestore-function-revised` Cloud Run service.

Runs as the same default compute service account as `create_profile` (broad
`roles/editor` already covers triggering Cloud Run Job executions and writing to
Firestore).

### Eventarc trigger gotcha: exact-match vs. path-pattern

When adding a `document` event filter through the Cloud Run console, there are
two different UI paths that look similar but behave very differently:
- The dedicated **"Document path"** field (with a `users/{userId}`-style
  placeholder) sets `operator: match-path-pattern` automatically — `{jobId}` acts
  as a real wildcard matching any single path segment.
- A generic **"+ ADD FILTER"** key/value row defaults to **exact match** — typing
  `document = processing_jobs/{jobId}` there means "match a document literally
  named `{jobId}`," which never happens, so the trigger silently never fires.

The currently-deployed `trigger-ix4ibbqr` has the correct configuration:
```yaml
eventFilters:
- attribute: document
  operator: match-path-pattern
  value: processing_jobs/{jobId}
- attribute: type
  value: google.cloud.firestore.document.v1.created
- attribute: database
  value: (default)
```
The gcloud-CLI equivalent of the *correct* (wildcard) field is the
`--event-filters-path-pattern` flag — `--event-filters` (no `-path-pattern`)
is the exact-match one.

---

## 8. The iOS app, file by file

All in `Dynaface Mobile/Dynaface Mobile/` unless noted.

- **`DynafaceMobileApp.swift`** — calls `FirebaseApp.configure()` at launch. This
  reads `GoogleService-Info.plist` (must be added to the Xcode target, downloaded
  from Firebase console after registering the iOS app) to know which Firebase
  project this binary talks to.
- **`FirebaseConfig.swift`** — the handful of values Firebase can't infer from
  `GoogleService-Info.plist`: the two pre-existing GCS bucket URLs (`gs://...`,
  since they predate Firebase being enabled on this project) and the deployed
  `create_profile` HTTPS URL.
- **`Authentication.swift`** (`AuthenticationService`) — wraps
  `Auth.auth().createUser/signIn/signOut`; `completeProfile()` calls
  `create_profile` then force-refreshes the ID token (§3); `checkCurrentSession()`
  / `signIn()` resolve "who's logged in" via the `app_uid` custom claim, then read
  `profiles/{app_uid}` from Firestore directly for profile data.
- **`VideoUploadService.swift`** — uploads to the raw bucket and writes the
  `processing_jobs/{jobId}` doc that kicks off §4's pipeline.
- **`JobAttributionService.swift`, `PatientService.swift`, `TimelineService.swift`**
  — Firestore CRUD for `job_patient_attributions`, `patients`, `timeline_events`
  respectively. `PatientService`/`TimelineService` explicitly generate their own
  `UUID()` and set it as the Firestore document ID (`.document(uuid.uuidString)`)
  rather than letting Firestore auto-generate one — see §5 for why.
- **`PatientVideoTabs.swift`** — queries `processing_jobs` /
  `job_patient_attributions`; resolves playback URLs via
  `Storage.storage(url:).reference(withPath:).downloadURL()` (gated by
  `storage.rules`, not a signed-URL scheme).
- **`ExerciseHistoryPage.swift`** (`ProcessedVideosPage` section) — reuses the
  same job-row decoding and download-URL logic from `PatientVideoTabs.swift`.
- **`PracticePage.swift`, `ProfilePage.swift`** — minor call-site/copy updates to
  match the above (no Supabase/Firebase-specific logic of their own).

### Backend / Python, by file

- **`gcp-backend/create_profile/main.py`** — see §3.
- **`firestore_function.py`** (deployed as the Cloud Run service
  `firestore-function-revised`) — see §4 and §7.
- **`google_remote_dynaface_worker.py`** (the `dynaface-worker` Cloud Run Job's
  entrypoint) — see §4.
- **`clinical_report_tool/clinical_facial_report.py`,
  `dynaface_video_to_csv.py`** — the core per-frame metric computation the worker
  imports; not modified for this architecture, just relocated/restored to where
  the worker's bootstrap expects them.
- **`clinical_report_tool/extract_peak_expression_frame.py`** — maps exercise name
  → peak-expression metric/frame (see §4). Also runnable standalone:
  `python clinical_report_tool/extract_peak_expression_frame.py --video v.mov --exercise "Eyebrow Raise" --results results.json --output peak.png`.
- **`annotated-videos-scripts/dynaface_extract.py`** — renders the annotated
  output video; imported by the worker's bootstrap alongside the clinical report
  tool.

---

## 9. Quick reference: how to manually test each piece

- **Auth + `create_profile`:** Identity Toolkit REST API `accounts:signUp` to get
  a real ID token without the app, then `curl` `create_profile` with it as a
  Bearer token, then mint a *fresh* token via `securetoken.googleapis.com` and
  decode its JWT payload to confirm the `app_uid` claim landed.
- **Full pipeline:** upload a video to
  `gs://dynaface-mobile-496023-dynaface-raw/uploads/{anyUserId}/{anyJobId}/video.mp4`,
  then manually create a `processing_jobs/{anyJobId}` document (Firestore console
  is easiest) with `input_video_path`, `exercise_name` (must be one of the 10 keys
  in `EXERCISE_METRIC_MAP`), `status: "queued"`. Watch the document's `status`
  field go `queued → processing → completed`, and check the results bucket for
  the three output files.
- **Worker only (skip the trigger):**
  `gcloud run jobs execute dynaface-worker --region=us-east4 --args="uploads/{userId}/{jobId}/video.mp4"`
  (still requires the video already uploaded to that path).
