# Test Dynaface Annotated Video Output

This guide explains how to test the updated `dynaface_extract.py` in `annotated-videos-scripts` so that it produces an **annotated MP4 video** instead of a CSV.

The annotated video includes:

- face landmarks drawn on the frame
- FAI
- dental area values
- dental ratios and differences
- eye area values
- eye ratios and differences

This uses the existing Dynaface landmark drawing behavior from the project and only changes the `dynaface_extract.py` output behavior.

---

## 1) What the script now outputs

The updated script writes an annotated video like:

```text
C:\Users\kimak\Documents\Quick Access\JHU\Dynaface\output\FullSmile_annotated.mp4
```

It no longer writes a CSV by default.

---

## 2) Prerequisites

You need:

- Python 3.12 or similar
- OpenCV
- Dynaface Python package
- a sample `.mov` or `.mp4` file

If you are using the existing Windows environment in this repo, activate the virtual environment first.

Example PowerShell:

```powershell
cd "C:\Users\kimak\Documents\Quick Access\JHU\Dynaface\dynaface-mobile"
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install dynaface opencv-python
```

If script execution is blocked:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\.venv\Scripts\Activate.ps1
```

---

## 3) Put a test video in the input folder

The current script uses a hardcoded input folder:

```text
C:\Users\kimak\Documents\Quick Access\JHU\Dynaface\input
```

Place a test video there, for example:

```text
C:\Users\kimak\Documents\Quick Access\JHU\Dynaface\input\FullSmile.mov
```

If you want to use a different file, either:

- copy it into that folder, or
- edit the hardcoded `args.input` line inside `dynaface_extract.py`

---

## 4) Run the script

From the repo root folder:

```powershell
python .\annotated-videos-scripts\dynaface_extract.py
```

If your terminal is already in `annotated-videos-scripts`, then run:

```powershell
python .\dynaface_extract.py
```

---

## 5) Where output goes

The script uses this hardcoded output folder:

```text
C:\Users\kimak\Documents\Quick Access\JHU\Dynaface\output
```

For an input file named `FullSmile.mov`, the output file will be:

```text
C:\Users\kimak\Documents\Quick Access\JHU\Dynaface\output\FullSmile_annotated.mp4
```

If you process a folder of videos, each video gets its own `_annotated.mp4` file.

---

## 6) What you should see in the video

Each processed frame should show:

- face landmarks drawn on the face
- a text overlay with the current frame and time
- FAI
- dental area
- dental left/right values
- dental ratio
- dental difference
- eye left/right values
- eye ratio
- eye difference

Only frames where Dynaface successfully detects a face are written into the output video.

---

## 7) How to verify the output

After the script finishes:

1. Open the output folder.
2. Find the `_annotated.mp4` file.
3. Play it in VLC, Movies & TV, or another video player.
4. Confirm that:
   - landmarks are visible
   - text values are visible
   - the output is a video, not a CSV

---

## 8) If you want to change the input/output folders

Open `dynaface_extract.py` and update the hardcoded defaults near the bottom of `main()`.

Look for lines like:

```python
args.input = r"C:\Users\kimak\Documents\Quick Access\JHU\Dynaface\input"
args.output = r"C:\Users\kimak\Documents\Quick Access\JHU\Dynaface\output"
```

Change them to your own paths if needed.

---

## 9) Troubleshooting

### No output video is created
- make sure the input file exists
- make sure the file is a supported video format
- make sure Dynaface models can download and initialize
- check terminal logs for a face detection failure

### Output video exists but is empty or short
- only frames with a detected face are written
- make sure the face is visible and oriented correctly
- try using a cleaner sample video

### The video plays but the overlays do not appear
- confirm you are running the updated `dynaface_extract.py`
- confirm the script completed without errors
- confirm the input video actually had face detections

---

## 10) Summary

Use this updated script when you want a **visual annotated video** from Dynaface instead of a CSV.

The exact workflow is:

```text
Put video in input folder
-> run dynaface_extract.py
-> get FullSmile_annotated.mp4 in output folder
```
