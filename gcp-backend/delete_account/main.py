"""
delete_account Cloud Function.

Called by the iOS app when a signed-in user (patient OR clinician) deletes their
own account from Profile.

How far the cascade reaches depends on the role, because "their data" differs:
  - A PATIENT erases their whole record: profile, assessments (including ones a
    clinician recorded FOR them, which are owned by the clinician's user_id and so
    are reached through the attributions), timeline, attributions, the roster rows
    pointing at them, and their Storage blobs.
  - A CLINICIAN loses only their login and their roster. The assessments,
    attributions, and timeline notes they authored are part of their PATIENTS'
    records and stay behind. Deleting them would gut patient history and leave
    timeline entries pointing at missing jobs.
The Firebase Auth user is removed in both cases.

Why this must run server-side (Admin SDK, bypasses firestore.rules /
storage.rules):
  - `profiles` and `patients` deny client delete outright (`allow delete: if false`).
  - `processing_jobs` / `timeline_events` / `job_patient_attributions` allow delete
    only for a clinician, so a patient can't remove their own rows.
  - the results bucket denies all client writes, so blobs can't be cleaned client-side.

Two-factor gate. The client re-authenticates with the account password
(Firebase `reauthenticate`) BEFORE calling this, and this function independently
requires the ID token's `email_verified` claim. Password proves possession,
verified email proves the address is real. Deleting the Auth user here also
sidesteps the client-side `requiresRecentLogin` restriction.

Case handling: the app writes id fields from Swift `UUID.uuidString` (UPPERCASE)
while `app_uid` is a lowercase python uuid4, so every query matches BOTH spellings.

Order matters: Firestore first (each deleted processing_jobs doc also fires the
cleanup_job_storage trigger for that job's blobs), then a storage sweep for
leftovers, then the Auth user LAST so a partial failure leaves the caller signed
in and able to retry.

Deploy:
    gcloud functions deploy delete_account \
        --gen2 \
        --runtime=python312 \
        --region=us-east4 \
        --source=gcp-backend/delete_account \
        --entry-point=delete_account \
        --trigger-http \
        --allow-unauthenticated \
        --set-env-vars=RESULTS_BUCKET=dynaface-mobile-496023-dynaface-results,RAW_BUCKET=dynaface-mobile-496023-dynaface-raw

(`--allow-unauthenticated` because the caller is an end-user app passing a
Firebase ID token; auth is verified inside. The runtime service account needs
storage.objects.list + storage.objects.delete on both buckets, same grant
cleanup_job_storage already uses.)
"""

from __future__ import annotations

import os
from typing import Any

import firebase_admin
import functions_framework
from firebase_admin import auth as firebase_auth
from firebase_admin import firestore
from flask import Request, jsonify
from google.cloud import storage

firebase_admin.initialize_app()

RESULTS_BUCKET = os.environ.get("RESULTS_BUCKET")
RAW_BUCKET = os.environ.get("RAW_BUCKET")

# Firestore caps a batch at 500 writes; stay under it.
_BATCH_SIZE = 400

_storage = None


def _storage_client() -> storage.Client:
    global _storage
    if _storage is None:
        _storage = storage.Client()
    return _storage


def _error(message: str, status: int):
    return jsonify({"error": message}), status


def _verify_id_token(request: Request) -> dict[str, Any] | None:
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None
    id_token = header[len("Bearer "):]
    try:
        return firebase_auth.verify_id_token(id_token)
    except Exception as exc:  # noqa: BLE001 - surfaced as a 401 below
        print(f"ID token verification failed: {exc}")
        return None


def _delete_matching(db, collection: str, field: str, values: list[str]) -> int:
    """Delete every doc in `collection` whose `field` equals any of `values`.

    Best-effort: a failure on one collection must not abort the whole account
    deletion, or the user is left half-deleted with no way to retry cleanly.
    """
    deleted = 0
    try:
        docs = list(db.collection(collection).where(field, "in", values).stream())
    except Exception as exc:  # noqa: BLE001
        print(f"⚠️ Query {collection}.{field} failed: {exc}")
        return 0

    for start in range(0, len(docs), _BATCH_SIZE):
        chunk = docs[start:start + _BATCH_SIZE]
        batch = db.batch()
        for doc in chunk:
            batch.delete(doc.reference)
        try:
            batch.commit()
            deleted += len(chunk)
        except Exception as exc:  # noqa: BLE001
            print(f"⚠️ Batch delete on {collection}.{field} failed: {exc}")

    if deleted:
        print(f"🧹 {collection}.{field}: deleted {deleted} doc(s)")
    return deleted


def _attributed_job_ids(db, values: list[str]) -> list[str]:
    """Job ids attributed to this patient. The attribution doc id IS the job id,
    which is how we reach assessments a clinician recorded for them (those jobs
    carry the clinician's user_id, not the patient's)."""
    try:
        docs = db.collection("job_patient_attributions").where("patient_id", "in", values).stream()
        return [doc.id for doc in docs]
    except Exception as exc:  # noqa: BLE001
        print(f"⚠️ Attribution lookup failed: {exc}")
        return []


def _delete_docs_by_id(db, collection: str, doc_ids: list[str]) -> int:
    """Batched delete of specific document ids. Best-effort, like _delete_matching."""
    deleted = 0
    for start in range(0, len(doc_ids), _BATCH_SIZE):
        chunk = doc_ids[start:start + _BATCH_SIZE]
        batch = db.batch()
        for doc_id in chunk:
            batch.delete(db.collection(collection).document(doc_id))
        try:
            batch.commit()
            deleted += len(chunk)
        except Exception as exc:  # noqa: BLE001
            print(f"⚠️ Batch delete by id on {collection} failed: {exc}")
    if deleted:
        print(f"🧹 {collection}: deleted {deleted} doc(s) by id")
    return deleted


def _delete_prefix(bucket_name: str | None, prefix: str) -> int:
    """Best-effort delete of every blob under `prefix` (same shape as
    cleanup_job_storage._delete_prefix). Never raises."""
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
            except Exception as exc:  # noqa: BLE001
                print(f"⚠️ Failed to delete gs://{bucket_name}/{blob.name}: {exc}")
    except Exception as exc:  # noqa: BLE001
        print(f"⚠️ Failed to list gs://{bucket_name}/{prefix}: {exc}")
    if deleted:
        print(f"🧹 Deleted {deleted} object(s) under gs://{bucket_name}/{prefix}")
    return deleted


@functions_framework.http
def delete_account(request: Request):
    if request.method != "POST":
        return _error("Only POST is supported", 405)

    decoded_token = _verify_id_token(request)
    if decoded_token is None:
        return _error("Missing or invalid Authorization bearer token", 401)

    # Second factor: the address must be verified. The first factor (password
    # re-authentication) happens client-side right before this call.
    if not decoded_token.get("email_verified", False):
        return _error("Verify your email before deleting your account.", 403)

    app_uid = decoded_token.get("app_uid")
    if not isinstance(app_uid, str) or not app_uid:
        return _error("This account hasn't finished setup yet.", 403)
    firebase_uid = decoded_token["uid"]

    # Match both the lowercase app_uid and the UPPERCASE UUID.uuidString the app writes.
    ids = list({app_uid.lower(), app_uid.upper()})

    db = firestore.client()

    # Read the role before the profile goes; it decides the cascade's reach.
    profile_ref = db.collection("profiles").document(app_uid)
    profile_snap = profile_ref.get()
    account_type = (profile_snap.to_dict() or {}).get("account_type") if profile_snap.exists else None
    is_clinician = account_type == "clinician"

    print(f"🗑️ Deleting account app_uid={app_uid} auth_uid={firebase_uid} role={account_type}")

    # 1. Firestore. Deleting a processing_jobs doc also fires cleanup_job_storage,
    #    which removes that job's results/ + uploads/ blobs.
    if is_clinician:
        # Only their own organisational data. Their assessments, attributions and
        # timeline notes stay with the patients they belong to.
        _delete_matching(db, "patients", "clinician_id", ids)
    else:
        # Assessments recorded FOR this patient carry the clinician's user_id, so
        # collect them via the attributions BEFORE those attributions are deleted.
        _delete_docs_by_id(db, "processing_jobs", _attributed_job_ids(db, ids))
        _delete_matching(db, "processing_jobs", "user_id", ids)
        _delete_matching(db, "timeline_events", "patient_id", ids)
        _delete_matching(db, "job_patient_attributions", "patient_id", ids)
        _delete_matching(db, "patients", "claimed_user_id", ids)

    try:
        profile_ref.delete()
        print(f"🧹 profiles/{app_uid} deleted")
    except Exception as exc:  # noqa: BLE001
        print(f"⚠️ Failed to delete profiles/{app_uid}: {exc}")

    # 2. Storage sweep, patients only: a clinician's blobs back the assessments we
    #    just kept. Per-job blobs are already handled by the delete trigger; this
    #    catches orphans under the user's own prefix.
    if not is_clinician:
        for uid in ids:
            _delete_prefix(RESULTS_BUCKET, f"results/{uid}/")
            _delete_prefix(RAW_BUCKET, f"uploads/{uid}/")

    # 3. Auth user last.
    try:
        firebase_auth.delete_user(firebase_uid)
        print(f"✅ Auth user {firebase_uid} deleted")
    except Exception as exc:  # noqa: BLE001
        print(f"❌ Failed to delete auth user {firebase_uid}: {exc}")
        return _error("Couldn't finish deleting the account. Please try again.", 500)

    return jsonify({"deleted": True}), 200
