This is a mobile app extension of Dynaface. The computer version and accompanying library can be found here: https://github.com/jeffheaton/dynaface

---

# Phase 1: Start Assessment & Exercise Modules
**Branch:** `feature/start-assessment`

### 1. Start Assessment — Quick Start Modules

- Added **Quick Start** section with one-tap module buttons:
  - **Full Assessment (10)** — all exercises
  - **Eye Movements (4)** — Eyebrow Raise, Brow Furrow, Strong Eye Closure, Weak Eye Closure
  - **Smile Movements (4)** — Full Smile, Half Smile, Lip Pucker, Lip Purse
- Layout reserves space for future **Emotions** module (pending demo videos)

### 2. Tutorial Page with Text & Video Demo

- Each exercise displays instruction text and a bundled demo video
- All 10 exercises have corresponding demo videos

### 3. Assessment Flow — Minimal Clicks, Clear Instructions

- Recording review buttons renamed: **Retake** / **Save & Continue**
- Completion dismisses back to Dashboard (fixed nested Dashboard bug)

### 4. Custom Selection

- Retained exercise grid for manual selection below Quick Start
- "Practice Selected (N)" button for custom exercise sets

---

# Phase 2: UI Improvements
**Branch:** `feature/ui-changes`

### 1. Demo Video Looping

- Tutorial demo videos now loop automatically until user starts recording

### 2. Single-Screen Recording Experience

- Combined tutorial and recording into one screen
- Main view: front-facing camera (full screen)
- Top-right PiP: demo video overlay (no black bars, auto-loop, muted, toggleable)
- Back button added to recording screen (top-left)

### 3. Step Progress Bar

- Bottom progress bar with numbered circles (1 to N)
- Completed steps turn green with checkmark
- Current step highlighted in blue
- Syncs with back navigation

### 4. Back Navigation

- Step-by-step back: step 2 → step 1 → exercise selection page
- Progress bar updates when navigating back
- Recording page back returns to current step tutorial

### 5. Assessment Completion Reset

- Exercise selections reset when user taps "Done" on completion alert
- Manual back navigation preserves selections

### 6. Consistent Button Colors

- Start, Save & Continue buttons all use brand blue (`rgb(31, 74, 163)`)

---

# Phase 3: Face Guide, Navigation Fixes & Dashboard Cleanup
**Branch:** `feature/ui-changes`

### 1. Face Guide Oval with Vision Detection

- Dashed white oval overlay on camera screen (60% width, 1.35 aspect ratio, centered)
- Real-time face detection using Apple Vision framework (`VNDetectFaceRectanglesRequest`)
- Face aligned inside oval → oval turns solid green, Start button enabled
- Face leaves oval → oval returns to dashed white, Start button disabled (grey)
- Oval dismissed permanently once recording starts
- Frame throttling to prevent overload (`isProcessingFrame` flag)
- Front camera mirrored orientation (`.leftMirrored`)

### 2. Tab Bar Freeze Fix

- Removed nested `NavigationView` in `ExerciseHistoryPage.swift`
- Dashboard already provides the outer `NavigationView`; nesting caused tab switches to freeze

### 3. Home Tab Removal

- Removed Home tab (calendar page) from Dashboard
- Retained 3 tabs: **Exercise** (0), **History** (1), **Profile** (2)

---

# Phase 4: Review Summary Page & Camera Flipping
**Branch:** `feature/ui-changes`

### 1. Review Summary Page

- After recording all exercises, entering a new Review page (replaces the completion alert)
- Header: green checkmark icon, "All exercises done!" title, dynamic recorded count
- Scrollable list of all exercises with chevron indicator
- Tap a row to inline-expand video playback (accordion, one open at a time)
- Review videos loop continuously
- Re-record button on each row to redo any individual exercise
- Re-record flow preserves the old recording until the new one is confirmed (cancel-safe)
- Auto-expands the exercise row after a successful re-record
- Bottom "Finish Assessment" button posts completion notification

### 2. Phase State Machine in PracticePage

- New `PracticePhase` enum (`exercising` / `review` / `rerecording`) replaces alert-based flow
- Data structure upgraded from `Set<Int>` to `[Int: URL]` to persist video file URLs
- Single-page state switching avoids nested navigation pushes

### 3. Camera Flipping

- Front ↔ back camera toggle in the recording screen top bar
- Flip button hidden during active recording to prevent interruption
- Switching to back camera hides the face guide oval and enables the record button directly
- Switching back to front camera restores the oval and resets face alignment state
- Vision face detection orientation adjusted per camera (`.leftMirrored` vs `.right`)
- SwiftUI ↔ UIKit communication via NotificationCenter (`.flipCamera`, `.recordingStateChanged`)
- Proper observer cleanup in `viewWillDisappear` to prevent memory leaks

---

# Phase 5: Auto-Nav to History, Auto-Expand Fix, Player Leak Fix & Upload Video Tab
**Branch:** `feature/ui-changes-3`

### 1. Auto-Navigate to History After Assessment

- After tapping **Finish Assessment**, the app auto-switches to the History tab (was returning to Exercises)
- Implemented via `.onReceive(.assessmentCompleted)` on Dashboard's `TabView` with `withAnimation { selectedTab = 1 }`
- Existing notification flow unchanged — `PracticePage` posts `.assessmentCompleted` then dismisses

### 2. History Page Auto-Expand for Newly Added Sections

- **Bug**: after recording, the new "Today" section stayed collapsed if any other section was already expanded — videos appeared "hidden" until the user tapped to expand
- `reloadSections()` now snapshots previous section IDs before overwriting, computes `newIds.subtracting(previousIds)`, and `formUnion`s the diff into `expandedDays` / `expandedExercises`
- First-load behavior preserved (auto-expand only the top section)
- Respects user's explicit collapse — if a section already existed and the user collapsed it, it stays collapsed across reloads

### 3. MirroredAVPlayerControllerView Dismantle Fix

- **Bug**: video and audio kept playing after popping `HistoryDetailView` or collapsing the review accordion. Coordinator's `deinit` was eventually called, but ARC release timing combined with the loop observer closure and `AVPlayerViewController.player` both retaining the player meant playback continued meanwhile
- Implemented `static dismantleUIViewController(_:coordinator:)` to immediately remove the loop observer, pause `vc.player`, and nil out all player references. SwiftUI calls this synchronously when the representable leaves the hierarchy
- Covers all callers: `HistoryDetailView`, `PracticePage` review accordion, `RecordingPage` review phase

### 4. Upload Video Tab (4th Tab)

- New **Upload** tab using SwiftUI-native `PhotosPicker` (matches existing pattern in `ProfilePage`)
- State machine `UploadPhase`: `empty → loading → previewing → readyToSave → saving → savedFlash`
- Custom `Movie: Transferable` (`FileRepresentation` with `contentType: .movie`) streams a video URL into a temp file — no `Data` buffering for large videos
- After picking, mirrored preview via existing `MirroredAVPlayerControllerView`
- Sheet-based exercise selector lists all 10 exercises from `allExercises` (`ExercisesPage.swift`)
- Save copies the file to Documents as `<exercise.title>_<N>.mov` — same convention as native recordings
- Posts `.recordingAccepted` after save → `ExerciseHistoryPage` and `HomePage` (streak) auto-refresh, no new plumbing
- 2-second success banner, returns to empty state for consecutive uploads
- Profile tab moves from tag 2 to tag 3; Upload occupies tag 2

### 5. Filename Helper Refactor

- Extracted `getNextFileNumber(for:)` from `CameraRecorderView` into module-level `RecordingFiles.swift`
- Added `saveImportedVideo(from:exerciseTitle:)` (used by Upload) and `nextFileNumber(for:in:)` (shared)
- Native recording and Upload now share one source of truth for filename numbering — both write `<exercise.title>_<N>.mov` to Documents

---

# Phase 6: Clinician / Patient Account Split + Patient List + Per-Type Profiles
**Branch:** `feature/ui-changes-4`

Per the 2026-04-26 meeting and Oren's UX/UI overhaul diagram, the app now branches at login into a clinician root (with a patient roster) and a patient root (own data). Weichao owns the **full stack** (Supabase schema + auth + UI) of the red-boxed sections in Oren's diagram; Alex owns the section below it (Patient detail view container, Timeline, Analysis).

### 1. Supabase schema migration

- New SQL migration at `supabase/migrations/20260427_add_account_type_and_patients.sql`:
  - Adds `account_type text NOT NULL DEFAULT 'patient'` column to `profiles` (CHECK ∈ {clinician, patient})
  - Creates `patients` table (`id`, `clinician_id` FK → `profiles(id)`, `name`, `created_at`) with index on `clinician_id`
  - Enables RLS with four policies: clinicians can SELECT / INSERT / UPDATE / DELETE only their own patients (`auth.uid() = clinician_id`)
- Idempotent (`ADD COLUMN IF NOT EXISTS`, `CREATE TABLE IF NOT EXISTS`, `DROP POLICY IF EXISTS` before each `CREATE POLICY`) so re-runs are safe

### 2. AccountType in the auth layer

- New `AccountType` enum (`clinician`, `patient`) with `displayName` + `subtitle` for UI
- `Profile` struct gets a non-optional `accountType` field; custom `init(from:)` decoder defaults to `.patient` if the column is missing (defensive against any pre-migration rows)
- `AuthState.accountCreated` carries `(email: String, accountType: AccountType)` so downstream views know which signup flow to show
- `AuthenticationService.createAccount(...)` accepts `accountType: AccountType` and stashes it in `pendingAccountType` until profile completion
- `createUserProfile(...)` writes `account_type` on insert; symptom columns default to empty strings when no survey responses are provided (clinician case)

### 3. SignUp picker + branched survey

- `CreateAccountView` adds a segmented picker between Username and Password fields. Default `.clinician`. Subtitle text hints at the choice's meaning.
- `SurveyFlow` branches on `accountType`:
  - `.patient` → existing 4-page symptom survey (FirstPage → SecondPage → ThirdPage → FourthPage → FifthPage)
  - `.clinician` → jumps directly to FifthPage with empty symptom strings
- `FifthPage.completeProfile()` detects the empty-string case and passes `nil` for `SurveyResponses` so the auth service writes blank symptom columns rather than fake answers

### 4. Clinician root

- New `ClinicianRootView` — `TabView` with two tabs: Patients (`PatientListPage`) and Profile (`ClinicianMyProfile`)
- Owns a single `PatientService` via `@StateObject`, shared with children via `@EnvironmentObject`
- Loads patient list automatically on first appearance via `.task`
- `PatientListPage` — `.searchable` modifier, list rows with avatar initials + name + created date, "Add patient" `+` button in nav bar, empty-state view, no-matches view, pull-to-refresh, error alert
- `AddPatientSheet` — single name field (DOB/MRN deferred until HIPAA path is confirmed), saves via `PatientService.addPatient(...)`, closes on success
- `ClinicianMyProfile` — read-only username/email/role, sign-out button (editing pending `AuthenticationService.updateProfile(...)`)
- `PatientDetailPlaceholder` — throwaway "Coming soon — Alex" page at the destination of patient row taps. Alex's PR replaces with the real `PatientDetailView`.

### 5. Patient root

- New `PatientRootView` — `TabView` with My care (lands directly on `PatientDetailPlaceholder` for the patient's own data) and Profile (`PatientMyProfile`)
- Synthesizes a `Patient` value from the signed-in profile so `PatientDetailPlaceholder` can be reused (V1 stop-gap; Alex's `PatientDetailView` will likely take a generic identifier and fetch its own scope)
- `PatientMyProfile` — surfaces username/email/role plus the symptom answers captured during signup (affected side, area, diagnosis), sign-out button

### 6. PatientService — Supabase CRUD

- `loadPatients(for clinicianId: UUID)` — `SELECT … FROM patients WHERE clinician_id = ? ORDER BY created_at DESC`
- `addPatient(name:clinicianId:)` — `INSERT … RETURNING *`, prepends new row to local `@Published patients` array
- `searchedPatients(matching:)` — client-side case-insensitive substring filter on `name` (single clinician's roster is small enough that round-tripping per keystroke is unnecessary)

### 7. Root routing + dev toggle

- `DynafaceMobileApp.RootContainer` switches on `Profile.accountType` after `.signedIn` and renders `ClinicianRootView` or `PatientRootView`
- New dev-only `mockAccountType: AccountType?` flag (default `nil`) — when set, bypasses real auth and renders the matching root directly. Useful for previewing UI without going through full Supabase round-trips. Lives next to the existing `skipAuth` flag.

---

## Files Modified

| File                       | Phase 1 | Phase 2 | Phase 3 | Phase 4 | Phase 5 | Phase 6 |
| -------------------------- | ------- | ------- | ------- | ------- | ------- | ------- |
| `PracticePage.swift`       | Progress bar, post-completion nav | Video looping, StepProgressBar, PiPDemoPlayer, back logic | — | Review page, phase state machine, recordings dict, accordion video | — | — |
| `RecordingPage.swift`      | Retake / Save & Continue labels | Single-screen with PiP, back button, brand colors | — | Continue rename, flip camera button, recording state observer | — | — |
| `ExercisesPage.swift`      | Modules, Quick Start buttons | Reset on assessment completion | — | — | — | — |
| `CameraRecorderView.swift` | Simulator mode toggle | Brand blue button color | Face guide oval, Vision face detection | Camera flip, per-camera orientation, notification-driven flip | Use shared `RecordingFiles` helper for filename numbering | — |
| `ExerciseHistoryPage.swift`| — | — | Removed nested NavigationView | — | Auto-expand newly added sections (snapshot/diff in `reloadSections`) | — |
| `Dashboard.swift`          | — | — | Removed Home tab | — | Auto-nav to History on `.assessmentCompleted`; new Upload tab at tag 2 | — |
| `Players.swift`            | — | — | — | — | `dismantleUIViewController` to stop playback on view removal | — |
| `Authentication.swift`     | — | — | — | — | — | `Profile.accountType` field, custom decoder, account-type plumbing through `createAccount` / `completeProfile` / `createUserProfile`, `AuthState.accountCreated(email, accountType)` |
| `SignUp.swift`             | — | — | — | — | — | Account-type segmented picker on `CreateAccountView`, `SurveyFlow` branches on type, `FifthPage` passes `nil` `SurveyResponses` for clinicians |
| `DynafaceMobileApp.swift`  | Auth skip toggle | — | — | — | — | `RootContainer` routes by `Profile.accountType`; new `mockAccountType` dev flag |

## New Components

| Component | File | Description |
| --------- | ---- | ----------- |
| `StepProgressBar` | `PracticePage.swift` | Reusable numbered step indicator |
| `PiPDemoPlayer` | `PracticePage.swift` | Fill-frame, no-black-bar, muted looping video player |
| `FaceGuideOverlayView` | `CameraRecorderView.swift` | CAShapeLayer oval with dashed/solid states and alignment callback |
| `PracticePhase` (enum) | `PracticePage.swift` | Three-state machine (exercising / review / rerecording) |
| `UploadVideoPage` | `UploadVideoPage.swift` | New 4th tab — Photos import + exercise selection + save flow |
| `UploadPhase` (enum) | `UploadVideoPage.swift` | State machine for upload (`empty → previewing → readyToSave → saving → savedFlash`) |
| `Movie` (Transferable) | `UploadVideoPage.swift` | `FileRepresentation` bridge from `PhotosPickerItem` to a temp video URL |
| `RecordingFiles` (helpers) | `RecordingFiles.swift` | Module-level `nextFileNumber(for:in:)` + `saveImportedVideo(from:exerciseTitle:)` shared by recording and upload paths |
| `AccountType` (enum) | `Models.swift` | Clinician / patient discriminator with `displayName` + `subtitle` |
| `Patient` (struct) | `Models.swift` | Codable patient record (`id`, `name`, `clinicianId`, `createdAt`) with snake-case `CodingKeys` |
| `PatientService` | `PatientService.swift` | `@MainActor ObservableObject` Supabase CRUD for the `patients` table |
| `ClinicianRootView` | `ClinicianRootView.swift` | TabView (Patients, Profile) for clinician accounts |
| `PatientListPage` | `PatientListPage.swift` | Searchable patient list with empty-state, add button, pull-to-refresh, error alert |
| `AddPatientSheet` | `AddPatientSheet.swift` | Single-field sheet to insert a patient row |
| `ClinicianMyProfile` | `ClinicianMyProfile.swift` | Clinician-flavored profile + sign-out |
| `PatientDetailPlaceholder` | `PatientDetailPlaceholder.swift` | Throwaway "Coming soon" view at patient row taps; Alex's PR replaces |
| `PatientRootView` | `PatientRootView.swift` | TabView (My care, Profile) for patient accounts |
| `PatientMyProfile` | `PatientMyProfile.swift` | Patient-flavored profile (with symptom answers) + sign-out |

## Pending

- **Emotions module** — requires 7 new demo videos and exercise definitions
- **Video upload to Supabase** — integrate Alex's `VideoUploadService.swift` into app
- **Real device testing** — requires Apple Developer Team access
