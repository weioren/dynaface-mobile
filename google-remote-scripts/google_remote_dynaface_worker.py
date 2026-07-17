#!/usr/bin/env python3
"""Google Cloud Run Dynaface worker configured for Cloud Run Jobs.

Stateless GCP version optimized for long-running batch processing.
"""

from __future__ import annotations

import base64
import importlib
import importlib.util
import json
import os
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from google.cloud import storage
from google.cloud import firestore
from google.api_core.exceptions import PreconditionFailed

APP_NAME = "dynaface-google-cloud-run-job-worker"
MODEL_CACHE_DIR = Path(os.environ.get("DYNAFACE_MODEL_PATH", "/opt/dynaface-models"))
JOBS_COLLECTION = os.environ.get("JOBS_COLLECTION", "processing_jobs")

# Opt-in single-pass pipeline: computes the annotated video and the per-frame
# metrics in one MTCNN+SPIGA pass instead of two. Defaults to off so existing
# deployments keep today's (legacy two-pass) behavior until this is validated.
SINGLE_PASS_PIPELINE = os.environ.get("DYNAFACE_SINGLE_PASS", "false").strip().lower() in {
    "1",
    "true",
    "yes",
}


def _detect_workspace_root() -> Path:
    file_path = Path(__file__).resolve()

    def _is_repo_root(path: Path) -> bool:
        return (path / "dynaface-main").exists() and (path / "dynaface-mobile").exists()

    for candidate in [file_path.parent, *file_path.parents]:
        if _is_repo_root(candidate):
            return candidate

    cwd = Path.cwd().resolve()
    for candidate in [cwd, *cwd.parents]:
        if _is_repo_root(candidate):
            return candidate

    app_root = Path("/app")
    if _is_repo_root(app_root):
        return app_root

    return cwd


WORKSPACE_ROOT = _detect_workspace_root()


_BOOTSTRAPPED = False
_STORAGE_CLIENT: storage.Client | None = None
_FIRESTORE_CLIENT: firestore.Client | None = None


def _load_module_from_path(module_name: str, file_path: Path):
    spec = importlib.util.spec_from_file_location(module_name, file_path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Could not load module {module_name} from {file_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _storage_client() -> storage.Client:
    global _STORAGE_CLIENT
    if _STORAGE_CLIENT is None:
        _STORAGE_CLIENT = storage.Client(project=os.environ.get("PROJECT_ID"))
    return _STORAGE_CLIENT


def _firestore_client() -> firestore.Client:
    global _FIRESTORE_CLIENT
    if _FIRESTORE_CLIENT is None:
        _FIRESTORE_CLIENT = firestore.Client(project=os.environ.get("PROJECT_ID"))
    return _FIRESTORE_CLIENT


def _update_job_status(job_id: str, **fields: Any) -> None:
    """Best-effort status write to processing_jobs/{job_id}. Never raises —
    a Firestore hiccup shouldn't take down a video that otherwise processed
    fine (or mask the real error that's already being reported)."""
    try:
        _firestore_client().collection(JOBS_COLLECTION).document(job_id).set(
            {**fields, "updated_at": firestore.SERVER_TIMESTAMP}, merge=True
        )
    except Exception as exc:
        print(f"⚠️ Failed to update Firestore status for job {job_id}: {exc}")


def _raw_bucket() -> str:
    return os.environ.get("RAW_BUCKET") or os.environ.get("BUCKET_NAME") or "raw-videos"


def _results_bucket() -> str:
    results_bucket = os.environ.get("RESULTS_BUCKET")
    if not results_bucket:
        raise RuntimeError("RESULTS_BUCKET must be set so outputs are written to the results bucket")
    return results_bucket


def _accepted_upload_buckets() -> set[str]:
    return {_raw_bucket()}


def _is_upload_object(object_name: str) -> bool:
    return object_name.startswith("uploads/")


def _validate_model_cache() -> None:
    model_file = MODEL_CACHE_DIR / "spiga_wflw.pt"
    if not model_file.exists():
        raise FileNotFoundError(
            f"Missing predownloaded Dynaface model file: {model_file}. "
            "Rebuild the container so the image predownload step runs successfully."
        )


def _bootstrap_runtime() -> None:
    global _BOOTSTRAPPED
    if _BOOTSTRAPPED:
        return

    import sys

    workspace_root = WORKSPACE_ROOT if WORKSPACE_ROOT.exists() else Path("/app")
    dyna_lib = workspace_root / "dynaface-main" / "dynaface-lib"
    clinical_tool = workspace_root / "dynaface-mobile" / "clinical_report_tool"
    annotated_tool = workspace_root / "dynaface-mobile" / "annotated-videos-scripts"

    if not clinical_tool.exists():
        raise FileNotFoundError(f"Could not find clinical report folder: {clinical_tool}")
    if not dyna_lib.exists():
        raise FileNotFoundError(f"Could not find Dynaface library folder: {dyna_lib}")

    for p in (str(clinical_tool), str(dyna_lib)):
        if p not in sys.path:
            sys.path.insert(0, p)

    global FrameRecord, Metadata, compute_landmark_metrics, compute_measurement_metrics
    global parse_landmarks, parse_measurements, extract_summary_metrics
    from clinical_facial_report import (  # type: ignore
        FrameRecord,
        Metadata,
        compute_landmark_metrics,
        compute_measurement_metrics,
        parse_landmarks,
        parse_measurements,
        extract_summary_metrics,
    )

    global resolve_exercise, find_peak_frame, extract_peak_frame
    from extract_peak_expression_frame import (  # type: ignore
        resolve_exercise,
        find_peak_frame,
        extract_frame as extract_peak_frame,
    )

    global models, AnalyzeFace, all_measures, cv2
    from dynaface import models  # type: ignore
    from dynaface.facial import AnalyzeFace  # type: ignore
    from dynaface.measures import all_measures  # type: ignore

    cv2 = importlib.import_module("cv2")

    annotated_extract = annotated_tool / "dynaface_extract.py"
    if not annotated_extract.exists():
        raise FileNotFoundError(f"Could not find annotated Dynaface script: {annotated_extract}")

    global render_annotated_video
    dynaface_extract_mod = _load_module_from_path("annotated_dynaface_extract", annotated_extract)
    render_annotated_video = dynaface_extract_mod.process_video  # type: ignore[attr-defined]

    _BOOTSTRAPPED = True


def initialize_models() -> None:
    _validate_model_cache()
    device = models.detect_device()
    print(f"Detected device: {device}")
    models.init_models(str(MODEL_CACHE_DIR), device)


def process_video_in_memory(video_path: Path, crop: bool = False) -> list[FrameRecord]:
    capture = cv2.VideoCapture(str(video_path))
    if not capture.isOpened():
        raise RuntimeError(f"Could not open video: {video_path}")

    fps = float(capture.get(cv2.CAP_PROP_FPS) or 30.0)
    stats = all_measures()
    records: list[FrameRecord] = []
    pupils = None
    frame_idx = 0

    try:
        while True:
            ok, frame = capture.read()
            if not ok:
                break

            frame_idx += 1
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            face = AnalyzeFace(stats)
            face.load_image(rgb, crop, pupils)
            rec = face.analyze()
            if not rec:
                continue

            row = {"frame": frame_idx, "time_sec": (frame_idx - 1) / fps, **rec}
            landmarks = parse_landmarks(row)
            measures = parse_measurements(row)

            if landmarks:
                records.append(
                    FrameRecord(
                        frame=frame_idx,
                        time_sec=(frame_idx - 1) / fps,
                        landmarks=landmarks,
                        measures=measures,
                    )
                )

            if pupils is None:
                pupils = face.get_pupils()
    finally:
        capture.release()

    return records


def compute_metrics(records: list[FrameRecord]) -> list[dict[str, float]]:
    if not records:
        raise ValueError("No analyzable frames were found in the input video.")

    has_landmarks = bool(records[0].landmarks)
    if has_landmarks:
        return compute_landmark_metrics(records, metadata=Metadata())
    return compute_measurement_metrics(records)


def _job_id_from_object_name(object_name: str) -> str | None:
    parts = object_name.split("/")
    if len(parts) >= 4 and parts[0] == "uploads":
        return parts[2]
    if len(parts) >= 3 and parts[0] == "results":
        return parts[2]
    return None


def _user_id_from_object_name(object_name: str) -> str | None:
    parts = object_name.split("/")
    if len(parts) >= 4 and parts[0] in {"uploads", "results"}:
        return parts[1]
    return None


def _find_uploaded_object_for_job(job_id: str) -> tuple[str, str] | None:
    bucket = _storage_client().bucket(_raw_bucket())
    for blob in bucket.list_blobs(prefix="uploads/"):
        if f"/{job_id}/" in blob.name:
            user_id = _user_id_from_object_name(blob.name)
            return user_id or "unknown", blob.name
    return None


def _results_prefix(user_id: str, job_id: str) -> str:
    return f"results/{user_id}/{job_id}/"


def _results_json_path(user_id: str, job_id: str) -> str:
    return f"{_results_prefix(user_id, job_id)}results.json"


def _results_lock_path(user_id: str, job_id: str) -> str:
    return f"{_results_prefix(user_id, job_id)}processing.lock"


def _lock_is_stale(lock_blob: storage.Blob, stale_after_seconds: int = 7200) -> bool:
    try:
        lock_blob.reload()
    except Exception:
        return True
    updated = lock_blob.updated
    if not updated:
        return True
    if updated.tzinfo is None:
        updated = updated.replace(tzinfo=timezone.utc)
    age_seconds = (datetime.now(timezone.utc) - updated).total_seconds()
    return age_seconds > stale_after_seconds


def _acquire_job_lock(user_id: str, job_id: str, object_name: str) -> bool:
    results_bucket = _storage_client().bucket(_results_bucket())
    lock_blob = results_bucket.blob(_results_lock_path(user_id, job_id))
    result_blob = results_bucket.blob(_results_json_path(user_id, job_id))

    if result_blob.exists():
        return True

    payload = {
        "job_id": job_id,
        "user_id": user_id,
        "object_name": object_name,
        "state": "processing",
        "started_at": time.time(),
    }

    try:
        lock_blob.upload_from_string(json.dumps(payload, indent=2), content_type="application/json", if_generation_match=0)
        return True
    except PreconditionFailed:
        if _lock_is_stale(lock_blob):
            try:
                lock_blob.delete()
            except Exception:
                pass
            try:
                lock_blob.upload_from_string(json.dumps(payload, indent=2), content_type="application/json", if_generation_match=0)
                return True
            except Exception:
                return False
        return False


def _release_job_lock(user_id: str, job_id: str) -> None:
    results_bucket = _storage_client().bucket(_results_bucket())
    lock_blob = results_bucket.blob(_results_lock_path(user_id, job_id))
    try:
        lock_blob.delete()
    except Exception:
        pass


def _store_results(
    user_id: str,
    job_id: str,
    input_object_name: str,
    annotated_video_file: Path,
    summary: dict[str, Any],
    computed: list[dict[str, float]],
    peak_frame_file: Path | None = None,
) -> dict[str, str]:
    annotated_path = f"results/{user_id}/{job_id}/annotated.mp4"
    json_path = f"results/{user_id}/{job_id}/results.json"
    peak_frame_path = f"results/{user_id}/{job_id}/peak_frame.png" if peak_frame_file is not None else ""
    results_bucket = _storage_client().bucket(_results_bucket())

    json_blob = results_bucket.blob(json_path)
    if json_blob.exists():
        return {
            "output_video_path": annotated_path,
            "output_json_path": json_path,
            "peak_frame_path": peak_frame_path,
            "skipped": True,
        }

    annot_blob = results_bucket.blob(annotated_path)
    annot_blob.upload_from_filename(str(annotated_video_file), content_type="video/mp4")

    if peak_frame_file is not None:
        peak_blob = results_bucket.blob(peak_frame_path)
        peak_blob.upload_from_filename(str(peak_frame_file), content_type="image/png")

    payload = {
        "job_id": job_id,
        "user_id": user_id,
        "input_object_name": input_object_name,
        "annotated_video_path": annotated_path,
        "results_json_path": json_path,
        "peak_frame_path": peak_frame_path or None,
        "generated_at": time.time(),
        "summary": summary,
        "per_frame": computed,
    }

    try:
        json_blob.upload_from_string(json.dumps(payload, indent=2), content_type="application/json", if_generation_match=0)
        return {
            "output_video_path": annotated_path,
            "output_json_path": json_path,
            "peak_frame_path": peak_frame_path,
            "skipped": False,
        }
    except PreconditionFailed:
        return {
            "output_video_path": annotated_path,
            "output_json_path": json_path,
            "peak_frame_path": peak_frame_path,
            "skipped": True,
        }


def _extract_peak_frame_if_possible(
    video_file: Path,
    tmpdir: Path,
    exercise_name: str | None,
    computed: list[dict[str, float]],
) -> Path | None:
    """Best-effort "maximum expression" frame extraction (see
    extract_peak_expression_frame.py). Never raises — this is an
    enhancement on top of the core metrics, not something that should
    fail an otherwise-successful job."""
    if not exercise_name:
        print("ℹ️ No exercise_name on job document — skipping peak-frame extraction.")
        return None

    try:
        resolved_name, config = resolve_exercise(exercise_name)
    except KeyError:
        print(f"ℹ️ No peak-frame metric mapping for exercise '{exercise_name}' — skipping.")
        return None

    try:
        _, peak_record = find_peak_frame(computed, config["fields"], config["mode"])
        peak_frame_file = tmpdir / "peak_frame.png"
        extract_peak_frame(video_file, peak_record["frame"], peak_record["time_sec"], peak_frame_file)
        print(f"Extracted peak expression frame for '{resolved_name}': frame {int(peak_record['frame'])}")
        return peak_frame_file
    except Exception as exc:
        print(f"⚠️ Peak-frame extraction failed for exercise '{exercise_name}': {exc}")
        return None


def _process_uploaded_object(object_name: str) -> dict[str, Any]:
    _bootstrap_runtime()
    if not _is_upload_object(object_name):
        raise ValueError(f"Ignoring non-upload object: {object_name}")
    user_id = _user_id_from_object_name(object_name) or "unknown"
    job_id = _job_id_from_object_name(object_name)
    if not job_id:
        raise ValueError(f"Could not derive job id from object name: {object_name}")

    bucket_name = _raw_bucket()
    raw_bucket = _storage_client().bucket(bucket_name)
    blob = raw_bucket.blob(object_name)

    # Defensive — firestore_function.py already flips this to "processing"
    # before triggering the job, but set it here too in case this path was
    # invoked directly (e.g. local testing) without going through that function.
    _update_job_status(job_id, status="processing")

    job_doc = _firestore_client().collection(JOBS_COLLECTION).document(job_id).get()
    exercise_name = job_doc.to_dict().get("exercise_name") if job_doc.exists else None

    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        video_file = tmpdir / "input.mov"
        annotated_video_file = tmpdir / "annotated.mp4"

        print(f"Downloading gs://{bucket_name}/{object_name}")
        blob.download_to_filename(str(video_file))

        print(f"Running Dynaface on {video_file}")
        initialize_models()

        if SINGLE_PASS_PIPELINE:
            print("Pipeline mode: single-pass (DYNAFACE_SINGLE_PASS=true)")
            raw_rows: list[dict[str, Any]] = []
            ok = render_annotated_video(
                video_file, annotated_video_file, crop=False, forced_rotation=None,
                frame_step=1, measures=all_measures(), records_out=raw_rows,
            )
            if not ok:
                raise RuntimeError("Dynaface returned no valid frames while rendering annotated video")

            records: list[FrameRecord] = []
            for row in raw_rows:
                landmarks = parse_landmarks(row)
                if not landmarks:
                    continue
                records.append(
                    FrameRecord(
                        frame=row["frame"],
                        time_sec=row["time_sec"],
                        landmarks=landmarks,
                        measures=parse_measurements(row),
                    )
                )
        else:
            print("Pipeline mode: legacy two-pass")
            ok = render_annotated_video(video_file, annotated_video_file, crop=False, forced_rotation=None, frame_step=1)
            if not ok:
                raise RuntimeError("Dynaface returned no valid frames while rendering annotated video")

            records = process_video_in_memory(video_file, crop=False)

        computed = compute_metrics(records)
        summary = extract_summary_metrics(computed)

        peak_frame_file = _extract_peak_frame_if_possible(video_file, tmpdir, exercise_name, computed)

        result_paths = _store_results(
            user_id, job_id, object_name, annotated_video_file, summary, computed,
            peak_frame_file=peak_frame_file,
        )
        print(f"Uploaded annotated video and results for {object_name}")

        _update_job_status(
            job_id,
            status="completed",
            exercise_name=exercise_name,
            pipeline_mode="single_pass" if SINGLE_PASS_PIPELINE else "legacy",
            output_video_path=result_paths["output_video_path"],
            output_json_path=result_paths["output_json_path"],
            peak_frame_path=result_paths["peak_frame_path"] or None,
        )

        return {
            "ok": True,
            "job_id": job_id,
            "user_id": user_id,
            "input_object": object_name,
            **result_paths,
        }


def _process_job_by_id(job_id: str, object_name: str | None = None) -> dict[str, Any]:
    found = None
    # 🌟 FIX: If the object path contains "unknown", force a bucket scan to find the real user path
    if object_name and "/unknown/" not in object_name:
        user_id = _user_id_from_object_name(object_name) or "unknown"
        found = (user_id, object_name)
    else:
        found = _find_uploaded_object_for_job(job_id)

    if not found:
        return {"ok": False, "reason": "job_not_found", "job_id": job_id}

    user_id, object_name = found
    results_bucket = _storage_client().bucket(_results_bucket())
    result_blob = results_bucket.blob(_results_json_path(user_id, job_id))
    if result_blob.exists():
        return {"ok": True, "job_id": job_id, "user_id": user_id, "skipped": True, "reason": "already_completed"}

    if not _acquire_job_lock(user_id, job_id, object_name):
        return {"ok": True, "job_id": job_id, "user_id": user_id, "skipped": True, "reason": "already_processing"}

    try:
        result = _process_uploaded_object(object_name)
        result["user_id"] = user_id
        return result
    finally:
        _release_job_lock(user_id, job_id)


# --- 🚀 CLOUD RUN JOBS MAIN ENTRYPOINT ---
if __name__ == "__main__":
    print(f"Initializing {APP_NAME} execution task...")

    target_object = None

    if len(sys.argv) > 1:
        target_object = sys.argv[1]
        print(f"Found target object path via CLI argument: {target_object}")

    elif os.environ.get("PUBSUB_PAYLOAD"):
        try:
            raw_payload = os.environ.get("PUBSUB_PAYLOAD", "")
            envelope = json.loads(raw_payload)

            if "message" in envelope and "data" in envelope["message"]:
                data_str = base64.b64decode(envelope["message"]["data"]).decode("utf-8")
                payload = json.loads(data_str)
            else:
                payload = envelope

            target_object = payload.get("name")
            print(f"Parsed target object path from PUBSUB_PAYLOAD: {target_object}")
        except Exception as err:
            print(f"❌ Failed to parse payload string from environment: {err}")
            sys.exit(1)

    if not target_object:
        print("❌ Error: Missing execution target object path parameter.")
        sys.exit(1)

    try:
        job_id = _job_id_from_object_name(target_object)
        if not job_id:
            print(f"❌ Error: Could not extract a valid job ID from object path: {target_object}")
            sys.exit(1)

        # 🌟 FIX: If the orchestrator sent an "unknown" user hint, find the real user ID before running the existence check
        user_id = _user_id_from_object_name(target_object) or "unknown"
        if user_id == "unknown":
            print(f"ℹ️ Received placeholder path hint. Scanning bucket to locate correct user namespace for job {job_id}...")
            lookup = _find_uploaded_object_for_job(job_id)
            if lookup:
                user_id, target_object = lookup
                print(f"🎯 Discovered true object target path: gs://{_raw_bucket()}/{target_object}")
            else:
                print(f"❌ Error: No matching uploaded file found in storage bucket for Job ID: {job_id}")
                sys.exit(1)

        # Enforce Idempotency check with the corrected user namespace path
        json_path = f"results/{user_id}/{job_id}/results.json"
        results_bucket = _storage_client().bucket(_results_bucket())
        if results_bucket.blob(json_path).exists():
            print(f"ℹ️ Skipping execution: Results document already found for job {job_id}")
            sys.exit(0)

        # Run pipeline
        print(f"🎬 Launching processing pipeline for Job: {job_id}...")
        result = _process_job_by_id(job_id, object_name=target_object)

        if result.get("ok"):
            print(f"🎉 Task run completed successfully: {result}")
            sys.exit(0)
        else:
            print(f"⚠️ Task processing execution flagged a soft failure: {result}")
            sys.exit(1)

    except Exception as exc:
        print(f"💥 Job failed with an unhandled runtime crash: {exc}")
        if "job_id" in locals() and job_id:
            _update_job_status(job_id, status="failed", error_message=str(exc))
        sys.exit(1)
