#!/usr/bin/env python3
"""Generate a clinical facial function report from Dynaface CSV output.

This tool is designed to work with Dynaface CSV exports, especially:
- Landmark CSV produced by AnalyzeLandmarks (landmark-1-x ... landmark-97-y)
- Measurement CSV produced by VideoToVideo.dump_data (fai, oce.l, eye.left, etc.)

The script creates:
- a per-frame metrics CSV
- a Markdown clinical report
- lightweight SVG charts (global score timeline and synkinesis heatmap)
- an optional pre/post comparison report

Only the Python standard library is used.
"""

from __future__ import annotations

import argparse
import csv
import dataclasses
import json
import math
import re
import statistics
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from html import escape
from pathlib import Path
from typing import Any, Iterable


LANDMARK_RE = re.compile(r"^landmark[-_]?([0-9]+)[-_](x|y)$", re.IGNORECASE)
FRAME_RE = re.compile(r"^frame$|^frame_num$|^frame_number$", re.IGNORECASE)
TIME_RE = re.compile(r"^time$|^time_sec$|^timestamp$", re.IGNORECASE)

# Landmark indices validated against Dynaface code paths:
# - FAI: landmarks[64], [76], [68], [82]
# - Oral commissure excursion: landmarks[76], [82], [85]
# - Eye area: landmarks[60:68] and [68:76]
# - Dental area: landmarks[88:96]
# - Nose frontal: landmarks[52:60], brow anchors: landmarks[35], [44]
# These indices are therefore used here to remain consistent with dynaface-main.
RIGHT_EYE_POLY = [60, 61, 62, 63, 64, 65, 66, 67]
LEFT_EYE_POLY = [68, 69, 70, 71, 72, 73, 74, 75]
MOUTH_POLY = [88, 89, 90, 91, 92, 93, 94, 95]
RIGHT_EYE_UPPER = [61, 62, 63]
RIGHT_EYE_LOWER = [65, 66, 67]
LEFT_EYE_UPPER = [69, 70, 71]
LEFT_EYE_LOWER = [73, 74, 75]
RIGHT_BROW = [35, 36, 37, 38, 39, 40]
LEFT_BROW = [44, 45, 46, 47, 48, 49]
NOSE_LEFT = 55
NOSE_RIGHT = 59
NOSE_BRIDGE = 52
NOSE_BASE = 53
NOSE_TIP = 54
MOUTH_RIGHT = 76
MOUTH_LEFT = 82
MOUTH_CENTER = 85


@dataclass
class FrameRecord:
    frame: int
    time_sec: float
    landmarks: dict[int, tuple[float, float]]
    measures: dict[str, float]


@dataclass
class Metadata:
    patient_id: str = ""
    patient_name: str = ""
    diagnosis: str = ""
    functional_status: str = ""
    side_affected: str = ""
    date_of_injury: str = ""
    interventions: str = ""
    surgery: str = ""
    botox: str = ""
    notes: str = ""
    events: list[dict[str, Any]] = dataclasses.field(default_factory=list)


# ---------------------------------------------------------------------------
# Generic helpers
# ---------------------------------------------------------------------------

def clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def safe_mean(values: Iterable[float]) -> float:
    values = [v for v in values if v is not None]
    return float(statistics.fmean(values)) if values else 0.0


def safe_median(values: Iterable[float]) -> float:
    values = [v for v in values if v is not None]
    return float(statistics.median(values)) if values else 0.0


def dist(p1: tuple[float, float], p2: tuple[float, float]) -> float:
    return float(math.hypot(p2[0] - p1[0], p2[1] - p1[1]))


def polygon_area(points: list[tuple[float, float]]) -> float:
    if len(points) < 3:
        return 0.0
    area = 0.0
    for i in range(len(points)):
        x1, y1 = points[i]
        x2, y2 = points[(i + 1) % len(points)]
        area += x1 * y2 - x2 * y1
    return abs(area) / 2.0


def mean_y(points: list[tuple[float, float]]) -> float:
    return safe_mean(p[1] for p in points)


def mean_x(points: list[tuple[float, float]]) -> float:
    return safe_mean(p[0] for p in points)


def velocity(series: list[float], times: list[float]) -> list[float]:
    if len(series) < 2:
        return [0.0 for _ in series]
    out = [0.0]
    for i in range(1, len(series)):
        dt = max(times[i] - times[i - 1], 1e-9)
        out.append((series[i] - series[i - 1]) / dt)
    return out


def normalize_by_n(value: float, n: float, power: int = 1) -> float:
    if n <= 0:
        return 0.0
    return value / (n**power)


# ---------------------------------------------------------------------------
# Input parsing
# ---------------------------------------------------------------------------

def load_metadata(path: Path | None) -> Metadata:
    if not path:
        return Metadata()
    payload = json.loads(path.read_text(encoding="utf-8"))
    return Metadata(
        patient_id=str(payload.get("patient_id", "")),
        patient_name=str(payload.get("patient_name", "")),
        diagnosis=str(payload.get("diagnosis", "")),
        functional_status=str(payload.get("functional_status", "")),
        side_affected=str(payload.get("side_affected", "")),
        date_of_injury=str(payload.get("date_of_injury", "")),
        interventions=str(payload.get("interventions", "")),
        surgery=str(payload.get("surgery", "")),
        botox=str(payload.get("botox", "")),
        notes=str(payload.get("notes", "")),
        events=list(payload.get("events", [])),
    )


def read_csv_rows(csv_path: Path) -> list[dict[str, str]]:
    with csv_path.open("r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def parse_float(value: Any) -> float | None:
    if value is None:
        return None
    text = str(value).strip()
    if text == "":
        return None
    try:
        return float(text)
    except ValueError:
        return None


def detect_frame_column(row: dict[str, str]) -> str | None:
    for key in row.keys():
        if FRAME_RE.match(key):
            return key
    return None


def detect_time_column(row: dict[str, str]) -> str | None:
    for key in row.keys():
        if TIME_RE.match(key):
            return key
    return None


def parse_landmarks(row: dict[str, str]) -> dict[int, tuple[float, float]]:
    xs: dict[int, float] = {}
    ys: dict[int, float] = {}
    for key, value in row.items():
        m = LANDMARK_RE.match(key)
        if not m:
            continue
        idx = int(m.group(1))
        axis = m.group(2).lower()
        num = parse_float(value)
        if num is None:
            continue
        if axis == "x":
            xs[idx] = num
        else:
            ys[idx] = num
    landmarks: dict[int, tuple[float, float]] = {}
    for idx in sorted(set(xs) & set(ys)):
        landmarks[idx] = (xs[idx], ys[idx])
    return landmarks


def parse_measurements(row: dict[str, str]) -> dict[str, float]:
    out: dict[str, float] = {}
    for key, value in row.items():
        if LANDMARK_RE.match(key):
            continue
        if FRAME_RE.match(key) or TIME_RE.match(key):
            continue
        num = parse_float(value)
        if num is not None:
            out[key] = num
    return out


def load_records(csv_path: Path) -> tuple[list[FrameRecord], bool, bool]:
    rows = read_csv_rows(csv_path)
    if not rows:
        raise ValueError(f"Input CSV is empty: {csv_path}")

    frame_col = detect_frame_column(rows[0])
    time_col = detect_time_column(rows[0])

    records: list[FrameRecord] = []
    has_landmarks = False
    has_measures = False

    for i, row in enumerate(rows):
        frame = int(parse_float(row.get(frame_col, i)) or i) if frame_col else i
        time_sec = parse_float(row.get(time_col, i)) if time_col else None
        if time_sec is None:
            time_sec = float(i)

        landmarks = parse_landmarks(row)
        measures = parse_measurements(row)
        has_landmarks = has_landmarks or bool(landmarks)
        has_measures = has_measures or bool(measures)

        records.append(
            FrameRecord(
                frame=frame,
                time_sec=float(time_sec),
                landmarks=landmarks,
                measures=measures,
            )
        )

    if not records:
        raise ValueError(f"No usable rows found in CSV: {csv_path}")

    return records, has_landmarks, has_measures


# ---------------------------------------------------------------------------
# Landmark extraction
# ---------------------------------------------------------------------------

def poly_points(landmarks: dict[int, tuple[float, float]], indices: list[int]) -> list[tuple[float, float]]:
    return [landmarks[i] for i in indices if i in landmarks]


def center_point(points: list[tuple[float, float]]) -> tuple[float, float]:
    return (mean_x(points), mean_y(points))


def get_or_none(landmarks: dict[int, tuple[float, float]], idx: int) -> tuple[float, float] | None:
    return landmarks.get(idx)


def split_by_proximity_to_midline(
    indices: list[int], landmarks: dict[int, tuple[float, float]], midline_x: float, near_count: int
) -> tuple[list[int], list[int]]:
    """Split a side's landmark indices into the N nearest / farthest from the midline.

    Determined geometrically from rest-frame positions rather than assuming a fixed
    landmark-ordering convention (medial/lateral order is not guaranteed by the model).
    """
    present = [i for i in indices if i in landmarks]
    ordered = sorted(present, key=lambda i: abs(landmarks[i][0] - midline_x))
    return ordered[:near_count], ordered[near_count:]


def classify_left_right(
    indices: list[int], landmarks: dict[int, tuple[float, float]], midline_x: float, right_side_is_smaller_x: bool
) -> tuple[list[int], list[int]]:
    """Split landmark indices into (left, right) groups by x position at rest.

    Sidedness is anchored to MOUTH_RIGHT/MOUTH_LEFT (already-validated named landmarks)
    rather than assumed, so it stays correct regardless of which side has smaller x.
    """
    left: list[int] = []
    right: list[int] = []
    for i in indices:
        if i not in landmarks:
            continue
        is_smaller = landmarks[i][0] < midline_x
        (right if is_smaller == right_side_is_smaller_x else left).append(i)
    return left, right


# ---------------------------------------------------------------------------
# Metric computation
# ---------------------------------------------------------------------------

def compute_landmark_metrics(records: list[FrameRecord], metadata: Metadata, rest_index: int = 0) -> list[dict[str, float]]:
    rest_index = max(0, min(rest_index, len(records) - 1))
    rest = records[rest_index]
    if len(rest.landmarks) < 96:
        raise ValueError(
            "Landmark CSV must include Dynaface AnalyzeLandmarks output with landmark-1-x ... landmark-97-y columns."
        )

    rest_landmarks = rest.landmarks

    # Reference facial size N: use intercanthal distance from Dynaface landmark convention.
    n = dist(rest_landmarks[64], rest_landmarks[68]) if 64 in rest_landmarks and 68 in rest_landmarks else 0.0
    if n <= 0:
        n = 1.0

    rows: list[dict[str, float]] = []

    # Baseline values.
    rest_eye_r = polygon_area(poly_points(rest_landmarks, RIGHT_EYE_POLY))
    rest_eye_l = polygon_area(poly_points(rest_landmarks, LEFT_EYE_POLY))
    rest_mouth_area = polygon_area(poly_points(rest_landmarks, MOUTH_POLY))
    rest_brow_y = safe_mean([rest_landmarks[i][1] for i in RIGHT_BROW + LEFT_BROW if i in rest_landmarks])
    rest_alar = safe_mean([rest_landmarks[i][x] for i, x in [(NOSE_LEFT, 0), (NOSE_RIGHT, 0)] if i in rest_landmarks])
    rest_mouth_center = rest_landmarks.get(MOUTH_CENTER, rest_landmarks.get(MOUTH_RIGHT, (0.0, 0.0)))
    rest_eye_center_l = center_point(poly_points(rest_landmarks, LEFT_EYE_POLY))
    rest_eye_center_r = center_point(poly_points(rest_landmarks, RIGHT_EYE_POLY))
    rest_x_midline = mean_x([rest_eye_center_l, rest_eye_center_r])

    # Per-side brow medial/lateral subsets (nearest/farthest 3 points to the midline),
    # determined geometrically at rest rather than assuming a fixed landmark order.
    BROW_MEDIAL_R, BROW_LATERAL_R = split_by_proximity_to_midline(RIGHT_BROW, rest_landmarks, rest_x_midline, 3)
    BROW_MEDIAL_L, BROW_LATERAL_L = split_by_proximity_to_midline(LEFT_BROW, rest_landmarks, rest_x_midline, 3)

    # Upper-lip subset of the mouth polygon (points above its mean y at rest), split
    # left/right of the midline with sidedness anchored to MOUTH_RIGHT/MOUTH_LEFT.
    mouth_rest_points = poly_points(rest_landmarks, MOUTH_POLY)
    mouth_rest_mean_y = mean_y(mouth_rest_points) if mouth_rest_points else 0.0
    upper_lip_idx = [i for i in MOUTH_POLY if i in rest_landmarks and rest_landmarks[i][1] <= mouth_rest_mean_y] or list(MOUTH_POLY)
    right_side_is_smaller_x = rest_landmarks.get(MOUTH_RIGHT, (rest_x_midline, 0.0))[0] <= rest_landmarks.get(MOUTH_LEFT, (rest_x_midline, 0.0))[0]
    UPPER_LIP_L, UPPER_LIP_R = classify_left_right(upper_lip_idx, rest_landmarks, rest_x_midline, right_side_is_smaller_x)

    # Midface-proxy region (#26 mouth-polygon proxy), split left/right of the midline
    # the same way as the upper-lip subset, just over the full MOUTH_POLY.
    MIDFACE_L, MIDFACE_R = classify_left_right(MOUTH_POLY, rest_landmarks, rest_x_midline, right_side_is_smaller_x)

    # Eye closure reference apertures.
    rest_aperture_r = safe_mean([rest_landmarks[i][1] for i in RIGHT_EYE_UPPER if i in rest_landmarks]) - safe_mean([rest_landmarks[i][1] for i in RIGHT_EYE_LOWER if i in rest_landmarks])
    rest_aperture_l = safe_mean([rest_landmarks[i][1] for i in LEFT_EYE_UPPER if i in rest_landmarks]) - safe_mean([rest_landmarks[i][1] for i in LEFT_EYE_LOWER if i in rest_landmarks])
    rest_aperture_r = abs(rest_aperture_r) or 1.0
    rest_aperture_l = abs(rest_aperture_l) or 1.0

    # Global time-series vectors.
    eye_aperture_r_series: list[float] = []
    eye_aperture_l_series: list[float] = []
    eye_area_r_series: list[float] = []
    eye_area_l_series: list[float] = []
    mouth_area_series: list[float] = []
    smile_magnitude_series: list[float] = []
    brow_elev_series: list[float] = []
    alar_series: list[float] = []
    global_score_series: list[float] = []

    for rec in records:
        lm = rec.landmarks
        row: dict[str, float] = {"frame": float(rec.frame), "time_sec": float(rec.time_sec)}

        # FAI (validated from dynaface measures_frontal.py)
        fai = 0.0
        if 64 in lm and 76 in lm and 68 in lm and 82 in lm:
            d1 = dist(lm[64], lm[76])
            d2 = dist(lm[68], lm[82])
            fai = abs(d1 - d2)
        row["fai"] = normalize_by_n(fai, n)

        # Eye module: aperture, closure completeness, area, symmetry.
        r_ap = abs(safe_mean([lm[i][1] for i in RIGHT_EYE_UPPER if i in lm]) - safe_mean([lm[i][1] for i in RIGHT_EYE_LOWER if i in lm]))
        l_ap = abs(safe_mean([lm[i][1] for i in LEFT_EYE_UPPER if i in lm]) - safe_mean([lm[i][1] for i in LEFT_EYE_LOWER if i in lm]))
        eye_aperture_r_series.append(r_ap)
        eye_aperture_l_series.append(l_ap)
        row["eye_aperture_r"] = normalize_by_n(r_ap, n)
        row["eye_aperture_l"] = normalize_by_n(l_ap, n)
        row["eye_closure_completeness_r"] = clamp(1.0 - (r_ap / rest_aperture_r))
        row["eye_closure_completeness_l"] = clamp(1.0 - (l_ap / rest_aperture_l))

        eye_area_r = polygon_area(poly_points(lm, RIGHT_EYE_POLY))
        eye_area_l = polygon_area(poly_points(lm, LEFT_EYE_POLY))
        eye_area_r_series.append(eye_area_r)
        eye_area_l_series.append(eye_area_l)
        row["eye_area_r"] = normalize_by_n(eye_area_r, n, power=2)
        row["eye_area_l"] = normalize_by_n(eye_area_l, n, power=2)
        row["eye_ratio"] = (eye_area_l / eye_area_r) if eye_area_r else 0.0
        row["eye_diff"] = normalize_by_n(abs(eye_area_l - eye_area_r), n, power=2)

        # Upper vs lower eyelid contribution (from eye aperture change vs rest).
        upper_r = abs(safe_mean([rest_landmarks[i][1] for i in RIGHT_EYE_UPPER if i in rest_landmarks]) - safe_mean([lm[i][1] for i in RIGHT_EYE_UPPER if i in lm]))
        lower_r = abs(safe_mean([lm[i][1] for i in RIGHT_EYE_LOWER if i in lm]) - safe_mean([rest_landmarks[i][1] for i in RIGHT_EYE_LOWER if i in rest_landmarks]))
        upper_l = abs(safe_mean([rest_landmarks[i][1] for i in LEFT_EYE_UPPER if i in rest_landmarks]) - safe_mean([lm[i][1] for i in LEFT_EYE_UPPER if i in lm]))
        lower_l = abs(safe_mean([lm[i][1] for i in LEFT_EYE_LOWER if i in lm]) - safe_mean([rest_landmarks[i][1] for i in LEFT_EYE_LOWER if i in rest_landmarks]))
        row["upper_move_r"] = normalize_by_n(upper_r, n)
        row["lower_move_r"] = normalize_by_n(lower_r, n)
        row["upper_ratio_r"] = upper_r / (upper_r + lower_r) if (upper_r + lower_r) else 0.0
        row["upper_move_l"] = normalize_by_n(upper_l, n)
        row["lower_move_l"] = normalize_by_n(lower_l, n)
        row["upper_ratio_l"] = upper_l / (upper_l + lower_l) if (upper_l + lower_l) else 0.0

        # Smile module: commissure excursion, symmetry, FAI, smile vector and reserve.
        mouth_r = lm.get(MOUTH_RIGHT)
        mouth_l = lm.get(MOUTH_LEFT)
        mouth_center = lm.get(MOUTH_CENTER)
        smile_r = dist(rest_landmarks[MOUTH_RIGHT], mouth_r) if mouth_r and MOUTH_RIGHT in rest_landmarks else 0.0
        smile_l = dist(rest_landmarks[MOUTH_LEFT], mouth_l) if mouth_l and MOUTH_LEFT in rest_landmarks else 0.0
        row["commissure_exc_r"] = normalize_by_n(smile_r, n)
        row["commissure_exc_l"] = normalize_by_n(smile_l, n)
        row["smile_symmetry"] = (smile_r / smile_l) if smile_l else 0.0
        row["smile_vector_r"] = normalize_by_n(dist(rest_eye_center_r, mouth_r), n) if mouth_r else 0.0
        row["smile_vector_l"] = normalize_by_n(dist(rest_eye_center_l, mouth_l), n) if mouth_l else 0.0
        row["vector_difference"] = abs(row["smile_vector_l"] - row["smile_vector_r"])
        row["mouth_area"] = normalize_by_n(polygon_area(poly_points(lm, MOUTH_POLY)), n, power=2)
        mouth_area_series.append(row["mouth_area"])
        row["dental_show_proxy"] = normalize_by_n(abs((rest_mouth_center[1] if rest_mouth_center else 0.0) - (mouth_center[1] if mouth_center else 0.0)), n)

        # Mouth motion magnitude + velocity.
        smile_magnitude = max(smile_r, smile_l)
        smile_magnitude_series.append(smile_magnitude)
        row["smile_magnitude"] = normalize_by_n(smile_magnitude, n)

        # Brow module: use the anchor points explicitly referenced by Dynaface brows logic.
        brow_y = safe_mean([lm[i][1] for i in RIGHT_BROW + LEFT_BROW if i in lm])
        brow_elev = rest_brow_y - brow_y
        brow_elev_series.append(brow_elev)
        row["brow_elevation"] = normalize_by_n(brow_elev, n)
        brow_r = safe_mean([rest_landmarks[i][1] for i in RIGHT_BROW if i in rest_landmarks]) - safe_mean([lm[i][1] for i in RIGHT_BROW if i in lm])
        brow_l = safe_mean([rest_landmarks[i][1] for i in LEFT_BROW if i in rest_landmarks]) - safe_mean([lm[i][1] for i in LEFT_BROW if i in lm])
        row["brow_symmetry"] = (abs(brow_r) / abs(brow_l)) if brow_l else 0.0
        row["recruitment_ratio"] = abs(brow_r) / (abs(brow_r) + abs(brow_l)) if (abs(brow_r) + abs(brow_l)) else 0.0
        row["brow_elevation_r"] = normalize_by_n(brow_r, n)
        row["brow_elevation_l"] = normalize_by_n(brow_l, n)

        elev_medial_r = abs(safe_mean([rest_landmarks[i][1] for i in BROW_MEDIAL_R]) - safe_mean([lm[i][1] for i in BROW_MEDIAL_R if i in lm]))
        elev_medial_l = abs(safe_mean([rest_landmarks[i][1] for i in BROW_MEDIAL_L]) - safe_mean([lm[i][1] for i in BROW_MEDIAL_L if i in lm]))
        elev_lateral_r = abs(safe_mean([rest_landmarks[i][1] for i in BROW_LATERAL_R]) - safe_mean([lm[i][1] for i in BROW_LATERAL_R if i in lm]))
        elev_lateral_l = abs(safe_mean([rest_landmarks[i][1] for i in BROW_LATERAL_L]) - safe_mean([lm[i][1] for i in BROW_LATERAL_L if i in lm]))
        row["elev_medial_r"] = normalize_by_n(elev_medial_r, n)
        row["elev_medial_l"] = normalize_by_n(elev_medial_l, n)
        row["elev_lateral_r"] = normalize_by_n(elev_lateral_r, n)
        row["elev_lateral_l"] = normalize_by_n(elev_lateral_l, n)

        # Nasal / midface module: supported by Dynaface nose landmarks.
        alar = abs(lm[NOSE_LEFT][0] - lm[NOSE_RIGHT][0]) if NOSE_LEFT in lm and NOSE_RIGHT in lm else 0.0
        alar_series.append(alar)
        row["alar_movement"] = normalize_by_n(abs(alar - (abs(rest_landmarks[NOSE_LEFT][0] - rest_landmarks[NOSE_RIGHT][0]) if NOSE_LEFT in rest_landmarks and NOSE_RIGHT in rest_landmarks else alar)), n)
        row["alar_symmetry"] = 1.0 if alar == 0 else clamp(1.0 - abs(alar - (abs(rest_landmarks[NOSE_LEFT][0] - rest_landmarks[NOSE_RIGHT][0]) if NOSE_LEFT in rest_landmarks and NOSE_RIGHT in rest_landmarks else alar)) / max(alar, 1e-9))
        row["alar_movement_l"] = normalize_by_n(dist(rest_landmarks[NOSE_LEFT], lm[NOSE_LEFT]), n) if NOSE_LEFT in rest_landmarks and NOSE_LEFT in lm else 0.0
        row["alar_movement_r"] = normalize_by_n(dist(rest_landmarks[NOSE_RIGHT], lm[NOSE_RIGHT]), n) if NOSE_RIGHT in rest_landmarks and NOSE_RIGHT in lm else 0.0
        cupid_x = mouth_center[0] if mouth_center else rest_mouth_center[0]
        row["cupid_bow_deviation"] = normalize_by_n(cupid_x - rest_x_midline, n)
        row["dynamic_shift"] = normalize_by_n(abs((mouth_center[1] if mouth_center else 0.0) - rest_mouth_center[1]), n) if mouth_center else 0.0
        row["midface_area_proxy"] = row["mouth_area"]
        row["cheek_elevation_proxy"] = row["brow_elevation"]
        row["cheek_elevation_r"] = row["brow_elevation_r"]
        row["cheek_elevation_l"] = row["brow_elevation_l"]
        row["cheek_symmetry"] = clamp(1.0 - abs(row["cheek_elevation_l"] - row["cheek_elevation_r"]) / max(abs(row["cheek_elevation_l"]) + abs(row["cheek_elevation_r"]), 1e-9))

        row["upper_lip_area_l"] = normalize_by_n(polygon_area(poly_points(lm, UPPER_LIP_L)), n, power=2)
        row["upper_lip_area_r"] = normalize_by_n(polygon_area(poly_points(lm, UPPER_LIP_R)), n, power=2)
        row["upper_lip_symmetry"] = clamp(1.0 - abs(row["upper_lip_area_l"] - row["upper_lip_area_r"]) / max(row["upper_lip_area_l"] + row["upper_lip_area_r"], 1e-9))

        row["midface_area_l"] = normalize_by_n(polygon_area(poly_points(lm, MIDFACE_L)), n, power=2)
        row["midface_area_r"] = normalize_by_n(polygon_area(poly_points(lm, MIDFACE_R)), n, power=2)
        row["midface_symmetry"] = clamp(1.0 - abs(row["midface_area_l"] - row["midface_area_r"]) / max(row["midface_area_l"] + row["midface_area_r"], 1e-9))

        # Temporal dynamics.
        row["time_to_peak_proxy"] = 0.0
        row["peak_velocity_proxy"] = 0.0
        row["smoothness_proxy"] = 0.0

        # Synkinesis / hypercontractility proxies (0..1).
        row["synk_upper_eyelid"] = clamp(row["upper_move_r"] / max(row["eye_closure_completeness_r"], 1e-6))
        row["synk_lower_eyelid"] = clamp(row["lower_move_r"] / max(row["eye_closure_completeness_r"], 1e-6))
        row["synk_mouth_eye"] = clamp(row["smile_magnitude"] / max(row["eye_closure_completeness_r"] + row["eye_closure_completeness_l"], 1e-6))
        row["brow_eye_coupling"] = clamp(abs(row["brow_elevation"]) / max(row["smile_magnitude"], 1e-6))
        row["synk_score"] = clamp(
            0.30 * row["synk_upper_eyelid"]
            + 0.30 * row["synk_lower_eyelid"]
            + 0.25 * row["synk_mouth_eye"]
            + 0.15 * row["brow_eye_coupling"]
        )

        # Global score (0-100): symmetry + movement - synkinesis penalty.
        symmetry = clamp(
            0.30 * (1.0 - min(abs(row["eye_ratio"] - 1.0), 1.0))
            + 0.30 * (1.0 - min(abs(row["smile_symmetry"] - 1.0), 1.0))
            + 0.20 * (1.0 - min(abs(row["brow_symmetry"] - 1.0), 1.0))
            + 0.20 * (1.0 - min(abs(row["alar_symmetry"] - 1.0), 1.0))
        )
        movement = clamp(
            0.40 * row["eye_closure_completeness_r"]
            + 0.40 * row["eye_closure_completeness_l"]
            + 0.20 * min(row["smile_magnitude"], 1.0)
        )
        penalty = clamp(row["synk_score"])
        row["global_score"] = 100.0 * clamp(0.55 * symmetry + 0.45 * movement - 0.25 * penalty)

        global_score_series.append(row["global_score"])
        rows.append(row)

    # Temporal metrics using the computed series.
    for i, row in enumerate(rows):
        if i < 1:
            row["blink_velocity_r"] = 0.0
            row["blink_velocity_l"] = 0.0
            row["peak_close_velocity_r"] = 0.0
            row["peak_close_velocity_l"] = 0.0
            row["smile_velocity"] = 0.0
        else:
            dt = max(rows[i]["time_sec"] - rows[i - 1]["time_sec"], 1e-9)
            row["blink_velocity_r"] = (eye_aperture_r_series[i] - eye_aperture_r_series[i - 1]) / dt
            row["blink_velocity_l"] = (eye_aperture_l_series[i] - eye_aperture_l_series[i - 1]) / dt
            row["peak_close_velocity_r"] = min(velocity(eye_aperture_r_series[: i + 1], [r["time_sec"] for r in rows[: i + 1]]))
            row["peak_close_velocity_l"] = min(velocity(eye_aperture_l_series[: i + 1], [r["time_sec"] for r in rows[: i + 1]]))
            row["smile_velocity"] = (smile_magnitude_series[i] - smile_magnitude_series[i - 1]) / dt

    # Time-to-peak and smoothness are sequence-level, assign as summary features.
    if smile_magnitude_series:
        peak_idx = max(range(len(smile_magnitude_series)), key=lambda i: smile_magnitude_series[i])
        peak_time = rows[peak_idx]["time_sec"]
        peak_vel = max(velocity(smile_magnitude_series, [r["time_sec"] for r in rows]))
        vel = velocity(smile_magnitude_series, [r["time_sec"] for r in rows])
        smoothness = 1.0 / max(statistics.pvariance(vel) if len(vel) > 1 else 1.0, 1e-9)
        for row in rows:
            row["time_to_peak_proxy"] = peak_time
            row["peak_velocity_proxy"] = peak_vel
            row["smoothness_proxy"] = smoothness

    return rows


def extract_summary_metrics(rows: list[dict[str, float]]) -> dict[str, Any]:
    """Extract summary (aggregated) metrics from per-frame rows.
    
    Returns a dict organized by clinical region with min/max/mean values.
    """
    if not rows:
        return {}

    def safe_agg(key: str, agg_fn: callable) -> float:
        vals = [r.get(key, 0.0) for r in rows if key in r]
        return agg_fn(vals) if vals else 0.0

    def recruitment(key_l: str, key_r: str) -> tuple[float, float]:
        peak_l = safe_agg(key_l, max)
        peak_r = safe_agg(key_r, max)
        denom = max(peak_l, peak_r, 1e-6)
        return peak_l / denom, peak_r / denom

    medial_recruitment_l, medial_recruitment_r = recruitment("elev_medial_l", "elev_medial_r")
    lateral_recruitment_l, lateral_recruitment_r = recruitment("elev_lateral_l", "elev_lateral_r")
    cupid_bow_values = [r.get("cupid_bow_deviation", 0.0) for r in rows]
    max_cupid_bow_deviation = max(cupid_bow_values, key=abs) if cupid_bow_values else 0.0

    summary = {
        "global_score": {
            "current": rows[-1].get("global_score", 0.0),
            "baseline": rows[0].get("global_score", 0.0),
            "mean": safe_agg("global_score", safe_mean),
            "max": safe_agg("global_score", max),
            "min": safe_agg("global_score", min),
        },
        "eye_module": {
            "max_aperture_l": safe_agg("eye_aperture_l", max),
            "max_aperture_r": safe_agg("eye_aperture_r", max),
            "min_aperture_l": safe_agg("eye_aperture_l", min),
            "min_aperture_r": safe_agg("eye_aperture_r", min),
            "eye_closure_completeness_l": safe_agg("eye_closure_completeness_l", max),
            "eye_closure_completeness_r": safe_agg("eye_closure_completeness_r", max),
            "mean_eye_area_l": safe_agg("eye_area_l", safe_mean),
            "mean_eye_area_r": safe_agg("eye_area_r", safe_mean),
            "mean_eye_ratio": safe_agg("eye_ratio", safe_mean),
            "mean_eye_diff": safe_agg("eye_diff", safe_mean),
            "mean_upper_ratio_l": safe_agg("upper_ratio_l", safe_mean),
            "mean_upper_ratio_r": safe_agg("upper_ratio_r", safe_mean),
            "peak_close_velocity_l": safe_agg("blink_velocity_l", lambda x: min(x) if x else 0.0),
            "peak_close_velocity_r": safe_agg("blink_velocity_r", lambda x: min(x) if x else 0.0),
        },
        "smile_module": {
            "max_commissure_exc_l": safe_agg("commissure_exc_l", max),
            "max_commissure_exc_r": safe_agg("commissure_exc_r", max),
            "max_smile_magnitude": safe_agg("smile_magnitude", max),
            "mean_smile_symmetry": safe_agg("smile_symmetry", safe_mean),
            "mean_smile_velocity": safe_agg("smile_velocity", safe_mean),
            "max_smile_velocity": safe_agg("smile_velocity", max),
            "max_dental_show": safe_agg("dental_show_proxy", max),
            "max_smile_vector_l": safe_agg("smile_vector_l", max),
            "max_smile_vector_r": safe_agg("smile_vector_r", max),
            "mean_fai": safe_agg("fai", safe_mean),
        },
        "brow_module": {
            "max_brow_elevation": safe_agg("brow_elevation", max),
            "mean_brow_symmetry": safe_agg("brow_symmetry", safe_mean),
            "mean_recruitment_ratio": safe_agg("recruitment_ratio", safe_mean),
            "max_brow_elevation_l": safe_agg("brow_elevation_l", max),
            "max_brow_elevation_r": safe_agg("brow_elevation_r", max),
            "medial_recruitment_l": medial_recruitment_l,
            "medial_recruitment_r": medial_recruitment_r,
            "lateral_recruitment_l": lateral_recruitment_l,
            "lateral_recruitment_r": lateral_recruitment_r,
        },
        "midface_module": {
            "max_alar_movement": safe_agg("alar_movement", max),
            "mean_alar_symmetry": safe_agg("alar_symmetry", safe_mean),
            "mean_cheek_elevation": safe_agg("cheek_elevation_proxy", safe_mean),
            "mean_midface_area": safe_agg("midface_area_proxy", safe_mean),
            "mean_dynamic_shift": safe_agg("dynamic_shift", safe_mean),
            "max_alar_movement_l": safe_agg("alar_movement_l", max),
            "max_alar_movement_r": safe_agg("alar_movement_r", max),
            "mean_cheek_elevation_l": safe_agg("cheek_elevation_l", safe_mean),
            "mean_cheek_elevation_r": safe_agg("cheek_elevation_r", safe_mean),
            "max_cupid_bow_deviation": max_cupid_bow_deviation,
            "upper_lip_area_l": safe_agg("upper_lip_area_l", safe_mean),
            "upper_lip_area_r": safe_agg("upper_lip_area_r", safe_mean),
            "upper_lip_symmetry": safe_agg("upper_lip_symmetry", safe_mean),
            "midface_area_l": safe_agg("midface_area_l", safe_mean),
            "midface_area_r": safe_agg("midface_area_r", safe_mean),
            "midface_contour": safe_agg("midface_symmetry", safe_mean),
        },
        "synkinesis": {
            "mean_synk_score": safe_agg("synk_score", safe_mean),
            "max_synk_score": safe_agg("synk_score", max),
            "mean_synk_upper_eyelid": safe_agg("synk_upper_eyelid", safe_mean),
            "mean_synk_lower_eyelid": safe_agg("synk_lower_eyelid", safe_mean),
            "mean_synk_mouth_eye": safe_agg("synk_mouth_eye", safe_mean),
            "mean_brow_eye_coupling": safe_agg("brow_eye_coupling", safe_mean),
        },
        "temporal_dynamics": {
            "time_to_peak_proxy": rows[-1].get("time_to_peak_proxy", 0.0) if rows else 0.0,
            "mean_smoothness": safe_agg("smoothness_proxy", safe_mean),
            "mean_velocity": safe_agg("smile_velocity", safe_mean),
        },
    }
    return summary


def compute_measurement_metrics(records: list[FrameRecord]) -> list[dict[str, float]]:
    # Fallback path for Dynaface measurement CSVs (VideoToVideo.dump_data output).
    rows: list[dict[str, float]] = []
    fai_series: list[float] = []
    eye_l_series: list[float] = []
    eye_r_series: list[float] = []
    dental_series: list[float] = []
    brow_series: list[float] = []
    for rec in records:
        row: dict[str, float] = {"frame": float(rec.frame), "time_sec": float(rec.time_sec)}
        for key in ["fai", "oce.l", "oce.r", "brow.d", "dental_area", "dental_left", "dental_right", "dental_ratio", "dental_diff", "eye.left", "eye.right", "eye.diff", "eye.ratio", "ml", "tilt", "pd", "pitch", "roll", "yaw", "nostril", "nose.tip", "dorsal.base", "dorsal.bridge", "oe", "id"]:
            if key in rec.measures:
                row[key] = float(rec.measures[key])
        # simple derived values
        fai = row.get("fai", 0.0)
        eye_l = row.get("eye.left", 0.0)
        eye_r = row.get("eye.right", 0.0)
        dental = row.get("dental_area", row.get("dental_left", 0.0) + row.get("dental_right", 0.0))
        brow = row.get("brow.d", 0.0)
        fai_series.append(fai)
        eye_l_series.append(eye_l)
        eye_r_series.append(eye_r)
        dental_series.append(dental)
        brow_series.append(brow)
        eye_sym = 1.0 - min(abs((eye_l / eye_r) if eye_r else 1.0 - 1.0), 1.0)
        oral_sym = 1.0 - min(abs((row.get("oce.l", 0.0) / row.get("oce.r", 1.0)) - 1.0), 1.0)
        row["global_score"] = 100.0 * clamp(0.35 * eye_sym + 0.35 * oral_sym + 0.20 * (1.0 - min(abs(fai), 1.0)) + 0.10 * (1.0 - min(abs(brow), 1.0)))
        row["synk_score"] = clamp(abs(row.get("eye.diff", 0.0)) + abs(row.get("dental_diff", 0.0)))
        rows.append(row)

    return rows


# ---------------------------------------------------------------------------
# Output generation
# ---------------------------------------------------------------------------

def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def write_csv(path: Path, rows: list[dict[str, float]]) -> None:
    ensure_dir(path.parent)
    cols = sorted({key for row in rows for key in row.keys()})
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=cols)
        writer.writeheader()
        for row in rows:
            writer.writerow({k: row.get(k, "") for k in cols})


def svg_header(width: int, height: int, title: str) -> list[str]:
    return [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="white"/>',
        f'<text x="20" y="30" font-family="Arial, sans-serif" font-size="20" font-weight="bold">{escape(title)}</text>',
    ]


def write_svg(path: Path, lines: list[str]) -> None:
    ensure_dir(path.parent)
    path.write_text("\n".join(lines + ["</svg>"]), encoding="utf-8")


def make_line_chart_svg(rows: list[dict[str, float]], title: str, y_key: str, events: list[dict[str, Any]], width: int = 1100, height: int = 340) -> list[str]:
    plot_left, plot_top, plot_right, plot_bottom = 70, 60, width - 30, height - 55
    plot_w = plot_right - plot_left
    plot_h = plot_bottom - plot_top
    times = [r["time_sec"] for r in rows]
    ys = [r.get(y_key, 0.0) for r in rows]
    if not times:
        times = [0.0]
        ys = [0.0]
    min_t, max_t = min(times), max(times)
    min_y, max_y = min(ys), max(ys)
    if math.isclose(min_t, max_t):
        max_t = min_t + 1.0
    if math.isclose(min_y, max_y):
        max_y = min_y + 1.0

    def x_map(t: float) -> float:
        return plot_left + (t - min_t) / (max_t - min_t) * plot_w

    def y_map(v: float) -> float:
        return plot_bottom - (v - min_y) / (max_y - min_y) * plot_h

    lines = svg_header(width, height, title)
    lines += [
        f'<line x1="{plot_left}" y1="{plot_top}" x2="{plot_left}" y2="{plot_bottom}" stroke="#444"/>',
        f'<line x1="{plot_left}" y1="{plot_bottom}" x2="{plot_right}" y2="{plot_bottom}" stroke="#444"/>',
        f'<text x="{plot_left}" y="{height - 15}" font-family="Arial" font-size="12">Time (sec)</text>',
        f'<text x="15" y="{plot_top + plot_h / 2}" font-family="Arial" font-size="12" transform="rotate(-90 15,{plot_top + plot_h / 2})">{escape(y_key)}</text>',
    ]
    points = " ".join(f"{x_map(r['time_sec']):.2f},{y_map(r.get(y_key, 0.0)):.2f}" for r in rows)
    lines.append(f'<polyline fill="none" stroke="#1565c0" stroke-width="2" points="{points}"/>')

    # Event markers.
    for ev in events:
        t = parse_float(ev.get("time_sec") if isinstance(ev, dict) else None)
        if t is None:
            continue
        if t < min_t or t > max_t:
            continue
        x = x_map(t)
        lines += [
            f'<line x1="{x:.2f}" y1="{plot_top}" x2="{x:.2f}" y2="{plot_bottom}" stroke="#d32f2f" stroke-dasharray="4,4"/>',
            f'<text x="{x + 4:.2f}" y="{plot_top + 14}" font-family="Arial" font-size="11" fill="#d32f2f">{escape(str(ev.get("label", "event")))}</text>',
        ]

    # Axis labels
    lines.append(f'<text x="{plot_left}" y="{plot_bottom + 18}" font-family="Arial" font-size="11">{min_t:.1f}</text>')
    lines.append(f'<text x="{plot_right - 35}" y="{plot_bottom + 18}" font-family="Arial" font-size="11">{max_t:.1f}</text>')
    lines.append(f'<text x="{plot_left}" y="{plot_top - 10}" font-family="Arial" font-size="11">max</text>')
    lines.append(f'<text x="{plot_left}" y="{plot_bottom + 3}" font-family="Arial" font-size="11">min</text>')
    return lines


def make_heatmap_svg(rows: list[tuple[str, float]], title: str, width: int = 720, height: int = 240) -> list[str]:
    lines = svg_header(width, height, title)
    x0, y0 = 20, 60
    cell_w, cell_h = 160, 50
    max_score = max((v for _, v in rows), default=1.0)
    max_score = max(max_score, 1e-9)

    def color_for(v: float) -> str:
        # green -> yellow -> red
        p = clamp(v / max_score)
        if p < 0.5:
            # 0..0.5 : green to yellow
            t = p / 0.5
            r = int(255 * t)
            g = 200
            b = 70
        else:
            # 0.5..1 : yellow to red
            t = (p - 0.5) / 0.5
            r = 255
            g = int(200 * (1 - t))
            b = 70
        return f"rgb({r},{g},{b})"

    for i, (label, value) in enumerate(rows):
        y = y0 + i * (cell_h + 10)
        lines += [
            f'<text x="20" y="{y - 10}" font-family="Arial" font-size="12">{escape(label)}</text>',
            f'<rect x="20" y="{y}" width="{cell_w}" height="{cell_h}" rx="8" fill="{color_for(value)}" stroke="#444"/>',
            f'<text x="35" y="{y + 30}" font-family="Arial" font-size="14" font-weight="bold" fill="#111">{value:.2f}</text>',
        ]
    return lines


def render_markdown_report(metadata: Metadata, rows: list[dict[str, float]], outdir: Path, compare_summary: dict[str, float] | None = None) -> str:
    first = rows[0]
    last = rows[-1]
    def fmt(v: Any, digits: int = 2) -> str:
        if v is None:
            return "n/a"
        if isinstance(v, (int, float)):
            return f"{v:.{digits}f}"
        return str(v)

    summary_keys = ["global_score", "fai", "eye_closure_completeness_r", "eye_closure_completeness_l", "eye_ratio", "eye_diff", "commissure_exc_r", "commissure_exc_l", "smile_symmetry", "brow_elevation", "synk_score"]
    md = []
    md.append("# Patient Snapshot")
    md.append("")
    md.append(f"- **Patient ID / Name:** {escape(metadata.patient_id)} / {escape(metadata.patient_name)}")
    md.append(f"- **Diagnosis (Etiology):** {escape(metadata.diagnosis)}")
    md.append(f"- **Functional Status:** {escape(metadata.functional_status)}")
    md.append(f"- **Side affected:** {escape(metadata.side_affected)}")
    md.append(f"- **Date of injury/paralysis:** {escape(metadata.date_of_injury)}")
    md.append(f"- **Intervention(s):** {escape(metadata.interventions)}")
    md.append(f"- **Surgery:** {escape(metadata.surgery)}")
    md.append(f"- **Botox dates / notes:** {escape(metadata.botox)}")
    if metadata.notes:
        md.append(f"- **Notes:** {escape(metadata.notes)}")
    md.append("")
    if metadata.events:
        md.append("## Timeline markers")
        for ev in metadata.events:
            label = ev.get("label", "event")
            time_sec = ev.get("time_sec", ev.get("time", ""))
            desc = ev.get("description", "")
            md.append(f"- {escape(str(time_sec))} sec — **{escape(str(label))}**{(' — ' + escape(str(desc))) if desc else ''}")
        md.append("")

    md.append("## Global Facial Function Score")
    md.append("")
    md.append(f"- **Score (current):** {fmt(last['global_score'])} / 100")
    md.append(f"- **Trend baseline → current:** {fmt(first['global_score'])} → {fmt(last['global_score'])}")
    md.append(f"- **Synkinesis penalty:** {fmt(last['synk_score'])}")
    md.append("")
    md.append(f"![Global score timeline](plots/global_score.svg)")
    md.append("")

    md.append("## Regional Movement Panels")
    md.append("")
    md.append("### Eye Module")
    md.append(f"- Eye aperture R/L: {fmt(last.get('eye_aperture_r'))} / {fmt(last.get('eye_aperture_l'))}")
    md.append(f"- Eye closure completeness R/L: {fmt(last.get('eye_closure_completeness_r'))} / {fmt(last.get('eye_closure_completeness_l'))}")
    md.append(f"- Eye area R/L: {fmt(last.get('eye_area_r'))} / {fmt(last.get('eye_area_l'))}")
    md.append(f"- Eye ratio / diff: {fmt(last.get('eye_ratio'))} / {fmt(last.get('eye_diff'))}")
    md.append(f"- Upper vs lower eyelid contribution R/L: {fmt(last.get('upper_ratio_r'))} / {fmt(last.get('upper_ratio_l'))}")
    md.append(f"- Blink velocity R/L: {fmt(last.get('blink_velocity_r'))} / {fmt(last.get('blink_velocity_l'))}")
    md.append("")
    md.append("### Smile / Oral Commissure Module")
    md.append(f"- Commissure excursion R/L: {fmt(last.get('commissure_exc_r'))} / {fmt(last.get('commissure_exc_l'))}")
    md.append(f"- Smile symmetry: {fmt(last.get('smile_symmetry'))}")
    md.append(f"- FAI: {fmt(last.get('fai'))}")
    md.append(f"- Smile vector R/L: {fmt(last.get('smile_vector_r'))} / {fmt(last.get('smile_vector_l'))}")
    md.append(f"- Smile velocity: {fmt(last.get('smile_velocity'))}")
    md.append(f"- Time to peak: {fmt(last.get('time_to_peak_proxy'))} sec")
    md.append(f"- Smile reserve proxy: not directly available from a single CSV; use broad-smile vs gentle-smile passes if you provide separate CSVs.")
    md.append(f"- Dental show proxy: {fmt(last.get('dental_show_proxy'))}")
    md.append("")
    md.append("### Brow / Forehead Module")
    md.append(f"- Brow elevation: {fmt(last.get('brow_elevation'))}")
    md.append(f"- Brow symmetry: {fmt(last.get('brow_symmetry'))}")
    md.append(f"- Recruitment ratio: {fmt(last.get('recruitment_ratio'))}")
    md.append("")
    md.append("### Nasal / Midface Module")
    md.append(f"- Alar movement: {fmt(last.get('alar_movement'))}")
    md.append(f"- Alar symmetry: {fmt(last.get('alar_symmetry'))}")
    md.append(f"- Cupid's bow deviation: {fmt(last.get('cupid_bow_deviation'))}")
    md.append(f"- Dynamic shift: {fmt(last.get('dynamic_shift'))}")
    md.append(f"- Lip / midface area proxy: {fmt(last.get('midface_area_proxy'))}")
    md.append(f"- Cheek elevation proxy: {fmt(last.get('cheek_elevation_proxy'))}")
    md.append("")

    md.append("## Synkinesis / Hypercontractility / Spasm Heatmap")
    md.append("")
    md.append(f"- Global synkinesis score: {fmt(last.get('synk_score'))} (0–1)")
    md.append(f"![Synkinesis heatmap](plots/synkinesis_heatmap.svg)")
    md.append("")

    md.append("## Temporal Dynamics")
    md.append("")
    md.append(f"- Peak smile time: {fmt(last.get('time_to_peak_proxy'))} sec")
    md.append(f"- Peak smile velocity proxy: {fmt(last.get('peak_velocity_proxy'))}")
    md.append(f"- Smoothness proxy: {fmt(last.get('smoothness_proxy'))}")
    md.append("")
    md.append("## Baseline vs Current")
    md.append("")
    md.append("| Metric | Baseline | Current | Delta |")
    md.append("|---|---:|---:|---:|")
    for key in summary_keys:
        base = first.get(key, 0.0)
        curr = last.get(key, 0.0)
        md.append(f"| {key} | {fmt(base)} | {fmt(curr)} | {fmt(curr - base)} |")
    md.append("")

    if compare_summary:
        md.append("## Comparison Summary")
        md.append("")
        md.append("| Metric | Pre | Post | Delta |")
        md.append("|---|---:|---:|---:|")
        for key, value in compare_summary.items():
            md.append(f"| {key} | {fmt(value)} | | |")
        md.append("")

    md.append(f"_Generated: {datetime.now().isoformat(timespec='seconds')}_")
    return "\n".join(md)


def summarize_compare(main_rows: list[dict[str, float]], compare_rows: list[dict[str, float]]) -> dict[str, float]:
    # Compare median values of core metrics.
    keys = ["global_score", "fai", "eye_ratio", "eye_diff", "commissure_exc_r", "commissure_exc_l", "brow_elevation", "synk_score"]
    summary: dict[str, float] = {}
    for key in keys:
        main_vals = [r.get(key, 0.0) for r in main_rows]
        comp_vals = [r.get(key, 0.0) for r in compare_rows]
        summary[f"pre_{key}"] = safe_median(main_vals)
        summary[f"post_{key}"] = safe_median(comp_vals)
        summary[f"delta_{key}"] = summary[f"post_{key}"] - summary[f"pre_{key}"]
    return summary


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate a clinical facial function report from a Dynaface CSV export."
    )
    parser.add_argument("input_csv", type=Path, help="Primary CSV input (prefer AnalyzeLandmarks output).")
    parser.add_argument("--metadata", type=Path, default=None, help="Optional JSON file with patient metadata and timeline markers.")
    parser.add_argument("--outdir", type=Path, default=Path("clinical_report_output"), help="Output directory for report files.")
    parser.add_argument("--rest-frame", type=int, default=0, help="Baseline/rest frame index (0-based).")
    parser.add_argument("--compare-csv", type=Path, default=None, help="Optional second CSV to compare against the primary input.")

    args = parser.parse_args()

    metadata = load_metadata(args.metadata)
    records, has_landmarks, has_measures = load_records(args.input_csv)
    if not has_landmarks and not has_measures:
        raise ValueError("CSV does not contain Dynaface landmarks or measurement columns.")

    if has_landmarks:
        rows = compute_landmark_metrics(records, metadata, rest_index=args.rest_frame)
    else:
        rows = compute_measurement_metrics(records)

    ensure_dir(args.outdir)
    ensure_dir(args.outdir / "plots")

    # Write detailed per-frame metrics.
    write_csv(args.outdir / "metrics.csv", rows)

    # Optional comparison CSV.
    compare_summary = None
    if args.compare_csv:
        compare_records, compare_has_landmarks, compare_has_measures = load_records(args.compare_csv)
        compare_rows = compute_landmark_metrics(compare_records, metadata, rest_index=args.rest_frame) if compare_has_landmarks else compute_measurement_metrics(compare_records)
        write_csv(args.outdir / "comparison_metrics.csv", compare_rows)
        compare_summary = summarize_compare(rows, compare_rows)

    # SVG outputs.
    write_svg(
        args.outdir / "plots" / "global_score.svg",
        make_line_chart_svg(rows, "Global Facial Function Score", "global_score", metadata.events),
    )
    write_svg(
        args.outdir / "plots" / "synkinesis_heatmap.svg",
        make_heatmap_svg(
            [
                ("Synk_upper_eyelid", rows[-1].get("synk_upper_eyelid", 0.0)),
                ("Synk_lower_eyelid", rows[-1].get("synk_lower_eyelid", 0.0)),
                ("Synk_mouth_eye", rows[-1].get("synk_mouth_eye", 0.0)),
                ("Brow_eye_coupling", rows[-1].get("brow_eye_coupling", 0.0)),
            ],
            "Synkinesis Heatmap",
        ),
    )

    # Markdown report.
    report = render_markdown_report(metadata, rows, args.outdir, compare_summary=compare_summary)
    (args.outdir / "report.md").write_text(report, encoding="utf-8")

    # Light JSON summary for downstream use.
    summary_payload = {
        "patient_id": metadata.patient_id,
        "patient_name": metadata.patient_name,
        "diagnosis": metadata.diagnosis,
        "functional_status": metadata.functional_status,
        "side_affected": metadata.side_affected,
        "baseline_global_score": rows[0].get("global_score", 0.0),
        "current_global_score": rows[-1].get("global_score", 0.0),
        "delta_global_score": rows[-1].get("global_score", 0.0) - rows[0].get("global_score", 0.0),
        "current_synk_score": rows[-1].get("synk_score", 0.0),
        "input_csv": str(args.input_csv),
    }
    (args.outdir / "summary.json").write_text(json.dumps(summary_payload, indent=2), encoding="utf-8")

    print(f"Report written to: {args.outdir}")
    print(f"- {args.outdir / 'report.md'}")
    print(f"- {args.outdir / 'metrics.csv'}")
    print(f"- {args.outdir / 'summary.json'}")
    print(f"- {args.outdir / 'plots' / 'global_score.svg'}")
    print(f"- {args.outdir / 'plots' / 'synkinesis_heatmap.svg'}")
    if args.compare_csv:
        print(f"- {args.outdir / 'comparison_metrics.csv'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
