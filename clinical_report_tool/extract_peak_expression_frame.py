"""
extract_peak_expression_frame.py

Given a source video, an exercise name, and the Dynaface results JSON
(global + per-frame metrics) produced for that video, extract the single
video frame that best represents the "maximum expression" for that
exercise — e.g. peak brow elevation for Eyebrow Raise, peak eye closure
for Strong/Weak Eye Closure, peak dental show for Full Smile, etc.

Importable from the Cloud Run worker (`EXERCISE_METRIC_MAP`, `find_peak_frame`,
`extract_frame`) as well as runnable standalone:

    python extract_peak_expression_frame.py \
        --video video.mov \
        --exercise "Eyebrow Raise" \
        --results "results.json" \
        --output peak_frame.png

    # List the exercises this script knows how to score
    python extract_peak_expression_frame.py --list-exercises
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

import cv2

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Exercise -> metric mapping
#
# Each exercise is scored using one or more fields from the per-frame
# records produced by the Dynaface pipeline (see clinical_facial_report.py
# / google_remote_dynaface_worker.py for how these are computed). When
# multiple fields are listed (e.g. left/right channels) they are averaged
# before the max/min is taken. Comments call out cases where the pipeline
# doesn't emit a dedicated metric and a proxy is used instead.
# ---------------------------------------------------------------------------
EXERCISE_METRIC_MAP: dict[str, dict] = {
    "Eyebrow Raise": {
        "fields": ["brow_elevation"],
        "mode": "max",
    },
    "Brow Furrow": {
        # No dedicated furrow metric is emitted; brow elevation magnitude
        # is used as the closest available proxy for furrow depth.
        "fields": ["brow_elevation"],
        "mode": "max",
    },
    "Strong Eye Closure": {
        "fields": ["eye_aperture_l", "eye_aperture_r"],
        "mode": "min",
    },
    "Weak Eye Closure": {
        "fields": ["eye_aperture_l", "eye_aperture_r"],
        "mode": "min",
    },
    "Nose Wrinkle": {
        "fields": ["alar_movement"],
        "mode": "max",
    },
    "Cheek Puff": {
        # "Blowfish" exercise — cheeks/mouth area proxy peaks when puffed.
        "fields": ["mouth_area"],
        "mode": "max",
    },
    "Full Smile": {
        "fields": ["dental_show_proxy"],
        "mode": "max",
    },
    "Half Smile": {
        # Teeth aren't shown, so commissure excursion (corner-of-mouth
        # pull) is used instead of dental show.
        "fields": ["commissure_exc_l", "commissure_exc_r"],
        "mode": "max",
    },
    "Lip Pucker": {
        "fields": ["mouth_area"],
        "mode": "min",
    },
    "Lip Purse": {
        "fields": ["mouth_area"],
        "mode": "min",
    },
}


def find_peak_frame(per_frame: list[dict], fields: list[str], mode: str) -> tuple[float, dict]:
    """Return (score, record) for the per_frame record with the max/min averaged field value."""

    def score(record: dict) -> float | None:
        values = [record[f] for f in fields if record.get(f) is not None]
        if not values:
            return None
        return sum(values) / len(values)

    scored = [(score(r), r) for r in per_frame]
    scored = [(s, r) for s, r in scored if s is not None]
    if not scored:
        raise ValueError(f"None of the fields {fields} were present in per_frame data")

    pick = max if mode == "max" else min
    return pick(scored, key=lambda pair: pair[0])


def extract_frame(video_path: Path, frame_number: float, time_sec: float, output_path: Path) -> Path:
    """Save the video frame matching frame_number (1-indexed, as emitted in results JSON) to output_path."""
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise IOError(f"Could not open video: {video_path}")

    frame_index = int(round(frame_number)) - 1
    cap.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
    ok, frame = cap.read()

    if not ok:
        # Fall back to seeking by timestamp if direct frame indexing failed
        # (e.g. variable frame rate video where frame counts drift).
        cap.set(cv2.CAP_PROP_POS_MSEC, time_sec * 1000.0)
        ok, frame = cap.read()

    cap.release()

    if not ok:
        raise IOError(f"Could not read frame {frame_number} (t={time_sec:.3f}s) from {video_path}")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(output_path), frame)
    return output_path


def resolve_exercise(name: str) -> tuple[str, dict]:
    name = name.strip()
    for key, config in EXERCISE_METRIC_MAP.items():
        if key.lower() == name.lower():
            return key, config
    available = ", ".join(sorted(EXERCISE_METRIC_MAP))
    raise KeyError(f"Unknown exercise '{name}'. Available exercises: {available}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract the peak-expression frame for an exercise from a Dynaface results JSON.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--video", help="Path to the source video")
    parser.add_argument("--exercise", help="Exercise name, e.g. 'Eyebrow Raise'")
    parser.add_argument("--results", help="Path to the results JSON with per_frame metrics")
    parser.add_argument(
        "--output",
        default=None,
        help="Path to write the extracted frame image (default: <video_stem>_<exercise>_peak.png)",
    )
    parser.add_argument(
        "--list-exercises",
        action="store_true",
        help="Print the known exercise names and the metric used to score each, then exit.",
    )
    args = parser.parse_args()

    if args.list_exercises:
        for name, config in EXERCISE_METRIC_MAP.items():
            print(f"{name}: {config['mode']} of {', '.join(config['fields'])}")
        return

    if not (args.video and args.exercise and args.results):
        parser.error("--video, --exercise, and --results are required unless --list-exercises is given")

    try:
        exercise_name, config = resolve_exercise(args.exercise)
    except KeyError as exc:
        logger.error(str(exc))
        sys.exit(1)

    results_path = Path(args.results)
    with open(results_path, "r") as f:
        results = json.load(f)

    per_frame = results.get("per_frame")
    if not per_frame:
        logger.error(f"No 'per_frame' data found in {results_path}")
        sys.exit(1)

    score, peak_record = find_peak_frame(per_frame, config["fields"], config["mode"])
    frame_number = peak_record["frame"]
    time_sec = peak_record["time_sec"]

    video_path = Path(args.video)
    output_path = Path(args.output) if args.output else video_path.with_name(
        f"{video_path.stem}_{exercise_name.replace(' ', '_')}_peak.png"
    )

    saved_path = extract_frame(video_path, frame_number, time_sec, output_path)

    logger.info(f"Exercise   : {exercise_name}")
    logger.info(f"Metric     : {config['mode']} of {', '.join(config['fields'])}")
    logger.info(f"Peak score : {score:.4f}")
    logger.info(f"Frame      : {int(frame_number)} (t={time_sec:.3f}s)")
    logger.info(f"Saved      : {saved_path}")


if __name__ == "__main__":
    main()
