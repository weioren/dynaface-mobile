"""
create_profile Cloud Function.

Called once by the iOS app, right after `Auth.auth().createUser(...)`
succeeds, to finish account setup:

  1. Verify the caller's Firebase ID token (proves they own the Firebase
     Auth user they just created).
  2. Re-check username uniqueness server-side (defense in depth — the
     client already pre-checks, but this function is the only thing
     allowed to create a `profiles` document, so it has to be the one
     that actually enforces it).
  3. Generate `app_uid` — a client-style UUID that becomes the
     `profiles` document id and is used as the app-wide "user id"
     everywhere else in the app (Patient.clinicianId, TimelineEvent.createdBy,
     etc.), instead of the raw (non-UUID-shaped) Firebase Auth uid.
  4. Write `profiles/{app_uid}` using the Admin SDK, which bypasses
     firestore.rules — this is the one place that document is ever
     created; firestore.rules denies client-side `create` on purpose.
  5. Set the `app_uid` custom claim on the Firebase user so
     firestore.rules / storage.rules can use `request.auth.token.app_uid`
     for ownership checks.

Deploy the same way as firestore_function.py, e.g.:
    gcloud functions deploy create_profile \
        --gen2 \
        --runtime=python312 \
        --region=us-east4 \
        --source=dynaface-mobile/gcp-backend/create_profile \
        --entry-point=create_profile \
        --trigger-http \
        --allow-unauthenticated

(`--allow-unauthenticated` is required because the caller is an end-user
mobile app passing a Firebase ID token in the Authorization header, not
an IAM-authenticated GCP caller — auth is verified inside the function.)
"""

from __future__ import annotations

import uuid
from typing import Any

import firebase_admin
import functions_framework
from firebase_admin import auth as firebase_auth
from firebase_admin import firestore
from flask import Request, jsonify

firebase_admin.initialize_app()

VALID_ACCOUNT_TYPES = {"clinician", "patient"}


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


@functions_framework.http
def create_profile(request: Request):
    if request.method != "POST":
        return _error("Only POST is supported", 405)

    decoded_token = _verify_id_token(request)
    if decoded_token is None:
        return _error("Missing or invalid Authorization bearer token", 401)
    firebase_uid = decoded_token["uid"]

    # Email must be verified before a profile is minted. The client gates this
    # too (SignupVerificationGate), but enforcing it here makes it unforgeable.
    if not decoded_token.get("email_verified", False):
        return _error("Please verify your email before finishing signup.", 403)

    body = request.get_json(silent=True) or {}
    email = (body.get("email") or "").strip()
    username = (body.get("username") or "").strip()

    # The address on the verified token is authoritative. The body value is
    # client supplied, so on its own it would let a caller file a profile under
    # someone else's address.
    token_email = (decoded_token.get("email") or "").strip()
    if token_email:
        email = token_email
    account_type = (body.get("account_type") or "").strip()
    symptoms_location = body.get("symptoms_location") or ""
    symptoms_area = body.get("symptoms_area") or ""
    diagnosis = body.get("diagnosis") or ""

    if not email or not username:
        return _error("email and username are required", 400)
    if account_type not in VALID_ACCOUNT_TYPES:
        return _error(f"account_type must be one of {sorted(VALID_ACCOUNT_TYPES)}", 400)

    db = firestore.client()
    username_lower = username.lower()
    email_lower = email.lower()

    profiles = db.collection("profiles")
    existing = list(profiles.where("username_lower", "==", username_lower).limit(1).stream())
    if existing:
        return _error("Username has been registered", 409)

    # Email uniqueness. Firebase Auth already allows one account per address, so
    # normally createUser blocks a repeat. It does NOT cover the orphan case: if
    # an auth user is deleted but its profile document is left behind, that
    # address becomes free in Auth and could be re-registered under a different
    # username, leaving two profiles sharing one email. Check email_lower for
    # profiles written from here on, and fall back to the raw email field so
    # documents created before email_lower existed are still caught.
    duplicate = list(profiles.where("email_lower", "==", email_lower).limit(1).stream())
    if not duplicate:
        duplicate = list(profiles.where("email", "==", email).limit(1).stream())
    if duplicate:
        return _error("Email has been registered", 409)

    app_uid = str(uuid.uuid4())
    profiles.document(app_uid).set({
        "email": email,
        "email_lower": email_lower,
        "username": username,
        "username_lower": username_lower,
        "account_type": account_type,
        "symptoms_location": symptoms_location,
        "symptoms_area": symptoms_area,
        "diagnosis": diagnosis,
        "auth_uid": firebase_uid,
        "created_at": firestore.SERVER_TIMESTAMP,
    })

    firebase_auth.set_custom_user_claims(firebase_uid, {"app_uid": app_uid})

    return jsonify({"app_uid": app_uid}), 200
