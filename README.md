# Dynaface Mobile

This is a mobile app extension of Dynaface. The computer version and accompanying library can be found here: https://github.com/jeffheaton/dynaface

---

# Phase1: Start Assessment & Exercise Modules

## Branch: `feature/start-assessment`

## Changes

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

- Added visual **progress bar** showing current exercise out of total
- Recording review buttons renamed: **Retake** / **Save & Continue**
- Completion dismisses back to Dashboard (fixed nested Dashboard bug)

### 4. Custom Selection

- Retained exercise grid for manual selection below Quick Start
- "Practice Selected (N)" button for custom exercise sets

## Files Modified

| File                       | Change                                                      |
| -------------------------- | ----------------------------------------------------------- |
| `ExercisesPage.swift`      | Module definitions, Quick Start buttons, layout restructure |
| `PracticePage.swift`       | Progress bar, fixed post-completion navigation              |
| `RecordingPage.swift`      | Retake / Save & Continue button labels                      |
| `CameraRecorderView.swift` | Simulator mode toggle for dev testing                       |
| `DynafaceMobileApp.swift`  | Auth skip toggle for dev testing                            |

## Pending

- **Emotions module** — requires 7 new demo videos (happy, sad, surprised, fear, disgust, angry, neutral) and exercise definitions
- **Real device testing** — requires Apple Developer Team access
