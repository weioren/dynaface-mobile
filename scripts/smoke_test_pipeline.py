import argparse
import os
import time
from pathlib import Path
from uuid import UUID, uuid4

from supabase import create_client


def main():
    parser = argparse.ArgumentParser(description="Smoke test Supabase upload + processing_jobs + Dynaface worker")
    parser.add_argument("--video", required=True, help="Path to a local .mov file")
    parser.add_argument("--user-id", required=True, help="Auth user UUID")
    parser.add_argument("--exercise", default="FullSmile", help="Exercise name")
    args = parser.parse_args()

    supabase_url = os.environ["SUPABASE_URL"]
    service_key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    supabase = create_client(supabase_url, service_key)

    video_path = Path(args.video).resolve()
    if not video_path.exists():
        raise FileNotFoundError(video_path)

    job_id = uuid4()
    user_id = UUID(args.user_id)
    input_path = f"raw-videos/{user_id}/{job_id}/video.mov"

    print(f"Uploading video to: {input_path}")
    supabase.storage.from_("raw-videos").upload(
        input_path,
        video_path.read_bytes(),
        {"content-type": "video/quicktime"},
    )

    print("Inserting processing job row...")
    supabase.table("processing_jobs").insert(
        {
            "id": str(job_id),
            "user_id": str(user_id),
            "exercise_name": args.exercise,
            "input_video_path": input_path,
            "status": "queued",
        }
    ).execute()

    print(f"Queued job: {job_id}")

    for _ in range(120):
        response = (
            supabase.table("processing_jobs")
            .select("status,output_csv_path,error_message")
            .eq("id", str(job_id))
            .single()
            .execute()
        )
        row = response.data
        print(f"Current status: {row}")

        if row["status"] in ("completed", "failed"):
            break

        time.sleep(5)

    final = (
        supabase.table("processing_jobs")
        .select("status,output_csv_path,error_message")
        .eq("id", str(job_id))
        .single()
        .execute()
        .data
    )

    print("Final row:")
    print(final)

    if final["status"] == "completed" and final["output_csv_path"]:
        csv_bytes = supabase.storage.from_("results").download(final["output_csv_path"])
        out_file = Path("smoke_test_result.csv")
        out_file.write_bytes(csv_bytes)
        print(f"Downloaded CSV to: {out_file.resolve()}")


if __name__ == "__main__":
    main()