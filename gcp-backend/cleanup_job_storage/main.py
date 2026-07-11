"""
cleanup_job_storage Cloud Function.

Firestore *delete* trigger on `processing_jobs/{jobId}`. When a clinician
fully deletes an assessment, the iOS app cascades the Firestore docs
(timeline_events + processing_jobs + job_patient_attributions — see
TimelineService.deleteEvent), but it cannot remove the Cloud Storage blobs:
storage.rules denies all client writes to results/ (uploads are owner-only).
So this function does the storage cleanup the client can't, running as a
service account that bypasses Storage rules.

It deletes everything left behind for the job, in both buckets:
  - results bucket:  results/{userId}/{jobId}/   (annotated.mp4, results.json,
                     peak_frame.png, processing.lock)
  - raw bucket:      uploads/{userId}/{jobId}/    (the original recording)

Mirrors the existing `created` trigger (firestore_function/main.py): same
functions-framework CloudEvent entrypoint and Firestore protobuf decode, just
the `deleted` event type and a Storage-delete body instead of a Cloud Run
dispatch. The job doc is only ever deleted by the clinician cascade (the worker
never deletes job docs), so this fires exactly when an assessment is removed.

Deploy (gen2, Firestore delete trigger):
    gcloud functions deploy cleanup_job_storage \
        --gen2 \
        --runtime=python312 \
        --region=us-east4 \
        --source=dynaface-mobile/gcp-backend/cleanup_job_storage \
        --entry-point=cleanup_job_storage \
        --trigger-location=<FIRESTORE_DB_LOCATION> \
        --trigger-event-filters="type=google.cloud.firestore.document.v1.deleted" \
        --trigger-event-filters="database=(default)" \
        --trigger-event-filters-path-pattern="document=processing_jobs/{jobId}" \
        --set-env-vars=RESULTS_BUCKET=dynaface-mobile-496023-dynaface-results,RAW_BUCKET=dynaface-mobile-496023-dynaface-raw

`--trigger-location` must match the existing processing_jobs *create* trigger's
Firestore database location (don't guess — read it off the deployed
firestore_function trigger). The runtime service account needs
storage.objects.list + storage.objects.delete on BOTH buckets
(roles/storage.objectAdmin is the simplest grant).
"""

from __future__ import annotations

import os

import functions_framework
from cloudevents.http import CloudEvent
from google.cloud import storage
from google.events.cloud import firestore as firestore_event

# Same env-var convention the worker uses (RESULTS_BUCKET / RAW_BUCKET).
RESULTS_BUCKET = os.environ.get("RESULTS_BUCKET")
RAW_BUCKET = os.environ.get("RAW_BUCKET")

_storage = None


def _storage_client() -> storage.Client:
    global _storage
    if _storage is None:
        _storage = storage.Client()
    return _storage


def _string_field(fields, key: str):
    """Pull a string value out of a Firestore event's protobuf `fields` map."""
    value = fields.get(key)
    if value is None:
        return None
    return value.string_value or None


def _user_id_from_object_name(object_name: str) -> str | None:
    """uploads/{userId}/{jobId}/... or results/{userId}/{jobId}/... -> userId.

    Same convention as google_remote_dynaface_worker._user_id_from_object_name.
    """
    parts = object_name.split("/")
    if len(parts) >= 4 and parts[0] in {"uploads", "results"}:
        return parts[1]
    return None


def _delete_prefix(bucket_name: str | None, prefix: str) -> int:
    """Best-effort delete of every blob under `prefix`. Returns how many were
    deleted. Never raises — a missing bucket/blob must not fail the trigger
    (Eventarc would retry-loop on an already-cleaned job)."""
    if not bucket_name:
        print(f"⚠️ No bucket configured for prefix {prefix!r}; skipping.")
        return 0
    deleted = 0
    try:
        bucket = _storage_client().bucket(bucket_name)
        for blob in bucket.list_blobs(prefix=prefix):
            try:
                blob.delete()
                deleted += 1
            except Exception as exc:
                print(f"⚠️ Failed to delete gs://{bucket_name}/{blob.name}: {exc}")
    except Exception as exc:
        print(f"⚠️ Failed to list gs://{bucket_name}/{prefix}: {exc}")
    print(f"🧹 Deleted {deleted} object(s) under gs://{bucket_name}/{prefix}")
    return deleted


@functions_framework.cloud_event
def cleanup_job_storage(event: CloudEvent):
    """Delete a processing job's storage artifacts after its Firestore doc is
    deleted. Triggered by deletion of `processing_jobs/{jobId}`."""

    # 1. Decode the Firestore event payload.
    try:
        firestore_payload = firestore_event.DocumentEventData()
        firestore_payload._pb.ParseFromString(event.data)
    except Exception as parse_err:
        # A malformed payload won't get better on retry — ack with 200.
        print(f"❌ Protobuf decode crash: {parse_err}")
        return "Failed to parse payload", 200

    # On a delete event the document content is in `old_value`; `value` is
    # empty. Fall back to `value` defensively in case the event shape differs.
    old = firestore_payload.old_value
    document_name = old.name or firestore_payload.value.name
    fields = old.fields if old.fields else firestore_payload.value.fields

    if not document_name:
        print("❌ Empty document name on delete event; nothing to clean.")
        return "Empty document name", 200

    job_id = document_name.split("/")[-1]

    # 2. Resolve the owner user_id: prefer the explicit field, else parse it
    #    from the upload path the worker recorded. Don't full-scan otherwise.
    user_id = _string_field(fields, "user_id")
    if not user_id:
        input_video_path = _string_field(fields, "input_video_path")
        if input_video_path:
            user_id = _user_id_from_object_name(input_video_path)

    if not user_id:
        print(
            f"⚠️ Job {job_id}: no user_id (and no parseable input_video_path); "
            "skipping storage cleanup to avoid a full-bucket scan."
        )
        return "No user_id; skipped", 200

    print(f"🎯 Cleaning storage for job {job_id} (user {user_id})")

    # 3. Best-effort delete of both prefixes. results/ holds annotated.mp4 /
    #    results.json / peak_frame.png / processing.lock; uploads/ holds the
    #    original recording.
    total = 0
    total += _delete_prefix(RESULTS_BUCKET, f"results/{user_id}/{job_id}/")
    total += _delete_prefix(RAW_BUCKET, f"uploads/{user_id}/{job_id}/")

    print(f"✅ Job {job_id}: removed {total} storage object(s) total.")
    return "ok", 200
