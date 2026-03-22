# dynaface_extract.py

A command-line script that runs one or more videos through [Dynaface](https://github.com/jeffheaton/dynaface) and saves a **frame-level measurements CSV** for each video.

---

## What it does

For every video it receives, the script:

1. **Determines face orientation** — either uses a fixed rotation (hardcoded or via `--orientation`), auto-detects by sampling frames at all four rotations, or shows an interactive preview and asks the user to pick. See [Orientation](#orientation) below.
2. **Analyses every frame** — passes each frame through Dynaface to extract the following measurements:

| Measurement | Description |
|---|---|
| **FAI** (Facial Asymmetry Index) | Overall left/right asymmetry score |
| **Oral Commissure Excursion** | Horizontal displacement of the mouth corners |
| **Brows** | Brow position and symmetry |
| **Dental Area** | Visible tooth area |
| **Eye Area** | Palpebral fissure area for each eye |
| **Intercanthal Distance** | Distance between inner eye corners |
| **Mouth Length** | Width of the mouth |
| **Position** | Facial midpoint position in the frame |

3. **Writes one CSV per video** with columns `frame`, `time_sec`, and all the measurements above. Frames where no face is detected are silently omitted.

---

## Installation / requirements

The script depends on `dynaface` and `opencv-python`. Install them with:

```bash
pip install dynaface opencv-python
```

---

## Hardcoded defaults

Near the bottom of `main()` there is a **HARDCODED DEFAULTS** block that overrides whatever CLI flags are passed. Edit this block to change behaviour without typing flags every time:

```python
args.input            = "/path/to/videos"
args.output           = "/path/to/output"
args.skip_existing    = True
args.no_crop          = True
args.orientation      = "none"   # "auto" | "none" | "90cw" | "180" | "90ccw"
args.verify_orientation = False  # True: show interactive preview before processing
```

---

## Usage

### Single video

```bash
python dynaface_extract.py /path/to/video.mp4
```

Output CSV is written to a `dynaface_output/` folder in the same directory as the script:

```
Code/
  dynaface_extract.py
  dynaface_output/
    video.csv          ← frame-level measurements
```

### Folder of videos

```bash
python dynaface_extract.py /path/to/videos/
```

The script recurses through the folder and mirrors the directory structure in the output:

```
/path/to/videos/
  Subject1/
    Smile/
      smile_001.mp4
  Subject2/
    Blink/
      blink_001.mp4

dynaface_output/              ← created next to the input folder
  Subject1/
    Smile/
      smile_001.csv
  Subject2/
    Blink/
      blink_001.csv
```

### Custom output folder

```bash
python dynaface_extract.py /path/to/videos/ --output /path/to/results/
```

### Skip already-processed videos

```bash
python dynaface_extract.py /path/to/videos/ --skip-existing
```

Useful when re-running after adding new videos — already-produced CSVs are not overwritten.

### Disable face cropping

```bash
python dynaface_extract.py /path/to/video.mp4 --no-crop
```

By default the script zooms in on the detected face before measuring. Pass `--no-crop` to use the full frame instead.

---

## Orientation

The script supports four ways to handle video rotation:

| `orientation` value | Behaviour |
|---|---|
| `"none"` | No rotation applied (default) |
| `"auto"` | Sample 5 frames at all four rotations; pick the one that detects a face most often |
| `"90cw"` | Rotate 90° clockwise |
| `"180"` | Rotate 180° |
| `"90ccw"` | Rotate 90° counter-clockwise |

Set `verify_orientation = True` in the hardcoded defaults block to open an interactive preview window before processing starts. The window shows a 2×2 grid of the same mid-video frame at all four rotations; press **1**, **2**, **3**, or **4** to confirm the correct one for each video.

---

## All options

| Flag | Default | Description |
|---|---|---|
| `input` | *(required)* | Path to a video file or folder |
| `--output` / `-o` | `dynaface_output/` next to the script | Where to write CSVs |
| `--skip-existing` | off | Skip videos that already have a CSV |
| `--no-crop` | off | Disable face cropping/zooming |

> **Note:** `orientation` and `verify_orientation` are set in the hardcoded defaults block inside the script, not via CLI flags.

---

## Output CSV format

Each row represents one successfully analysed frame.

| Column | Description |
|---|---|
| `frame` | Frame number (1-indexed) |
| `time_sec` | Timestamp in seconds |
| `fai` | Facial Asymmetry Index |
| `oral_commissure_*` | Oral commissure excursion values |
| `brow_*` | Brow position values |
| `dental_area` | Dental area |
| `eye_area_left` / `eye_area_right` | Eye areas |
| `intercanthal_distance` | Intercanthal distance |
| `mouth_length` | Mouth length |
| `position_*` | Facial position in frame |

> Exact column names are determined by Dynaface at runtime and may vary slightly across library versions.

---

## Relationship to `batch_video_extractor.py`

`dynaface_extract.py` extracts the core video-processing logic from `batch_video_extractor.py` into a general-purpose tool. Key differences:

| | `batch_video_extractor.py` | `dynaface_extract.py` |
|---|---|---|
| Interface | Edit constants inside the file | Hardcoded defaults block + CLI flags |
| Input | Hardcoded project folder structure | Any video or folder |
| Orientation | CSV lookup by subject/timepoint, then auto-detect | Configurable: none / auto / fixed / interactive |
| Exercise filtering | Configurable list | Not applicable |
| Intended use | Full batch run on the study dataset | Quick extraction on any video(s) |
