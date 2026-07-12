"""
redeem_invite Cloud Function.

Called by the iOS app when a *patient* enters an invite code a clinician
shared with them (see PatientInvite flow in PatientService.swift /
ProfilePage.swift). It records the patient<->clinician association the same
way a clinician "claim" does — by writing a `patients` row whose
`claimed_user_id` is the patient — but flips the initiative to the patient
(entering the code == consent).

Why a Cloud Function (and not a plain client write):
  - firestore.rules forbid a *patient* from creating a `patients` row
    (`allow create: if isClinician()`), and only the inviting clinician can
    touch their own invite. The Admin SDK bypasses rules, so this function is
    the one place that can atomically consume the invite AND create the link.

Flow:
  1. Verify the caller's Firebase ID token; pull their `app_uid` custom claim
     (set at signup by create_profile) and confirm they're a patient.
  2. Load `patient_invites/{code}`; reject missing / expired / already-redeemed.
  3. If the patient is already actively linked to that clinician, return that
     link (idempotent) without consuming the code.
  4. Otherwise, in a transaction: mark the invite redeemed and either
     un-archive a prior (disconnected) link or create a fresh `patients` row.

Deploy the same way as create_profile:
    gcloud functions deploy redeem_invite \
        --gen2 \
        --runtime=python312 \
        --region=us-east4 \
        --source=dynaface-mobile/gcp-backend/redeem_invite \
        --entry-point=redeem_invite \
        --trigger-http \
        --allow-unauthenticated

(`--allow-unauthenticated` — the caller is an end-user app passing a Firebase
ID token in the Authorization header, not an IAM-authenticated GCP caller;
auth is verified inside the function.)
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Any

import firebase_admin
import functions_framework
from firebase_admin import auth as firebase_auth
from firebase_admin import firestore
from flask import Request, jsonify

firebase_admin.initialize_app()

# Ambiguity-free alphabet is only enforced at generation time (client side);
# on redeem we just normalize whatever the patient typed to match the doc id.
_CODE_STRIP = {" ", "-", "\t"}


class _AlreadyRedeemed(Exception):
    """Raised inside the transaction if the invite got consumed concurrently."""


def _error(message: str, status: int):
    return jsonify({"error": message}), status


def _verify_id_token(request: Request) -> dict[str, Any] | None:
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None
    id_token = header[len("Bearer "):]
    try:
        return firebase_auth.verify_id_token(id_token)
    except Exception as exc:  # noqa: BLE001 - surface as a 401 below
        print(f"ID token verification failed: {exc}")
        return None


def _normalize_code(raw: str) -> str:
    return "".join(ch for ch in raw.strip().upper() if ch not in _CODE_STRIP)


@functions_framework.http
def redeem_invite(request: Request):
    if request.method != "POST":
        return _error("Only POST is supported", 405)

    decoded_token = _verify_id_token(request)
    if decoded_token is None:
        return _error("Missing or invalid Authorization bearer token", 401)

    app_uid = decoded_token.get("app_uid")
    if not isinstance(app_uid, str) or not app_uid:
        return _error("This account hasn't finished setup yet.", 403)

    body = request.get_json(silent=True) or {}
    raw_code = body.get("code")
    if not isinstance(raw_code, str):
        return _error("Enter an invite code.", 400)
    code = _normalize_code(raw_code)
    if not code:
        return _error("Enter an invite code.", 400)

    db = firestore.client()

    # Only patient accounts can opt into a clinician.
    profile_snap = db.collection("profiles").document(app_uid).get()
    if not profile_snap.exists:
        return _error("This account hasn't finished setup yet.", 403)
    profile = profile_snap.to_dict() or {}
    if profile.get("account_type") != "patient":
        return _error("Only patient accounts can redeem an invite code.", 403)
    patient_name = profile.get("username") or "Patient"

    invite_ref = db.collection("patient_invites").document(code)
    invite_snap = invite_ref.get()
    if not invite_snap.exists:
        return _error("That invite code isn't valid.", 404)
    invite = invite_snap.to_dict() or {}

    if invite.get("redeemed_by"):
        return _error("That invite code has already been used.", 409)

    expires_at = invite.get("expires_at")
    if expires_at is not None and expires_at < datetime.now(timezone.utc):
        return _error("That invite code has expired.", 410)

    clinician_id = invite.get("clinician_id")
    clinician_name = invite.get("clinician_name") or "your clinician"
    if not clinician_id:
        return _error("That invite is missing its clinician.", 422)

    patients = db.collection("patients")

    # Idempotency / re-connect: reuse an existing row for this
    # (clinician, patient) pair instead of stacking duplicates.
    existing = list(
        patients
        .where("clinician_id", "==", clinician_id)
        .where("claimed_user_id", "==", app_uid)
        .limit(5)
        .stream()
    )
    active = [s for s in existing if (s.to_dict() or {}).get("archived_at") is None]
    if active:
        # Already connected — don't burn the code, just report it.
        return jsonify({
            "clinician_name": clinician_name,
            "patient_id": active[0].id,
            "already_connected": True,
        }), 200

    archived_ref = existing[0].reference if existing else None
    transaction = db.transaction()

    @firestore.transactional
    def _redeem(txn) -> str:
        fresh = invite_ref.get(transaction=txn)
        data = fresh.to_dict() or {}
        if data.get("redeemed_by"):
            raise _AlreadyRedeemed()

        if archived_ref is not None:
            # Re-connect: clear the archive flag on the prior link. A null
            # `archived_at` reads back as "active" on the client, same as an
            # absent field, so we avoid depending on a DELETE_FIELD sentinel.
            txn.update(archived_ref, {
                "archived_at": None,
                "clinician_name": clinician_name,
                "updated_at": firestore.SERVER_TIMESTAMP,
            })
            pid = archived_ref.id
        else:
            pid = str(uuid.uuid4())
            txn.set(patients.document(pid), {
                "clinician_id": clinician_id,
                "clinician_name": clinician_name,
                "claimed_user_id": app_uid,
                "name": patient_name,
                "created_at": firestore.SERVER_TIMESTAMP,
                "updated_at": firestore.SERVER_TIMESTAMP,
            })

        txn.update(invite_ref, {
            "redeemed_by": app_uid,
            "redeemed_by_name": patient_name,
            "redeemed_at": firestore.SERVER_TIMESTAMP,
        })
        return pid

    try:
        patient_id = _redeem(transaction)
    except _AlreadyRedeemed:
        return _error("That invite code has already been used.", 409)

    return jsonify({
        "clinician_name": clinician_name,
        "patient_id": patient_id,
        "already_connected": False,
    }), 200
