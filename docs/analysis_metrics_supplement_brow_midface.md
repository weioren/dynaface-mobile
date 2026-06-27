# Metric Calculations — Supplement: Per-Side Fields for Brow & Midface

Companion to **Metric Calculations.docx**. The Analysis UI's **Brow** and **Midface**
detail pages need per-side (left/right) values and a few derived fields that the current
`results.json` does not yet emit — the Brow/Midface modules currently output single
aggregate values only. These additions **reuse the same landmarks already defined in the
main document**; the worker already computes per-side values for the Eye and Smile modules,
so the infrastructure exists.

**Convention:** `Δy = y_rest − y_current` (image y grows downward, so positive = upward /
elevation). `N` = the same facial-size normalization factor used by the existing metrics.
The app maps left/right → affected/normal from the patient profile, so the worker only needs
to emit `_l` / `_r` (it does not need to know the affected side).

---

## Brow / Forehead Module — Additions

### 1. `brow_elevation_r` / `brow_elevation_l` (per-frame; extends #19)

```
brow_elevation_r = mean_y(brow_r_rest) − mean_y(brow_r_current)
brow_elevation_l = mean_y(brow_l_rest) − mean_y(brow_l_current)
```

Where:
- `brow_r` = landmarks [35, 36, 37, 38, 39, 40]
- `brow_l` = landmarks [44, 45, 46, 47, 48, 49]

Normalized by N. Positive = elevation. (Already implicit in #20 `brow_symmetry`; just emit
each side.)
**Summary:** `max_brow_elevation_r` / `max_brow_elevation_l` = max over all frames. Also emit
the per-frame series to drive the per-side Brow Elevation trend chart.

### 2. `medial_recruitment_r` / `_l` and `lateral_recruitment_r` / `_l` (summary; extends #21)

```
elev_medial_side  = | mean_y(brow_medial_side_rest)  − mean_y(brow_medial_side_current) |
elev_lateral_side = | mean_y(brow_lateral_side_rest) − mean_y(brow_lateral_side_current) |

medial_recruitment_side  = elev_medial_side  / max(elev_medial_l,  elev_medial_r,  ε)
lateral_recruitment_side = elev_lateral_side / max(elev_lateral_l, elev_lateral_r, ε)
```

Where:
- `brow_medial_side`  = the 3 brow points nearest the facial midline (inner brow), per side
- `brow_lateral_side` = the 3 brow points farthest from the midline (outer brow), per side
- take `elev_*` at the peak-elevation frame (or max over frames)

Range [0, 1]. Normalizing each region to the stronger side makes the better side ≈ 100% and
the weak side a fraction (matches the mock's "45% | 88%" framing). **Alternative** (per #21):
`medial_recruitment_side = elev_medial_side / (elev_medial_side + elev_lateral_side)` for the
within-side medial-vs-lateral split. Confirm the intended definition with the clinical lead.

---

## Nasal / Midface Module — Additions

### 3. `alar_movement_r` / `alar_movement_l` (per-frame; splits #22)

```
alar_movement_l = distance(landmark_55_rest, landmark_55_current)
alar_movement_r = distance(landmark_59_rest, landmark_59_current)
```

Where:
- `landmark_55` = left alar base
- `landmark_59` = right alar base

Normalized by N. **Summary:** `max_alar_movement_r` / `max_alar_movement_l` = max over frames.

### 4. `cheek_elevation_r` / `cheek_elevation_l` (per-frame; extends #27)

```
cheek_elevation_side = mean_y(cheek_side_rest) − mean_y(cheek_side_current)
```

Where:
- `cheek_side` = dedicated mid-cheek / zygomatic landmarks if available
- fallback (current proxy, #27): `cheek_elevation_side = brow_elevation_side`

Normalized by N. **Summary:** `mean_cheek_elevation_r` / `_l` (or `max_`). #27 currently
proxies cheek with brow; the per-side version should use real cheek landmarks if the model
exposes them.

### 5. `cupid_bow_deviation` (signed) (per-frame; extends #24)

```
cupid_bow_deviation = (x_cupids_bow_current − x_midline) / N      // signed, drop the |·|
```

Where:
- `x_cupids_bow` = x of landmark 85 (mouth center)
- `x_midline` = mean_x(eye_center_l, eye_center_r)
- sign: positive = toward right, negative = toward left

**Summary:** `max_cupid_bow_deviation` = the signed value at the frame of greatest
`|deviation|` (keep the sign so the UI can show "2.1 mm toward right"). Today this is only
per-frame and unsigned (#24).

### 6. `upper_lip_area_r` / `upper_lip_area_l` + `upper_lip_symmetry` (summary)

```
upper_lip_area_side = polygon_area(upper_lip_side_landmarks)
upper_lip_symmetry  = 1 − |upper_lip_area_l − upper_lip_area_r| / (upper_lip_area_l + upper_lip_area_r)
```

Where:
- `upper_lip_side` = the upper-lip subset of the mouth polygon (#17, landmarks [88–95]), split at `x_midline`
- `polygon_area` = Shoelace formula; normalized by N²

Range [0, 1], 1 = symmetric. Drives the mock's "Upper Lip 2D Area — 82% symmetry" row.

### 7. `midface_area_r` / `_l` + `midface_contour` (summary; extends #26)

```
midface_area_side = polygon_area(midface_side_region)        // per-side of the #26 proxy region
midface_contour   = 1 − mean_t[ |midface_area_l − midface_area_r| / (midface_area_l + midface_area_r) ]
```

Where:
- `midface_side_region` = the left/right half (about `x_midline`) of the #26 `midface_area_proxy` polygon
- `mean_t[·]` = mean over all frames

Range [0, 1], 1 = symmetric midface. **Alternative** if per-side area is impractical:
`midface_contour = 0.5·mean_alar_symmetry + 0.5·cheek_symmetry`. Drives the mock's
"Midface Contour 0.71".

---

## New summary keys (`results.json`)

- **`brow_module`:** `max_brow_elevation_l`, `max_brow_elevation_r`, `medial_recruitment_l`,
  `medial_recruitment_r`, `lateral_recruitment_l`, `lateral_recruitment_r`
- **`midface_module`:** `max_alar_movement_l`, `max_alar_movement_r`, `mean_cheek_elevation_l`,
  `mean_cheek_elevation_r`, `max_cupid_bow_deviation` (signed), `upper_lip_area_l`,
  `upper_lip_area_r`, `upper_lip_symmetry`, `midface_area_l`, `midface_area_r`, `midface_contour`
- **`per_frame`:** `brow_elevation_l`, `brow_elevation_r`, `alar_movement_l`, `alar_movement_r`,
  `cheek_elevation_l`, `cheek_elevation_r` (and the now-signed `cupid_bow_deviation`)

---

## Notes & open questions

- **Aggregation:** use `max` for peak-excursion fields and `mean` for sustained ones,
  consistent with the existing module fields.
- The app maps left/right → affected/normal from the patient profile; the worker only emits
  `_l` / `_r`.
- **Confirm with the clinical lead** the medial/lateral brow landmark subsets and the
  recruitment normalization (stronger-side vs within-side) before release.
- `cheek_elevation` and `midface_area` are 2D proxies (per #26/#27) — not true volumetric
  measurements.
- Once these ship, the iOS Analysis pages need **no logic change** — only the contract gains
  the `_l`/`_r` keys and the Brow/Midface rows switch from single values to the existing
  two-tone compare bar (`CompareBar` in `AnalysisViews.swift`).
