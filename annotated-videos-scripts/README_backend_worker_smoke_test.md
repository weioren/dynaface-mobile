# Backend Worker Smoke Test (Annotated Video Pipeline)

This smoke test validates the backend path end-to-end:

1. upload input video to `raw-videos`
2. insert `processing_jobs` row with `queued`
3. worker picks job and runs Dynaface
4. worker uploads annotated MP4 to `results`
5. smoke test downloads the result artifact

## Prerequisites

- Python environment with dependencies:
  - `supabase`
  - `dynaface`
  - `opencv-python`
- Supabase buckets:
  - `raw-videos`
  - `results`
- Table: `processing_jobs`

## 1) Set environment variables (PowerShell)

```powershell
$env:SUPABASE_URL="https://<project>.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY="<service_role_key>"
```

## 2) Start worker (Terminal A)

```powershell
cd "C:\Users\kimak\Documents\Quick Access\JHU\Dynaface\dynaface-mobile\annotated-videos-scripts"
python .\dynaface_worker.py
```

Optional speed tweak:

```powershell
$env:WORKER_FRAME_STEP="2"
$env:WORKER_POLL_SECONDS="5"
```

## 3) Run smoke test (Terminal B)

```powershell
cd "C:\Users\kimak\Documents\Quick Access\JHU\Dynaface\dynaface-mobile\annotated-videos-scripts"
python .\smoke_test_pipeline.py --video "C:\Users\kimak\Documents\Quick Access\JHU\Dynaface\input\FullSmile.mov" --user-id "11111111-1111-1111-1111-111111111111" --exercise FullSmile --wait-seconds 600
```

## Expected result

- `processing_jobs.status` transitions: `queued -> processing -> completed`
- output path set in either `output_video_path` or `output_csv_path`
- local file downloaded:
  - `smoke_test_result.mp4` (or suffix matching output path)

## Notes

- Worker writes annotated videos to `results/{user_id}/{job_id}/annotated.mp4`.
- Worker supports older DB schema by falling back to `output_csv_path` if `output_video_path` does not exist.
