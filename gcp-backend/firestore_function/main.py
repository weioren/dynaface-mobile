import os
import google.auth
import google.auth.transport.requests
import requests
from cloudevents.http import CloudEvent
import functions_framework  # 🚀 Added to keep the container alive on port 8080
from google.cloud import firestore as firestore_client_lib
from google.events.cloud import firestore as firestore_event

# Environment variables to define your job execution plane
TARGET_PROJECT = os.environ.get("GCP_PROJECT") or os.environ.get("GOOGLE_CLOUD_PROJECT") or "your-project-id"
REGION = "us-east4"
JOB_NAME = "dynaface-worker"
JOBS_COLLECTION = os.environ.get("JOBS_COLLECTION", "processing_jobs")

_db = None


def _firestore_client() -> firestore_client_lib.Client:
    global _db
    if _db is None:
        _db = firestore_client_lib.Client()
    return _db


def _string_field(fields, key: str):
    """Pull a string value out of a Firestore event's protobuf `fields` map."""
    value = fields.get(key)
    if value is None:
        return None
    return value.string_value or None


def _update_job_status(job_id: str, **fields) -> None:
    """Best-effort status write — never let a Firestore hiccup take down
    the trigger function itself."""
    try:
        _firestore_client().collection(JOBS_COLLECTION).document(job_id).set(
            {**fields, "updated_at": firestore_client_lib.SERVER_TIMESTAMP}, merge=True
        )
    except Exception as exc:
        print(f"⚠️ Failed to update job status for {job_id}: {exc}")


@functions_framework.cloud_event  # 🎯 Tells the wrapper runner to map incoming events here
def hello_firestore(event: CloudEvent):
    """Cloud Run function that triggers a Cloud Run Job via the Admin API.

    Triggered by creation of a `processing_jobs/{jobId}` Firestore document
    (see VideoUploadService.swift). Reads the real uploaded object path and
    exercise name off that document instead of guessing, and flips the
    document's status to "processing" before handing off to the worker.
    """

    # 1. Decode the Firestore event payload cleanly
    try:
        firestore_payload = firestore_event.DocumentEventData()
        firestore_payload._pb.ParseFromString(event.data)
    except Exception as parse_err:
        print(f"❌ Protobuf Decode Crash: {parse_err}")
        return "Failed to parse payload", 400

    document_name = firestore_payload.value.name
    if not document_name:
        print("❌ Error: Document resource name path is empty.")
        return "Empty document name", 400

    # Extract the jobId from the end of the resource path string
    job_id = document_name.split("/")[-1]
    print(f"🎯 Target Job ID captured from Firestore: {job_id}")

    fields = firestore_payload.value.fields
    input_video_path = _string_field(fields, "input_video_path")
    exercise_name = _string_field(fields, "exercise_name")
    print(f"📎 input_video_path={input_video_path!r} exercise_name={exercise_name!r}")

    if not input_video_path:
        # Shouldn't happen once the client always writes this field, but
        # fall back to the old placeholder (the worker bucket-scans for
        # the real object in that case) rather than failing outright.
        print("⚠️ No input_video_path on the job document — falling back to bucket scan.")
        input_video_path = f"uploads/unknown/{job_id}/video.mp4"

    # 2. Authenticate the request using the Function's default service account
    try:
        credentials, authed_project = google.auth.default(
            scopes=["https://www.googleapis.com/auth/cloud-platform"]
        )
        auth_request = google.auth.transport.requests.Request()
        credentials.refresh(auth_request)
    except Exception as auth_err:
        print(f"💥 Failed to generate internal OAuth token: {auth_err}")
        _update_job_status(job_id, status="failed", error_message="Internal auth error triggering worker")
        return "Auth generation failed", 500

    # 3. Build the API URL and Authorization Headers
    # 💡 Safe variable mapping stops project parameter collisions
    url = f"https://run.googleapis.com/v2/projects/{TARGET_PROJECT}/locations/{REGION}/jobs/{JOB_NAME}:run"
    headers = {
        "Authorization": f"Bearer {credentials.token}",
        "Content-Type": "application/json"
    }

    # 4. Inject container runtime argument overrides — the real uploaded
    # object path (point 4 of the migration: no more "unknown" guessing).
    payload = {
        "overrides": {
            "containerOverrides": [
                {
                    "args": [input_video_path]
                }
            ]
        }
    }

    # Mark the job as processing before dispatch so the app can show a
    # "Processing..." state immediately rather than waiting on the worker's
    # first write.
    _update_job_status(job_id, status="processing", exercise_name=exercise_name)

    print(f"🚀 Dispatching authenticated HTTP POST payload to: {url}")

    # 5. Trigger the job
    try:
        response = requests.post(url, headers=headers, json=payload)

        if response.status_code in [200, 202]:
            print("🎉 Job triggered successfully:", response.json().get("name"))
            return "Job triggered", 200
        else:
            print(f"💥 Error status code {response.status_code} triggering job: {response.text}")
            _update_job_status(
                job_id,
                status="failed",
                error_message=f"Failed to trigger worker (HTTP {response.status_code})",
            )
            return "Failed to trigger job", response.status_code

    except Exception as network_err:
        print(f"💥 Outbound API connection error: {network_err}")
        _update_job_status(job_id, status="failed", error_message=f"Network error triggering worker: {network_err}")
        return "Network dispatch timeout", 500
