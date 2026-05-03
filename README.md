This is a mobile app extension of Dynaface. The computer version and accompanying library can be found here: https://github.com/jeffheaton/dynaface

---

# Phase 1: Start Assessment & Exercise Modules
**Branch:** `feature/start-assessment`


# Next Steps
1. Call ```VideoUploadService.swfit``` after the user presses Accept
```
Task {
        do {
            let uploadService = VideoUploadService()

<<<<<<< HEAD
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
=======
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

## Files Modified

| File                       | Phase 1 | Phase 2 | Phase 3 | Phase 4 | Phase 5 |
| -------------------------- | ------- | ------- | ------- | ------- | ------- |
| `PracticePage.swift`       | Progress bar, post-completion nav | Video looping, StepProgressBar, PiPDemoPlayer, back logic | — | Review page, phase state machine, recordings dict, accordion video | — |
| `RecordingPage.swift`      | Retake / Save & Continue labels | Single-screen with PiP, back button, brand colors | — | Continue rename, flip camera button, recording state observer | — |
| `ExercisesPage.swift`      | Modules, Quick Start buttons | Reset on assessment completion | — | — | — |
| `CameraRecorderView.swift` | Simulator mode toggle | Brand blue button color | Face guide oval, Vision face detection | Camera flip, per-camera orientation, notification-driven flip | Use shared `RecordingFiles` helper for filename numbering |
| `ExerciseHistoryPage.swift`| — | — | Removed nested NavigationView | — | Auto-expand newly added sections (snapshot/diff in `reloadSections`) |
| `Dashboard.swift`          | — | — | Removed Home tab | — | Auto-nav to History on `.assessmentCompleted`; new Upload tab at tag 2 |
| `Players.swift`            | — | — | — | — | `dismantleUIViewController` to stop playback on view removal |
| `DynafaceMobileApp.swift`  | Auth skip toggle | — | — | — | — |

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

## Pending

- **Emotions module** — requires 7 new demo videos and exercise definitions
- **Video upload to Supabase** — integrate Alex's `VideoUploadService.swift` into app
- **Real device testing** — requires Apple Developer Team access
>>>>>>> origin/main
