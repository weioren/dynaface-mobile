"""
dynaface_extract.py

Process one or more videos through Dynaface and output a frame-level
measurements CSV per video.

Usage:
    # Single video
    python dynaface_extract.py /path/to/video.mp4

    # Folder of videos (flat or nested)
    python dynaface_extract.py /path/to/videos/

    # Specify a custom output folder
    python dynaface_extract.py /path/to/videos/ --output /path/to/output/

    # Skip videos whose CSV already exists
    python dynaface_extract.py /path/to/videos/ --skip-existing

    # Disable face cropping
    python dynaface_extract.py /path/to/video.mp4 --no-crop
"""

import argparse
import csv
import logging
import sys
from datetime import datetime
from pathlib import Path

import cv2

from dynaface import models
from dynaface.facial import AnalyzeFace
from dynaface.measures import (
    AnalyzeBrows,
    AnalyzeDentalArea,
    AnalyzeEyeArea,
    AnalyzeFAI,
    AnalyzeIntercanthalDistance,
    AnalyzeMouthLength,
    AnalyzeOralCommissureExcursion,
    AnalyzePosition,
)

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

# Silence noisy Dynaface internals
logging.getLogger("dynaface").setLevel(logging.CRITICAL)
logging.getLogger("dynaface.facial").setLevel(logging.CRITICAL)

# ---------------------------------------------------------------------------
# Measurements to compute for every frame
# ---------------------------------------------------------------------------
MEASUREMENTS = [
    AnalyzeFAI(),
    AnalyzeOralCommissureExcursion(),
    AnalyzeBrows(),
    AnalyzeDentalArea(),
    AnalyzeEyeArea(),
    AnalyzeIntercanthalDistance(),
    AnalyzeMouthLength(),
    AnalyzePosition(),
]

VIDEO_EXTENSIONS = {".mp4", ".mov", ".avi", ".3gp", ".MP4", ".MOV", ".AVI", ".3GP"}

# Orientation options for the hardcoded setting below.
# "auto"  — detect automatically from sample frames
# "none"  — no rotation (0°)
# "90cw"  — 90° clockwise
# "180"   — 180°
# "90ccw" — 90° counter-clockwise
ORIENTATION_MAP = {
    "none":  (None,                          "no rotation"),
    "90cw":  (cv2.ROTATE_90_CLOCKWISE,       "90° clockwise"),
    "180":   (cv2.ROTATE_180,                "180°"),
    "90ccw": (cv2.ROTATE_90_COUNTERCLOCKWISE, "90° counter-clockwise"),
}


# ---------------------------------------------------------------------------
# Model initialisation
# ---------------------------------------------------------------------------
def initialize_models() -> None:
    """Download (if needed) and load Dynaface AI models."""
    logger.info("Initialising Dynaface models...")
    device = models.detect_device()
    logger.info(f"Using device: {device}")
    path = models.download_models()
    models.init_models(path, device)
    logger.info("Models initialised successfully.")


# ---------------------------------------------------------------------------
# Orientation detection
# ---------------------------------------------------------------------------
def detect_face_orientation(
    video_path: Path, analyzer: AnalyzeFace, num_sample_frames: int = 5
) -> tuple:
    """
    Try four rotations (0°, 90° CW, 180°, 90° CCW) on sample frames and
    return the one that detects a face most often.

    Returns:
        (rotation_code, rotation_name)
        rotation_code is a cv2 rotation constant, or None for no rotation.
    """
    rotations = [
        (None, "no rotation"),
        (cv2.ROTATE_90_CLOCKWISE, "90° clockwise"),
        (cv2.ROTATE_180, "180°"),
        (cv2.ROTATE_90_COUNTERCLOCKWISE, "90° counter-clockwise"),
    ]

    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        return None, "failed_to_open"

    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    if total_frames <= num_sample_frames:
        sample_indices = list(range(total_frames))
    else:
        start = max(1, total_frames // 10)
        end = min(total_frames - 1, total_frames * 9 // 10)
        step = max(1, (end - start) // (num_sample_frames - 1))
        sample_indices = [start + i * step for i in range(num_sample_frames)]

    scores = [0] * len(rotations)

    for idx in sample_indices:
        cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
        ret, frame = cap.read()
        if not ret:
            continue
        for rot_idx, (rotation_code, _) in enumerate(rotations):
            try:
                test = frame.copy()
                if rotation_code is not None:
                    test = cv2.rotate(test, rotation_code)
                image_rgb = cv2.cvtColor(test, cv2.COLOR_BGR2RGB)
                analyzer.load_image(image_rgb, crop=True, pupils=None)
                if not analyzer.is_no_face():
                    scores[rot_idx] += 1
            except Exception:
                continue

    cap.release()

    best_idx = max(range(len(scores)), key=lambda i: scores[i])
    if scores[best_idx] == 0:
        return None, "detection_failed"

    return rotations[best_idx]


# ---------------------------------------------------------------------------
# Single-video processing
# ---------------------------------------------------------------------------
def process_video(video_path: Path, output_csv: Path, crop: bool = True, forced_rotation=None) -> bool:
    """
    Run Dynaface on every frame of *video_path* and write results to *output_csv*.

    Returns True if at least one frame was successfully analysed.
    forced_rotation: a (rotation_code, rotation_name) tuple to skip auto-detection,
                     or None to auto-detect.
    """
    analyzer = AnalyzeFace(MEASUREMENTS)

    if forced_rotation is not None:
        rotation_code, rotation_name = forced_rotation
        logger.info(f"  Orientation: {rotation_name} (hardcoded)")
    else:
        # Auto-detect orientation
        logger.info(f"  Detecting orientation for {video_path.name}...")
        rotation_code, rotation_name = detect_face_orientation(video_path, analyzer)

        if rotation_name == "failed_to_open":
            logger.error(f"  Could not open video: {video_path}")
            return False

        if rotation_name == "detection_failed":
            logger.warning(
                f"  No face detected in any orientation — proceeding with no rotation."
            )
            rotation_code = None
            rotation_name = "no rotation (fallback)"

        logger.info(f"  Orientation: {rotation_name}")

    # Open video
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        logger.error(f"  Could not open video: {video_path}")
        return False

    frame_rate = cap.get(cv2.CAP_PROP_FPS) or 0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    logger.info(
        f"  {total_frames} frames @ {frame_rate:.1f} fps — writing to {output_csv.name}"
    )

    output_csv.parent.mkdir(parents=True, exist_ok=True)

    csv_file = open(output_csv, "w", newline="")
    csv_writer = None
    frame_num = 0
    successful_frames = 0
    pupils = None

    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                break

            frame_num += 1

            try:
                if rotation_code is not None:
                    frame = cv2.rotate(frame, rotation_code)

                image_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                analyzer.load_image(image_rgb, crop=crop, pupils=pupils)

                if analyzer.is_no_face():
                    continue

                measurements = analyzer.analyze()
                if measurements is None:
                    continue

                measurements["frame"] = frame_num
                measurements["time_sec"] = (
                    round(frame_num / frame_rate, 3) if frame_rate > 0 else 0
                )

                if csv_writer is None:
                    fieldnames = ["frame", "time_sec"] + [
                        k for k in measurements if k not in ("frame", "time_sec")
                    ]
                    csv_writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
                    csv_writer.writeheader()

                csv_writer.writerow(measurements)

                if pupils is None:
                    pupils = analyzer.get_pupils()

                successful_frames += 1

            except Exception:
                continue

    finally:
        cap.release()
        csv_file.close()

    rate = (successful_frames / frame_num * 100) if frame_num else 0
    logger.info(
        f"  Face detected in {successful_frames}/{frame_num} frames ({rate:.1f}%)"
    )

    return successful_frames > 0


# ---------------------------------------------------------------------------
# Input discovery
# ---------------------------------------------------------------------------
def collect_videos(input_path: Path) -> list[Path]:
    """Return a sorted list of video files under *input_path* (file or folder)."""
    if input_path.is_file():
        if input_path.suffix in VIDEO_EXTENSIONS:
            return [input_path]
        logger.error(f"File does not look like a video: {input_path}")
        return []

    videos = []
    for ext in VIDEO_EXTENSIONS:
        videos.extend(input_path.rglob(f"*{ext}"))
    return sorted(set(videos))


# ---------------------------------------------------------------------------
# Orientation verification (interactive)
# ---------------------------------------------------------------------------
def verify_orientations(videos: list[Path]) -> dict:
    """
    For each video, display a 2x2 grid showing a sample frame in all four
    orientations and ask the user to press 1–4 to pick the correct one.

    Returns a dict mapping Path -> (rotation_code, rotation_name).
    """
    ROTATIONS = [
        (None,                            "No rotation (0 deg)"),
        (cv2.ROTATE_90_CLOCKWISE,         "90 deg clockwise"),
        (cv2.ROTATE_180,                  "180 deg"),
        (cv2.ROTATE_90_COUNTERCLOCKWISE,  "90 deg counter-clockwise"),
    ]
    TILE_W, TILE_H = 480, 360

    print("\n" + "=" * 60)
    print("ORIENTATION VERIFICATION")
    print("For each video a preview window will open showing the")
    print("same frame in all four orientations.")
    print("Press 1, 2, 3, or 4 in the window to choose the correct one.")
    print("=" * 60 + "\n")

    import numpy as np

    results = {}

    WINDOW_NAME = "Select Orientation (press 1, 2, 3, or 4)"

    for video_path in videos:
        cap = cv2.VideoCapture(str(video_path))
        if not cap.isOpened():
            logger.warning(f"  Could not open {video_path.name} for preview — defaulting to no rotation.")
            results[video_path] = (None, "no rotation (fallback)")
            continue

        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        cap.set(cv2.CAP_PROP_POS_FRAMES, max(0, total_frames // 2))
        ret, frame = cap.read()
        cap.release()

        if not ret:
            logger.warning(f"  Could not read frame from {video_path.name} — defaulting to no rotation.")
            results[video_path] = (None, "no rotation (fallback)")
            continue

        tiles = []
        for i, (rot_code, rot_name) in enumerate(ROTATIONS, 1):
            img = frame.copy()
            if rot_code is not None:
                img = cv2.rotate(img, rot_code)
            img = cv2.resize(img, (TILE_W, TILE_H))
            # Black bar label at the top of each tile
            cv2.rectangle(img, (0, 0), (TILE_W, 45), (0, 0, 0), -1)
            cv2.putText(img, f"[{i}] {rot_name}", (10, 30),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.75, (255, 255, 255), 2)
            tiles.append(img)

        top    = cv2.hconcat([tiles[0], tiles[1]])
        bottom = cv2.hconcat([tiles[2], tiles[3]])
        grid   = cv2.vconcat([top, bottom])

        # Instruction bar across the full width at the top
        bar_h = 50
        bar = np.zeros((bar_h, TILE_W * 2, 3), dtype="uint8")
        instruction = "Please press the number on your keyboard that corresponds to the correct orientation."
        font, scale, thickness = cv2.FONT_HERSHEY_SIMPLEX, 0.6, 1
        (text_w, text_h), _ = cv2.getTextSize(instruction, font, scale, thickness)
        text_x = max(0, (TILE_W * 2 - text_w) // 2)
        text_y = (bar_h + text_h) // 2
        cv2.putText(bar, instruction, (text_x, text_y), font, scale, (255, 255, 255), thickness)
        grid = cv2.vconcat([bar, grid])

        cv2.imshow(WINDOW_NAME, grid)

        choice = None
        while choice is None:
            key = cv2.waitKey(0) & 0xFF
            if key in (ord('1'), ord('2'), ord('3'), ord('4')):
                choice = key - ord('1')

        rot_code, rot_name = ROTATIONS[choice]
        logger.info(f"  {video_path.name}: '{rot_name}' selected.")
        results[video_path] = (rot_code, rot_name)

    cv2.destroyAllWindows()
    cv2.waitKey(1)

    return results


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract frame-level Dynaface metrics from video(s) to CSV.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "input",
        nargs="?",
        default=None,
        help="Path to a single video file or a folder containing videos.",
    )
    parser.add_argument(
        "--output",
        "-o",
        default=None,
        help=(
            "Output folder for CSV files. Defaults to a folder called "
            "'dynaface_output' next to the input. For a single video the CSV "
            "is placed directly in this folder."
        ),
    )
    parser.add_argument(
        "--skip-existing",
        action="store_true",
        help="Skip videos that already have a corresponding CSV.",
    )
    parser.add_argument(
        "--no-crop",
        action="store_true",
        help="Disable face cropping/zooming during analysis.",
    )

    args = parser.parse_args()

    # HARDCODED DEFAULTS — edit these to change behaviour without CLI flags
    args.input = "/Users/orenw/Documents/Dynaface Scripts/Test"
    args.output = "/Users/orenw/Documents/Dynaface Scripts/Test"
    args.skip_existing = True
    args.no_crop = True
    args.orientation = "none"  # Options: "auto", "none", "90cw", "180", "90ccw"
    args.verify_orientation = False  # True: show preview window per video and ask user to pick orientation

    input_path = Path(args.input).resolve()

    if not input_path.exists():
        logger.error(f"Input path does not exist: {input_path}")
        sys.exit(1)

    # Determine output root
    if args.output:
        output_root = Path(args.output).resolve()
    else:
        output_root = Path(__file__).parent / "dynaface_output"

    crop = not args.no_crop
    forced_rotation = None if args.orientation == "auto" else ORIENTATION_MAP.get(args.orientation, (None, "no rotation"))

    print("\n" + "=" * 60)
    print("DYNAFACE EXTRACT")
    print("=" * 60)
    print(f"Start time : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Input      : {input_path}")
    print(f"Output     : {output_root}")
    print(f"Crop face  : {crop}")
    print(f"Verify ori : {args.verify_orientation}")
    print("=" * 60 + "\n")

    initialize_models()

    videos = collect_videos(input_path)
    if not videos:
        logger.error("No video files found.")
        sys.exit(1)

    logger.info(f"Found {len(videos)} video(s).")

    # If verify_orientation is on, ask the user to confirm each video's orientation
    # before any processing starts. Otherwise every video uses the hardcoded value.
    if args.verify_orientation:
        orientation_per_video = verify_orientations(videos)
    else:
        orientation_per_video = {}

    processed, failed, skipped = 0, 0, 0
    failed_list = []

    for i, video_path in enumerate(videos, 1):
        logger.info(f"\n[{i}/{len(videos)}] {video_path.name}")

        # Build the output CSV path, preserving relative structure when input is a folder
        if input_path.is_dir():
            rel = video_path.relative_to(input_path)
            output_csv = output_root / rel.with_suffix(".csv")
        else:
            output_csv = output_root / video_path.with_suffix(".csv").name

        if args.skip_existing and output_csv.exists():
            logger.info(f"  Skipping — CSV already exists: {output_csv}")
            skipped += 1
            continue

        video_rotation = orientation_per_video.get(video_path, forced_rotation)
        success = process_video(video_path, output_csv, crop=crop, forced_rotation=video_rotation)

        if success:
            logger.info(f"  Saved: {output_csv}")
            processed += 1
        else:
            logger.warning(f"  Failed: {video_path.name}")
            failed += 1
            failed_list.append(video_path)

    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"Total found   : {len(videos)}")
    print(f"Processed     : {processed}")
    print(f"Skipped       : {skipped}")
    print(f"Failed        : {failed}")
    if failed_list:
        print("\nFailed videos:")
        for p in failed_list:
            print(f"  ✗ {p}")
    print(f"\nEnd time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 60)


if __name__ == "__main__":
    main()
