# Dynaface Clinical Facial Report Tool

This folder contains a standalone Python script that turns a Dynaface CSV export into a clinical-style facial function report.

It is designed to work with Dynaface outputs from `dynaface-main/dynaface-lib`:

- **Best input:** CSV produced by `AnalyzeLandmarks` (`landmark-1-x` … `landmark-97-y`)
- **Fallback input:** CSV produced by `VideoToVideo.dump_data()` (measurement CSV with `fai`, `eye.left`, `dental_area`, etc.)

## Files

- `clinical_facial_report.py` — main report generator
- `dynaface_video_to_csv.py` — exports a full per-frame Dynaface CSV from video
- `README.md` — this guide

## What it outputs

Given a CSV input, the script creates an output folder containing:

- `report.md` — clinical summary report
- `metrics.csv` — per-frame computed metrics
- `summary.json` — compact machine-readable summary
- `plots/global_score.svg` — timeline of the global score
- `plots/synkinesis_heatmap.svg` — color-coded synkinesis summary
- `comparison_metrics.csv` — only if you provide a comparison CSV

## Valid Dynaface references used

The script uses landmark indices and measurements that are already present in Dynaface code:

- **FAI**: `AnalyzeFAI` uses landmarks `64`, `76`, `68`, `82`
- **Oral commissure excursion**: `AnalyzeOralCommissureExcursion` uses `76`, `82`, `85`
- **Eye area**: `AnalyzeEyeArea` uses landmarks `60–67` and `68–75`
- **Dental / mouth area**: `AnalyzeDentalArea` uses landmarks `88–95`
- **Brow / nose anchors**: based on the landmark neighborhoods already used by `AnalyzeBrows` and `AnalyzeNoseFrontal`

## Recommended CSV format

### 1) Landmark CSV from Dynaface
This is the preferred input.

Expected columns include:

- `frame` or `frame_num`
- `time_sec` or `time`
- `landmark-1-x`, `landmark-1-y`
- ...
- `landmark-97-x`, `landmark-97-y`

### 2) Dynaface measurement CSV
If you do not have landmark CSV, the tool can still use the measurement CSV produced by `VideoToVideo.dump_data()`.

Expected columns may include:

- `frame`, `time`
- `fai`
- `oce.l`, `oce.r`
- `brow.d`
- `dental_area`, `dental_left`, `dental_right`
- `eye.left`, `eye.right`, `eye.diff`, `eye.ratio`
- `ml`
- `tilt`, `px2mm`, `pd`
- `pitch`, `roll`, `yaw`
- `nostril`, `nose.tip`, `dorsal.base`, `dorsal.bridge`

## Metadata JSON

The report uses a separate JSON file for patient snapshot details and timeline markers.

Example `metadata.json`:

```json
{
  "patient_id": "P-001",
  "patient_name": "John Doe",
  "diagnosis": "Bell's palsy",
  "functional_status": "Partial recovery",
  "side_affected": "R",
  "date_of_injury": "2025-01-12",
  "interventions": "Physical therapy",
  "surgery": "Cross-face nerve graft",
  "botox": "2025-03-01: 15 units to periocular region",
  "notes": "Baseline and post-op comparison",
  "events": [
    {
      "time_sec": 0,
      "label": "Baseline",
      "description": "Resting face"
    },
    {
      "time_sec": 12.5,
      "label": "Surgery",
      "description": "Post-op marker"
    },
    {
      "time_sec": 28.0,
      "label": "Botox",
      "description": "Injected periocular region"
    }
  ]
}
```

## Usage

From the `dynaface-main` folder:

```powershell
python .\clinical_report_tool\clinical_facial_report.py .\input.csv --metadata .\metadata.json --outdir .\clinical_output
```

If you want to compare two CSV files:

```powershell
python .\clinical_report_tool\clinical_facial_report.py .\pre.csv --metadata .\metadata.json --compare-csv .\post.csv --outdir .\clinical_output
```

### Export a full Dynaface CSV from video

If you want Dynaface to analyze a video directly and write a single CSV with
all supported measures and landmarks, use:

```powershell
python .\dynaface_video_to_csv.py `
  "C:\Users\kimak\Documents\Quick Access\JHU\Dynaface\input\your_video.mp4" `
  --output-csv "C:\Users\kimak\Documents\Quick Access\JHU\Dynaface\output\your_video_dynaface_full.csv"
```

Optional crop mode:

```powershell
python .\dynaface_video_to_csv.py `
  "C:\Users\kimak\Documents\Quick Access\JHU\Dynaface\input\your_video.mp4" `
  --crop
```

## Notes

- The tool is meant to be a clinical reporting helper, not a medical diagnostic device.
- `clinical_facial_report.py` uses only the Python standard library.
- `dynaface_video_to_csv.py` depends on the Dynaface library and OpenCV.

## Suggested workflow

1. Run Dynaface to export landmark or measurement CSV.
2. Prepare a metadata JSON file.
3. Run this tool.
4. Review `report.md` and the generated SVGs.
5. Share or archive the `clinical_output` folder.
