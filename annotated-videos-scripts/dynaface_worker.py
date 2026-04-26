import os
import tempfile
import time
from pathlib import Path

from supabase import create_client

from dynaface_extract import initialize_models, process_video

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_SERVICE_ROLE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
RAW_BUCKET = "raw-videos"
RESULTS_BUCKET = "results"
POLL_INTERVAL_SECONDS = int(os.getenv("WORKER_POLL_SECONDS", "5"))
FRAME_STEP = max(1, int(os.getenv("WORKER_FRAME_STEP", "1")))

supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)


def normalize_object_path(path: str, bucket: str) -> str:
    prefix = f"{bucket}/"
    return path[len(prefix):] if path.startswith(prefix) else path


def input_path_candidates(path: str) -> list[str]:
    p = normalize_object_path(path, RAW_BUCKET)
    candidates = [p]

    if p.endswith(".mov"):
        candidates.append(p[:-4] + ".mp4")
    elif p.endswith(".mp4"):
        candidates.append(p[:-4] + ".mov")

    # de-duplicate while preserving order
    seen = set()
    out = []
    for c in candidates:
        if c not in seen:
            seen.add(c)
            out.append(c)
    return out


def try_download_input(path: str) -> tuple[bytes, str]:
    last_exc = None
    for candidate in input_path_candidates(path):
        try:
            blob = supabase.storage.from_(RAW_BUCKET).download(candidate)
            return blob, candidate
        except Exception as exc:
            last_exc = exc
            continue
    raise RuntimeError(f"Input object not found for any candidate path: {input_path_candidates(path)}; last_error={last_exc}")


def mark_failed(job_id: str, message: str) -> None:
    supabase.table("processing_jobs").update(
        {
            "status": "failed",
            "error_message": message[:2000],
        }
    ).eq("id", job_id).execute()


def get_next_job():
    response = (
        supabase.table("processing_jobs")
        .select("*")
        .eq("status", "queued")
        .order("created_at", desc=False)
        .limit(1)
        .execute()
    )
    rows = response.data or []
    return rows[0] if rows else None


def process_job(job):
    job_id = job["id"]
    user_id = job["user_id"]
    input_path = job["input_video_path"]

    supabase.table("processing_jobs").update({"status": "processing"}).eq("id", job_id).execute()
    try:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir = Path(tmpdir)
            video_file = tmpdir / "input.mov"
            output_video_file = tmpdir / "annotated.mp4"

            print(f"Downloading {input_path}")
            video_bytes, resolved_path = try_download_input(input_path)
            print(f"Resolved input path: {resolved_path}")
            video_file.write_bytes(video_bytes)

            print(f"Running Dynaface on {video_file}")
            ok = process_video(
                video_file,
                output_video_file,
                crop=False,
                forced_rotation=None,
                frame_step=FRAME_STEP,
            )

            if not ok:
                mark_failed(job_id, "Dynaface returned no valid frames")
                return

            output_path = f"{user_id}/{job_id}/annotated.mp4"
            print(f"Uploading annotated video to {output_path}")
            supabase.storage.from_(RESULTS_BUCKET).upload(
                output_path,
                output_video_file.read_bytes(),
                {"content-type": "video/mp4"},
            )

            # Prefer output_video_path; fall back to output_csv_path for older schemas.
            try:
                supabase.table("processing_jobs").update(
                    {
                        "status": "completed",
                        "output_video_path": output_path,
                        "error_message": None,
                    }
                ).eq("id", job_id).execute()
            except Exception:
                supabase.table("processing_jobs").update(
                    {
                        "status": "completed",
                        "output_csv_path": output_path,
                        "error_message": None,
                    }
                ).eq("id", job_id).execute()
    except Exception as exc:
        mark_failed(job_id, f"Worker exception: {exc}")
        raise


def main():
    initialize_models()
    print(
        f"Worker started. Poll={POLL_INTERVAL_SECONDS}s, frame_step={FRAME_STEP}, "
        f"raw_bucket={RAW_BUCKET}, results_bucket={RESULTS_BUCKET}"
    )

    while True:
        try:
            job = get_next_job()
            if job:
                print(f"Processing job: {job['id']}")
                process_job(job)
            else:
                print("No queued jobs")
        except Exception as exc:
            print(f"Worker error: {exc}")

        time.sleep(POLL_INTERVAL_SECONDS)


if __name__ == "__main__":
    main()