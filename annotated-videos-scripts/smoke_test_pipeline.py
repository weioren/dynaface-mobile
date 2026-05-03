import argparse
import os
import time
from pathlib import Path
from uuid import UUID, uuid4

from supabase import create_client


def require_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def main():
    parser = argparse.ArgumentParser(description="Smoke test Supabase upload + processing_jobs + Dynaface annotated-video worker")
    parser.add_argument("--video", required=True, help="Path to a local .mov file")
    parser.add_argument("--user-id", required=True, help="Auth user UUID")
    parser.add_argument("--exercise", default="FullSmile", help="Exercise name")
    parser.add_argument("--wait-seconds", type=int, default=600, help="Max wait time for worker completion")
    args = parser.parse_args()

    supabase_url = require_env("SUPABASE_URL")
    service_key = require_env("SUPABASE_SERVICE_ROLE_KEY")
    supabase = create_client(supabase_url, service_key)

    video_path = Path(args.video).resolve()
    if not video_path.exists():
        raise FileNotFoundError(video_path)

    job_id = uuid4()
    user_id = UUID(args.user_id)
    ext = video_path.suffix.lower() if video_path.suffix else ".mov"
    input_path = f"{user_id}/{job_id}/video{ext}"

    print(f"Uploading video to raw-videos/{input_path}")
    try:
        supabase.storage.from_("raw-videos").upload(
            input_path,
            video_path.read_bytes(),
            {"content-type": "video/quicktime"},
        )
    except Exception as exc:
        raise RuntimeError(
            "Upload failed. Check bucket name/policies and service role key. "
            f"Details: {exc}"
        ) from exc

    print("Inserting processing job row...")
    try:
        supabase.table("processing_jobs").insert(
            {
                "id": str(job_id),
                "user_id": str(user_id),
                "exercise_name": args.exercise,
                "input_video_path": input_path,
                "status": "queued",
            }
        ).execute()
    except Exception as exc:
        raise RuntimeError(
            "Insert failed. Check table schema/constraints (especially user_id foreign keys and RLS). "
            f"Details: {exc}"
        ) from exc

    print(f"Queued job: {job_id}")

    poll_interval = 5
    max_polls = max(1, args.wait_seconds // poll_interval)

    for _ in range(max_polls):
        response = (
            supabase.table("processing_jobs")
            .select("*")
            .eq("id", str(job_id))
            .single()
            .execute()
        )
        row = response.data
        print(f"Current status: {row}")

        if row["status"] in ("completed", "failed"):
            break

        time.sleep(poll_interval)

    final = (
        supabase.table("processing_jobs")
        .select("*")
        .eq("id", str(job_id))
        .single()
        .execute()
        .data
    )

    print("Final row:")
    print(final)

    output_path = final.get("output_video_path") or final.get("output_csv_path")
    if final["status"] == "completed" and output_path:
        blob = supabase.storage.from_("results").download(output_path)
        suffix = Path(output_path).suffix or ".bin"
        out_file = Path(f"smoke_test_result{suffix}")
        out_file.write_bytes(blob)
        print(f"Downloaded result artifact to: {out_file.resolve()}")
    elif final["status"] != "completed":
        raise RuntimeError(f"Job did not complete successfully: {final}")


if __name__ == "__main__":
    main()