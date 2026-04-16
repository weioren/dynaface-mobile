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

## Files Modified

| File                       | Phase 1 | Phase 2 | Phase 3 |
| -------------------------- | ------- | ------- | ------- |
| `PracticePage.swift`       | Progress bar, post-completion nav | Video looping, StepProgressBar, PiPDemoPlayer, back logic | — |
| `RecordingPage.swift`      | Retake / Save & Continue labels | Single-screen with PiP, back button, brand colors | — |
| `ExercisesPage.swift`      | Modules, Quick Start buttons | Reset on assessment completion | — |
| `CameraRecorderView.swift` | Simulator mode toggle | Brand blue button color | Face guide oval, Vision face detection |
| `ExerciseHistoryPage.swift`| — | — | Removed nested NavigationView |
| `Dashboard.swift`          | — | — | Removed Home tab |
| `DynafaceMobileApp.swift`  | Auth skip toggle | — | — |

## New Components

| Component | File | Description |
| --------- | ---- | ----------- |
| `StepProgressBar` | `PracticePage.swift` | Reusable numbered step indicator |
| `PiPDemoPlayer` | `PracticePage.swift` | Fill-frame, no-black-bar, muted looping video player |
| `FaceGuideOverlayView` | `CameraRecorderView.swift` | CAShapeLayer oval with dashed/solid states and alignment callback |

## Pending

- **Emotions module** — requires 7 new demo videos and exercise definitions
- **Real device testing** — requires Apple Developer Team access
