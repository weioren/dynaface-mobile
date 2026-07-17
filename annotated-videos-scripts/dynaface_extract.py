"""
dynaface_extract.py

Process one or more videos through Dynaface and output an annotated video
per input video.

Usage:
    # Single video
    python dynaface_extract.py /path/to/video.mp4

    # Folder of videos (flat or nested)
    python dynaface_extract.py /path/to/videos/

    # Specify a custom output folder
    python dynaface_extract.py /path/to/videos/ --output /path/to/output/

    # Skip videos whose annotated video already exists
    python dynaface_extract.py /path/to/videos/ --skip-existing

    # Disable face cropping
    python dynaface_extract.py /path/to/video.mp4 --no-crop
"""

import argparse
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
    #AnalyzeOralCommissureExcursion(),
    #AnalyzeBrows(),
    AnalyzeDentalArea(),
    AnalyzeEyeArea(),
    #AnalyzeIntercanthalDistance(),
    #AnalyzeMouthLength(),
    #AnalyzePosition(),
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


def format_metric(value) -> str:
    if value is None:
        return "n/a"
    try:
        return f"{float(value):.4f}"
    except Exception:
        return str(value)


def overlay_lines(face: AnalyzeFace, lines: list[str], start_xy=(10, 30), line_spacing: int = 22) -> None:
    x, y = start_xy
    for idx, line in enumerate(lines):
        face.write_text((x, y + idx * line_spacing), line)


def selected_measurement_lines(measurements: dict, frame_num: int, frame_rate: float) -> list[str]:
    time_sec = round(frame_num / frame_rate, 3) if frame_rate > 0 else 0
    return [
        f"Frame {frame_num}, {time_sec} sec",
        f"FAI: {format_metric(measurements.get('fai'))}",
        f"Mouth area: {format_metric(measurements.get('dental_area'))}",
        f"Mouth area L/R: {format_metric(measurements.get('dental_left'))} / {format_metric(measurements.get('dental_right'))}",
        f"Eye area L/R: {format_metric(measurements.get('eye.left'))} / {format_metric(measurements.get('eye.right'))}",
        f"Eye area ratio: {format_metric(measurements.get('eye.ratio'))}",
    ]


def analyze_measurements_no_render(face: AnalyzeFace) -> dict:
    """
    Compute enabled measurement values without drawing the library's default
    per-measure text overlays, so we can render a single clean metrics layer.
    """
    if not face.landmarks:
        return {}

    face.width = face.render_img.shape[1]
    face.height = face.render_img.shape[0]
    m = face.calc_text_size("W")
    face.analyze_x = int(m[0][0] * 0.25)
    face.analyze_y = int(m[0][1] * 1.5)

    result = {}

    def _run_with_suppressed_text(calc_obj):
        original_write_text = getattr(face, "write_text", None)
        original_write_text_sq = getattr(face, "write_text_sq", None)

        def _noop(*args, **kwargs):
            return None

        try:
            if original_write_text is not None:
                face.write_text = _noop
            if original_write_text_sq is not None:
                face.write_text_sq = _noop
            return calc_obj.calc(face, render=True)
        finally:
            if original_write_text is not None:
                face.write_text = original_write_text
            if original_write_text_sq is not None:
                face.write_text_sq = original_write_text_sq

    for calc in face.measures:
        if not getattr(calc, "enabled", False):
            continue

        try:
            # Keep visual area shading for eye + mouth(dental) while suppressing
            # library text, so only our custom single-layer text is shown.
            if calc.__class__.__name__ in {"AnalyzeDentalArea", "AnalyzeEyeArea"}:
                result.update(_run_with_suppressed_text(calc))
            else:
                result.update(calc.calc(face, render=False))
        except TypeError:
            # Backward compatibility for measures that don't accept render kwarg.
            result.update(calc.calc(face))

    return result


def smooth_points(prev_points, curr_points, alpha: float = 0.35):
    if not prev_points or not curr_points or len(prev_points) != len(curr_points):
        return curr_points

    out = []
    for (px, py), (cx, cy) in zip(prev_points, curr_points):
        sx = int(round((1.0 - alpha) * px + alpha * cx))
        sy = int(round((1.0 - alpha) * py + alpha * cy))
        out.append((sx, sy))
    return out


def smooth_pupils(prev_pupils, curr_pupils, alpha: float = 0.2):
    if curr_pupils is None:
        return prev_pupils
    if prev_pupils is None:
        return curr_pupils

    try:
        l_prev, r_prev = prev_pupils
        l_curr, r_curr = curr_pupils
        l_sm = (
            (1.0 - alpha) * l_prev[0] + alpha * l_curr[0],
            (1.0 - alpha) * l_prev[1] + alpha * l_curr[1],
        )
        r_sm = (
            (1.0 - alpha) * r_prev[0] + alpha * r_curr[0],
            (1.0 - alpha) * r_prev[1] + alpha * r_curr[1],
        )
        return (l_sm, r_sm)
    except Exception:
        return curr_pupils


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
def process_video(
    video_path: Path,
    output_video: Path,
    crop: bool = True,
    forced_rotation=None,
    frame_step: int = 1,
    measures: list | None = None,
    records_out: list | None = None,
) -> bool:
    """
    Run Dynaface on every frame of *video_path* and write an annotated video to *output_video*.

    Returns True if at least one frame was successfully analysed.
    forced_rotation: a (rotation_code, rotation_name) tuple to skip auto-detection,
                     or None to auto-detect.
    measures: enabled measures to compute (defaults to the module-level MEASUREMENTS
              subset used for the annotated-video overlay).
    records_out: if provided, each frame's raw measurement dict (frame/time_sec plus
                 whatever `measures` produced) is appended to this list, letting a
                 caller collect per-frame metrics from this same pass.
    """
    analyzer = AnalyzeFace(measures if measures is not None else MEASUREMENTS)

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
        f"  {total_frames} frames @ {frame_rate:.1f} fps — writing to {output_video.name}"
    )

    frame_num = 0
    successful_frames = 0
    pupils = None
    prev_landmarks = None
    writer = None
    frame_step = max(1, frame_step)
    output_fps = (
        (frame_rate / frame_step) if frame_rate and frame_rate > 0 else (30.0 / frame_step)
    )
    output_fps = max(1.0, output_fps)

    output_video.parent.mkdir(parents=True, exist_ok=True)
    if output_video.exists():
        output_video.unlink()

    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                break

            frame_num += 1
            if frame_step > 1 and (frame_num % frame_step) != 0:
                continue

            try:
                if rotation_code is not None:
                    frame = cv2.rotate(frame, rotation_code)

                image_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                analyzer.load_image(image_rgb, crop=crop, pupils=pupils)

                if analyzer.is_no_face():
                    continue

                if analyzer.landmarks:
                    analyzer.landmarks = smooth_points(prev_landmarks, analyzer.landmarks, alpha=0.35)
                    prev_landmarks = list(analyzer.landmarks)

                measurements = analyze_measurements_no_render(analyzer)
                if not measurements:
                    continue

                measurements["frame"] = frame_num
                measurements["time_sec"] = (
                    round(frame_num / frame_rate, 3) if frame_rate > 0 else 0
                )

                if records_out is not None:
                    records_out.append(dict(measurements))

                overlay_lines(
                    analyzer,
                    selected_measurement_lines(measurements, frame_num, frame_rate),
                )
                analyzer.draw_landmarks(numbers=False)

                frame_bgr = cv2.cvtColor(analyzer.render_img, cv2.COLOR_RGB2BGR)
                if writer is None:
                    h, w = frame_bgr.shape[:2]
                    writer = cv2.VideoWriter(
                        str(output_video),
                        cv2.VideoWriter_fourcc(*"mp4v"),
                        output_fps,
                        (w, h),
                    )
                writer.write(frame_bgr)

                if pupils is None:
                    pupils = analyzer.get_pupils()
                else:
                    pupils = smooth_pupils(pupils, analyzer.get_pupils(), alpha=0.2)

                successful_frames += 1

            except Exception:
                continue

    finally:
        cap.release()
        if writer is not None:
            writer.release()

    if successful_frames == 0:
        logger.warning("  No frames were successfully analysed.")
        return False

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
            "Output folder for annotated video files. Defaults to a folder called "
            "'dynaface_output' next to the input. For a single video the MP4 "
            "is placed directly in this folder."
        ),
    )
    parser.add_argument(
        "--skip-existing",
        action="store_true",
        help="Skip videos that already have a corresponding annotated video.",
    )
    parser.add_argument(
        "--no-crop",
        action="store_true",
        help="Disable face cropping/zooming during analysis.",
    )
    parser.add_argument(
        "--frame-step",
        type=int,
        default=1,
        help="Process every Nth frame (1 = all frames, 2 = every other frame, etc.).",
    )

    args = parser.parse_args()

    # HARDCODED DEFAULTS — edit these to change behaviour without CLI flags
    args.input = r"C:\Users\kimak\Documents\Quick Access\JHU\Dynaface\input"
    args.output = r"C:\Users\kimak\Documents\Quick Access\JHU\Dynaface\output"
    args.skip_existing = True
    args.no_crop = True
    args.frame_step = 1
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

        # Build the output video path, preserving relative structure when input is a folder
        if input_path.is_dir():
            rel = video_path.relative_to(input_path)
            output_video = output_root / rel.parent / f"{rel.stem}_annotated.mp4"
        else:
            output_video = output_root / f"{video_path.stem}_annotated.mp4"

        if args.skip_existing and output_video.exists():
            logger.info(f"  Skipping — annotated video already exists: {output_video}")
            skipped += 1
            continue

        video_rotation = orientation_per_video.get(video_path, forced_rotation)
        success = process_video(
            video_path,
            output_video,
            crop=crop,
            forced_rotation=video_rotation,
            frame_step=args.frame_step,
        )

        if success:
            logger.info(f"  Saved: {output_video}")
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
