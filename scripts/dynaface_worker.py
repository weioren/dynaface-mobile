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

supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)


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

    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir = Path(tmpdir)
        video_file = tmpdir / "input.mov"
        csv_file = tmpdir / "results.csv"

        print(f"Downloading {input_path}")
        video_bytes = supabase.storage.from_(RAW_BUCKET).download(input_path)
        video_file.write_bytes(video_bytes)

        print(f"Running Dynaface on {video_file}")
        ok = process_video(video_file, csv_file, crop=True, forced_rotation=None)

        if not ok:
            supabase.table("processing_jobs").update(
                {
                    "status": "failed",
                    "error_message": "Dynaface returned no valid frames",
                }
            ).eq("id", job_id).execute()
            return

        output_path = f"results/{user_id}/{job_id}/results.csv"
        print(f"Uploading CSV to {output_path}")
        supabase.storage.from_(RESULTS_BUCKET).upload(
            output_path,
            csv_file.read_bytes(),
            {"content-type": "text/csv"},
        )

        supabase.table("processing_jobs").update(
            {
                "status": "completed",
                "output_csv_path": output_path,
                "error_message": None,
            }
        ).eq("id", job_id).execute()


def main():
    initialize_models()

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

        time.sleep(5)


if __name__ == "__main__":
    main()