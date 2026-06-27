#!/usr/bin/env python3
"""Export everything Dynaface can measure from a video into one CSV file.

This script processes a video frame by frame using Dynaface and writes a
per-frame CSV that includes:

- all standard Dynaface frontal/lateral metrics returned by `all_measures()`
- the full landmark set from `AnalyzeLandmarks` (`landmark-1-x` ...
  `landmark-97-y`)
- frame index and timestamp

The goal is to provide a single CSV that is as complete as possible for later
clinical reporting, QA, or downstream analysis.
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path
from typing import Any

import cv2


def _add_dynaface_paths() -> None:
    """Add the local Dynaface library and example folder to `sys.path`."""

    here = Path(__file__).resolve()
    candidates = [
        here.parents[2] / "dynaface-main" / "dynaface-lib",
        here.parents[2] / "dynaface-main" / "dynaface-lib" / "examples",
        here.parents[1] / "dynaface-main" / "dynaface-lib",
        here.parents[1] / "dynaface-main" / "dynaface-lib" / "examples",
    ]

    for candidate in candidates:
        if candidate.exists() and str(candidate) not in sys.path:
            sys.path.insert(0, str(candidate))


_add_dynaface_paths()

from dynaface import models  # noqa: E402
from dynaface.facial import AnalyzeFace  # noqa: E402
from dynaface.measures import all_measures  # noqa: E402


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Process a video with Dynaface and export a full CSV."
    )
    parser.add_argument("input_video", type=Path, help="Path to the input video")
    parser.add_argument(
        "--output-csv",
        type=Path,
        default=None,
        help="Path to the output CSV. Defaults to <video_stem>_dynaface_full.csv",
    )
    parser.add_argument(
        "--crop",
        action="store_true",
        help="Crop/zoom to the detected face while processing.",
    )
    parser.add_argument(
        "--device",
        default="detect",
        help="GPU/CPU device to use. Default: detect",
    )
    return parser.parse_args()


def open_capture(video_path: Path) -> cv2.VideoCapture:
    capture = cv2.VideoCapture(str(video_path))
    if not capture.isOpened():
        raise RuntimeError(f"Could not open video: {video_path}")
    return capture


def float_or_default(value: Any, default: float) -> float:
    try:
        if value is None:
            return default
        value = float(value)
        if value <= 0:
            return default
        return value
    except Exception:
        return default


def build_output_path(input_video: Path, output_csv: Path | None) -> Path:
    if output_csv is not None:
        return output_csv
    return input_video.with_name(f"{input_video.stem}_dynaface_full.csv")


def write_full_csv(
    input_video: Path,
    output_csv: Path,
    crop: bool,
) -> None:
    capture = open_capture(input_video)
    fps = float_or_default(capture.get(cv2.CAP_PROP_FPS), 30.0)

    measures = all_measures()
    face_for_schema: AnalyzeFace | None = None
    pupils = None
    frame_idx = 0

    output_csv.parent.mkdir(parents=True, exist_ok=True)

    try:
        with output_csv.open("w", encoding="utf-8", newline="") as f:
            writer: csv.DictWriter[str] | csv.DictWriter[Any] = None  # type: ignore[assignment]

            while True:
                ok, frame = capture.read()
                if not ok:
                    break

                frame_idx += 1
                time_sec = (frame_idx - 1) / fps
                rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

                face = AnalyzeFace(measures)
                face.load_image(rgb, crop, pupils)

                if face_for_schema is None:
                    face_for_schema = face
                    fieldnames = ["frame", "time_sec"] + face_for_schema.get_all_items()
                    writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
                    writer.writeheader()

                rec = face.analyze() or {}

                row: dict[str, Any] = {"frame": frame_idx, "time_sec": round(time_sec, 6)}
                for key in face_for_schema.get_all_items():
                    row[key] = rec.get(key, "")

                writer.writerow(row)

                if pupils is None:
                    pupils = face.get_pupils()

    finally:
        capture.release()


def main() -> int:
    args = parse_args()
    input_video = args.input_video.resolve()
    output_csv = build_output_path(input_video, args.output_csv.resolve() if args.output_csv else None)

    device = args.device
    if device == "detect":
        device = models.detect_device()

    print(f"Detected device: {device}")
    model_path = models.download_models()
    models.init_models(model_path, device)

    print(f"Input video: {input_video}")
    print(f"Output CSV: {output_csv}")
    print(f"Crop: {args.crop}")

    write_full_csv(input_video=input_video, output_csv=output_csv, crop=args.crop)

    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())