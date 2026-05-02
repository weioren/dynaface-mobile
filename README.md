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

# Phase 6: Account Types, Patient List & Profile Editing
**Branch:** `feature/account-type-picker`

### 1. Account Type System (Clinician / Patient)

- New `AccountType` enum (`.clinician` / `.patient`) with display names and signup-picker subtitles
- SignUp flow captures account type via segmented picker → stored on `profiles.account_type` (`text NOT NULL DEFAULT 'patient'`, CHECK constraint)
- `Profile` struct decodes `account_type` with defensive fallback to `.patient` if the column is missing from a response
- `Dashboard` reads `profile.accountType` to drive an `isClinician` flag — only clinicians get the conditional **Patients** tab (4th of 5 tabs); patients keep the original 4-tab layout

### 2. Patient List View (Clinician Tab)

- New `PatientListPage` lists every `account_type='patient'` profile, newest first
- Server-side query via `PatientService.loadAllPatientProfiles()` → `profiles WHERE account_type='patient'`, ordered by `created_at` DESC
- Each row: initials avatar (brand blue) + username + email
- Rows are tappable — push to `PatientDetailPlaceholder` via `NavigationLink` (uses Dashboard's outer `NavigationView`, no nested stack to avoid the Phase-3 freeze)
- Pull-to-refresh wired on the inner `List`
- Empty-state copy: *"Patients appear here after they sign up. Pull to refresh."*
- Search bar / Add button intentionally absent for V1 (plumbing retained — `searchedPatientProfiles(matching:)`, `searchText` state — for quick re-enable)

### 3. Patient Detail Placeholder

- Stub destination at `PatientDetailPlaceholder` showing the patient's username as title + "Patient detail view coming soon"
- Forces `.toolbar(.visible, for: .navigationBar)` to override Dashboard's `.navigationBarHidden(true)` so the back chevron stays visible
- One-line swap when Alex's `PatientDetailView(profileId:)` lands

### 4. Role-Aware Profile Menu

- Single `ProfilePage` shell with `menuItems(for accountType:)` returning `[MenuRow]` (private struct, `id: String { text }` for stable diffing)
- Patient menu: Edit profile / My progress / My past evaluations / Upcoming appointments / FAQ / Sign out
- Clinician menu: Edit profile / **My patients** (functional) / Upcoming appointments (stub) / FAQ / Sign out
- "My patients" deep-links to the Patients tab via `NotificationCenter` (`.navigateToPatientsTab`) — not `UserDefaults`, since Dashboard's `onAppear` doesn't re-fire while ProfilePage is a sibling tab in the same instance. Dashboard subscribes with an `isClinician` guard so a stray post in patient mode is a no-op.

### 5. Functional Edit Profile

- New `AuthenticationService.updateProfile(patch:)` issues partial UPDATE on `profiles` (PATCH semantics — `JSONEncoder` skips nil keys) and re-fetches via `loadProfile` so `authState` reflects the new values everywhere
- `ProfilePatch: Encodable` struct with `var` fields (`username`, `symptoms_location`, `symptoms_area`, `diagnosis`)
- `EditProfilePage` is now role-aware:
  - **Patient** edits username + symptoms_location + symptoms_area + diagnosis
  - **Clinician** edits username only — symptom/diagnosis fields hidden, not just disabled
- Email permanently disabled with caption *"Contact support to change email."*
- Username validation: non-empty, ≤ 32 chars (trimmed); Save button greys out and is disabled when invalid
- Save button shows `ProgressView().tint(.white)` during `isLoading`
- Errors surface via `.alert("Couldn't save", ...)` bound to a new `errorMessage: String?` state — no silent failure
- Guards malformed `Profile.id` strings with `guard let UUID(uuidString:)` (no force-unwrap)

### 6. Username & Email Duplicate Detection

- New SECURITY DEFINER RPC `is_username_available(name text)` — anon-callable, bypasses `profiles` RLS for global existence check (lowercased + trimmed)
- Pre-check in `createAccount` (signup) and `updateProfile` (edit) — only re-checks when username actually changes (avoids unnecessary RPC on no-op edits)
- Friendly error messages routed through Swift: `"Username has been registered"` (new `AuthError.usernameAlreadyTaken`) / `"Email has been registered"` (set on `authState.error` directly in createAccount)
- Email duplicate also detected from Supabase `auth.signUp` "already registered" error string
- No UNIQUE constraint added on `profiles.username` — race conditions accepted for MVP, RPC fails open (returns true) on transient errors so legitimate signups aren't blocked

### 7. Database Migrations

5 new SQL migrations in `supabase/migrations/`, all idempotent:

- `20260428_account_type_and_patients.sql` — adds `profiles.account_type` + `profiles.updated_at` + shared `set_updated_at()` trigger; creates the `patients` table (clinician-owned clinical records) with RLS enabled (4 policies: clinicians read/insert/update own, patients read own claimed); soft-delete only via `archived_at`
- `20260428_open_patients_read_to_all_clinicians.sql` — replaces patients SELECT policy so any clinician sees the full non-archived roster (V1 testing aid; still scoped to `account_type='clinician'` via subquery)
- `20260428_tighten_patients_insert_to_clinicians.sql` — hardens INSERT/UPDATE with explicit `account_type='clinician'` check (defense-in-depth against direct API calls bypassing the UI)
- `20260429_clinician_search_patient_profiles.sql` — adds `is_clinician(uid uuid)` SECURITY DEFINER helper + RLS policy letting clinicians read all patient-role profiles + UNIQUE partial index on `patients.claimed_user_id`
- `20260430_username_availability_check.sql` — adds `is_username_available(name text)` RPC granted to `anon, authenticated`

### 8. Recording Quality — Lighting Check

- Adds a lighting gate alongside the existing face-in-oval gate. Record button is enabled only when **face aligned AND lighting OK**; either failing keeps the button grey
- Per-frame average luminance computed in the existing `captureOutput` path — no new capture session, no new queue. Reuses the same pixel buffer Vision already runs on
- Pixel-format aware sampler:
  - **YUV (bi-planar 420)** — most common for AVCapture video data output: read Y plane (plane 0) directly
  - **BGRA fallback** — Rec. 601 luminance from RGB
  - 32×32 sample grid → ~1024 samples per frame, microsecond cost
- Three-state machine `LightingState` (`.ok` / `.tooDark` / `.tooBright`) with **hysteresis** so a borderline frame doesn't flicker the button:
  - `.ok → .tooDark` when avg Y < 45; `.tooDark → .ok` when avg Y > 55
  - `.ok → .tooBright` when avg Y > 225; `.tooBright → .ok` when avg Y < 215
- `FaceGuideOverlayView` refactored: `updateOvalAppearance` now only touches the oval visuals; new `refreshFeedbackText()` centralizes the prioritized label text (face > lighting > none); new `updateLighting(message:)` public method
- New `updateRecordingReadiness()` controller helper merges face + lighting state and is the single place that toggles the record button
- Camera flip: switching to back camera bypasses the gate (existing behavior); switching back to front resets `isFaceAligned`, `lightingState`, and clears any stale lighting message before the first frame arrives
- Recording start path unchanged — once `faceGuideCompleted` flips, sample-buffer processing skips and lighting evaluation stops too, so live luminance changes during recording don't disturb the button state

---

## Files Modified

| File                       | Phase 1 | Phase 2 | Phase 3 | Phase 4 | Phase 5 | Phase 6 |
| -------------------------- | ------- | ------- | ------- | ------- | ------- | ------- |
| `PracticePage.swift`       | Progress bar, post-completion nav | Video looping, StepProgressBar, PiPDemoPlayer, back logic | — | Review page, phase state machine, recordings dict, accordion video | — | — |
| `RecordingPage.swift`      | Retake / Save & Continue labels | Single-screen with PiP, back button, brand colors | — | Continue rename, flip camera button, recording state observer | — | + `Notification.Name.navigateToPatientsTab` |
| `ExercisesPage.swift`      | Modules, Quick Start buttons | Reset on assessment completion | — | — | — | — |
| `CameraRecorderView.swift` | Simulator mode toggle | Brand blue button color | Face guide oval, Vision face detection | Camera flip, per-camera orientation, notification-driven flip | Use shared `RecordingFiles` helper for filename numbering | Lighting check (avg-luma sampler, hysteretic 3-state machine, combined gate with face oval); `FaceGuideOverlayView` feedback refactor |
| `ExerciseHistoryPage.swift`| — | — | Removed nested NavigationView | — | Auto-expand newly added sections (snapshot/diff in `reloadSections`) | — |
| `Dashboard.swift`          | — | — | Removed Home tab | — | Auto-nav to History on `.assessmentCompleted`; new Upload tab at tag 2 | + `isClinician`, conditional Patients tab (tag 3), `.navigateToPatientsTab` subscriber with role guard |
| `Players.swift`            | — | — | — | — | `dismantleUIViewController` to stop playback on view removal | — |
| `DynafaceMobileApp.swift`  | Auth skip toggle | — | — | — | — | — |
| `Authentication.swift`     | — | — | — | — | — | `Profile` w/ `accountType`; `ProfilePatch` + `updateProfile(patch:)`; `isUsernameAvailable(_:)` RPC; `AuthError.usernameAlreadyTaken`; createAccount username pre-check + email duplicate detection |
| `SignUp.swift`             | — | — | — | — | — | Account-type segmented picker → `authViewModel.accountType` → `profiles.account_type` |
| `ProfilePage.swift`        | — | — | — | — | — | `MenuRow` + `menuItems(for:)`, role-conditional render, `EditProfilePage` rewrite (role-aware fields, validation, real save, `ProgressView`, `.alert`) |
| `Models.swift`             | — | — | — | — | — | New file — `AccountType`, `Patient`, `PatientCandidate` |
| `PatientService.swift`     | — | — | — | — | — | New file — `patientProfiles` + `loadAllPatientProfiles()` + `searchedPatientProfiles(matching:)` |
| `PatientListPage.swift`    | — | — | — | — | — | New file — clinician's patient roster |
| `PatientDetailPlaceholder.swift` | — | — | — | — | — | New file — placeholder destination |
| `AddPatientSheet.swift`    | — | — | — | — | — | New file (orphaned — kept for future patients-table flow) |

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
| `AccountType` (enum) | `Models.swift` | `.clinician` / `.patient` with picker labels and subtitles |
| `Patient` (struct) | `Models.swift` | Row model for `patients` table (clinician-owned clinical record) |
| `PatientCandidate` (struct) | `Models.swift` | Row model for patient-role profile in clinician's list |
| `PatientService` | `PatientService.swift` | `@MainActor ObservableObject` owning `@Published patientProfiles` |
| `PatientListPage` | `PatientListPage.swift` | Clinician-only Patients tab content (header + list) |
| `PatientDetailPlaceholder` | `PatientDetailPlaceholder.swift` | Coming-soon detail stub forcing nav-bar visibility |
| `ProfilePatch` (Encodable) | `Authentication.swift` | Partial-update payload for `profiles` PATCH |
| `MenuRow` (private struct) | `ProfilePage.swift` | Role-conditional menu row data model with text-based ID |
| `Notification.Name.navigateToPatientsTab` | `RecordingPage.swift` | Profile → Dashboard tab-switch channel |
| `is_clinician(uid uuid)` | DB function (SQL) | SECURITY DEFINER helper for RLS without recursion |
| `is_username_available(name text)` | DB function (SQL) | Anon-callable username pre-check RPC |
| `patients` table | DB | Clinician-owned clinical records with soft-delete + RLS |
| `LightingState` (private enum) | `CameraRecorderView.swift` | Three-state machine (`.ok / .tooDark / .tooBright`) with hysteretic transitions; `feedbackMessage` produces the user-facing hint |

## Pending

- **Emotions module** — requires 7 new demo videos and exercise definitions
- **Video upload to Supabase** — integrate Alex's `VideoUploadService.swift` into app
- **Real device testing** — requires Apple Developer Team access
- **Patient detail view** — Alex's PR; placeholder is in place, swap one line in `PatientListPage.list`
- **HIPAA compliance path** — gated on Hopkins IT / SAFE Desktop sign-off; MRN, DOB, legal name remain blocked from UI
- **Patient list search bar** — deferred for V1; `searchedPatientProfiles(matching:)` + `searchText` state retained for quick re-enable
- **Email change flow** — deferred (requires verification email round-trip)
- **`profiles.username` UNIQUE constraint** — deferred; race conditions accepted for MVP. Pre-check via RPC handles 99% of cases. Add if duplicate signups become a real problem.
