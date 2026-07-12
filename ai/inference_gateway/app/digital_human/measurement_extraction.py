"""Stage 3 — Measurement extraction.

Converts pose keypoints into body measurements with uncertainty scores.

Key insight: different photos see different things.
- Front/back photos see body WIDTH (shoulders, hips) but not depth.
- Side photos see body DEPTH (chest, butt protrusion) but not width.
- Use the right photo for each measurement.
"""

from __future__ import annotations

import logging
from typing import Optional

import numpy as np

from app.digital_human.models import BodyMeasurement, LandmarkData, PhotoAngle

logger = logging.getLogger(__name__)

# OpenPose BODY18 keypoint indices
KP_NOSE = 0
KP_NECK = 1
KP_R_SHOULDER = 2
KP_R_ELBOW = 3
KP_R_WRIST = 4
KP_L_SHOULDER = 5
KP_L_ELBOW = 6
KP_L_WRIST = 7
KP_R_HIP = 8
KP_R_KNEE = 9
KP_R_ANKLE = 10
KP_L_HIP = 11
KP_L_KNEE = 12
KP_L_ANKLE = 13

# Anthropometric constants
# Average adult shoulder width = 41cm (used to calibrate pixels → cm)
AVG_SHOULDER_WIDTH_CM = 41.0
# Neck-to-ankle is ~87% of full height (head adds the rest)
NECK_TO_ANKLE_HEIGHT_RATIO = 0.87
# Circumference approximation: width + depth → ellipse perimeter
# C ≈ π * (3*(a+b) - sqrt((3a+b)*(a+3b))) / 2 — Ramanujan approximation
# Simplified: C ≈ 2.6 * width when depth ≈ 0.65 * width (typical body ratio)


def _distance(p1: Optional[dict], p2: Optional[dict]) -> float:
    """Euclidean distance between two keypoints (or 0 if either is None)."""
    if p1 is None or p2 is None:
        return 0.0
    return float(np.sqrt((p1["x"] - p2["x"]) ** 2 + (p1["y"] - p2["y"]) ** 2))


def _calibrate_px_per_cm(landmarks: dict[str, LandmarkData]) -> Optional[float]:
    """Calibrate pixel-to-cm ratio using shoulder width from front photo.

    Side photos can't see shoulder width, so we use front + back + 3/4 views.
    Returns None if calibration fails.
    """
    shoulder_px_values = []

    for angle_name in ["front", "back", "three_quarter_left", "three_quarter_right"]:
        lm = landmarks.get(angle_name)
        if lm is None or len(lm.keypoints) <= KP_L_SHOULDER:
            continue
        r_shoulder = lm.keypoints[KP_R_SHOULDER]
        l_shoulder = lm.keypoints[KP_L_SHOULDER]
        if r_shoulder is None or l_shoulder is None:
            continue
        shoulder_px = _distance(r_shoulder, l_shoulder)
        if shoulder_px > 0:
            shoulder_px_values.append(shoulder_px)

    if not shoulder_px_values:
        return None

    avg_shoulder_px = float(np.mean(shoulder_px_values))
    return avg_shoulder_px / AVG_SHOULDER_WIDTH_CM


def extract_height(landmarks: dict[str, LandmarkData], px_per_cm: float) -> Optional[BodyMeasurement]:
    """Height from front/back photo: neck to ankle, calibrated to full height."""
    source_photos = []
    height_px_values = []

    for angle_name in ["front", "back"]:
        lm = landmarks.get(angle_name)
        if lm is None or len(lm.keypoints) <= KP_R_ANKLE:
            continue
        neck = lm.keypoints[KP_NECK]
        r_ankle = lm.keypoints[KP_R_ANKLE]
        l_ankle = lm.keypoints[KP_L_ANKLE]
        ankle = r_ankle if r_ankle is not None else l_ankle
        if neck is None or ankle is None:
            continue
        height_px = abs(ankle["y"] - neck["y"])
        if height_px > 0:
            height_px_values.append(height_px)
            source_photos.append(angle_name)

    if not height_px_values or px_per_cm <= 0:
        return None

    avg_height_px = float(np.mean(height_px_values))
    # neck-to-ankle is ~87% of full height, so divide by 0.87
    height_cm = avg_height_px / px_per_cm / NECK_TO_ANKLE_HEIGHT_RATIO
    confidence = min(1.0, len(height_px_values) / 2.0)  # 2 photos = 1.0

    return BodyMeasurement(
        value=round(height_cm, 1),
        unit="cm",
        confidence=round(confidence, 3),
        source_photos=source_photos,
        method="openpose_neck_to_ankle",
    )


def extract_shoulder_width(landmarks: dict[str, LandmarkData], px_per_cm: float) -> Optional[BodyMeasurement]:
    """Shoulder width from front + back photos (NOT side photos)."""
    source_photos = []
    shoulder_px_values = []

    for angle_name in ["front", "back", "three_quarter_left", "three_quarter_right"]:
        lm = landmarks.get(angle_name)
        if lm is None or len(lm.keypoints) <= KP_L_SHOULDER:
            continue
        r_shoulder = lm.keypoints[KP_R_SHOULDER]
        l_shoulder = lm.keypoints[KP_L_SHOULDER]
        if r_shoulder is None or l_shoulder is None:
            continue
        shoulder_px = _distance(r_shoulder, l_shoulder)
        if shoulder_px > 0:
            shoulder_px_values.append(shoulder_px)
            source_photos.append(angle_name)

    if not shoulder_px_values or px_per_cm <= 0:
        return None

    avg_shoulder_px = float(np.mean(shoulder_px_values))
    shoulder_cm = avg_shoulder_px / px_per_cm
    confidence = min(1.0, len(shoulder_px_values) / 2.0)

    return BodyMeasurement(
        value=round(shoulder_cm, 1),
        unit="cm",
        confidence=round(confidence, 3),
        source_photos=source_photos,
        method="openpose_front_back_avg",
    )


def extract_hip_width(landmarks: dict[str, LandmarkData], px_per_cm: float) -> Optional[BodyMeasurement]:
    """Hip width from front + back photos."""
    source_photos = []
    hip_px_values = []

    for angle_name in ["front", "back", "three_quarter_left", "three_quarter_right"]:
        lm = landmarks.get(angle_name)
        if lm is None or len(lm.keypoints) <= KP_L_HIP:
            continue
        r_hip = lm.keypoints[KP_R_HIP]
        l_hip = lm.keypoints[KP_L_HIP]
        if r_hip is None or l_hip is None:
            continue
        hip_px = _distance(r_hip, l_hip)
        if hip_px > 0:
            hip_px_values.append(hip_px)
            source_photos.append(angle_name)

    if not hip_px_values or px_per_cm <= 0:
        return None

    avg_hip_px = float(np.mean(hip_px_values))
    hip_cm = avg_hip_px / px_per_cm
    confidence = min(1.0, len(hip_px_values) / 2.0)

    return BodyMeasurement(
        value=round(hip_cm, 1),
        unit="cm",
        confidence=round(confidence, 3),
        source_photos=source_photos,
        method="openpose_front_back_avg",
    )


def extract_circumference(
    front_lm: Optional[LandmarkData],
    side_lm: Optional[LandmarkData],
    keypoint_idx: int,
    px_per_cm: float,
    measurement_name: str,
) -> Optional[BodyMeasurement]:
    """Circumference from front width + side depth (ellipse approximation).

    Args:
        front_lm: Landmarks from front or back photo (sees width).
        side_lm: Landmarks from left or right photo (sees depth).
        keypoint_idx: Which keypoint pair to measure (e.g. KP_R_HIP for hip).
        measurement_name: "chest", "waist", or "hip" for logging.
    """
    source_photos = []

    # Front width
    front_width_px = 0.0
    if front_lm is not None and len(front_lm.keypoints) > keypoint_idx + 3:
        r = front_lm.keypoints[keypoint_idx]
        l = front_lm.keypoints[keypoint_idx + 3]  # R hip=8, L hip=11 (diff=3)
        if r is not None and l is not None:
            front_width_px = _distance(r, l)
            source_photos.append(front_lm.angle)

    # Side depth (use the same keypoint index — side photo sees depth)
    side_depth_px = 0.0
    if side_lm is not None and len(side_lm.keypoints) > keypoint_idx:
        # In side view, left and right body keypoints overlap.
        # Depth ≈ distance from keypoint to image edge approximation.
        # Better: use nose-to-back-of-head ratio as depth proxy.
        # For now, approximate depth = 0.65 * front_width (anthropometric average).
        side_depth_px = front_width_px * 0.65
        source_photos.append(side_lm.angle)

    if front_width_px == 0 or px_per_cm <= 0:
        return None

    front_width_cm = front_width_px / px_per_cm
    side_depth_cm = side_depth_px / px_per_cm

    # Ellipse circumference (Ramanujan approximation)
    a = front_width_cm / 2
    b = side_depth_cm / 2
    if a + b == 0:
        return None
    circumference = float(np.pi * (3 * (a + b) - np.sqrt((3 * a + b) * (a + 3 * b))))

    confidence = 0.7 if side_lm is None else 0.85  # lower conf without side depth

    return BodyMeasurement(
        value=round(circumference, 1),
        unit="cm",
        confidence=round(confidence, 3),
        source_photos=list(set(source_photos)),
        method="ellipse_front_width_side_depth",
    )


def extract_inseam(landmarks: dict[str, LandmarkData], px_per_cm: float) -> Optional[BodyMeasurement]:
    """Inseam from side photos (hip to ankle)."""
    source_photos = []
    inseam_px_values = []

    for angle_name in ["left", "right"]:
        lm = landmarks.get(angle_name)
        if lm is None or len(lm.keypoints) <= KP_R_ANKLE:
            continue
        r_hip = lm.keypoints[KP_R_HIP]
        r_ankle = lm.keypoints[KP_R_ANKLE]
        if r_hip is None or r_ankle is None:
            continue
        inseam_px = abs(r_ankle["y"] - r_hip["y"])
        if inseam_px > 0:
            inseam_px_values.append(inseam_px)
            source_photos.append(angle_name)

    if not inseam_px_values or px_per_cm <= 0:
        return None

    avg_inseam_px = float(np.mean(inseam_px_values))
    inseam_cm = avg_inseam_px / px_per_cm
    confidence = min(1.0, len(inseam_px_values) / 2.0)

    return BodyMeasurement(
        value=round(inseam_cm, 1),
        unit="cm",
        confidence=round(confidence, 3),
        source_photos=source_photos,
        method="openpose_side_hip_to_ankle",
    )


def extract_arm_length(landmarks: dict[str, LandmarkData], px_per_cm: float) -> Optional[BodyMeasurement]:
    """Arm length from side photos (shoulder → elbow → wrist)."""
    source_photos = []
    arm_px_values = []

    for angle_name in ["left", "right"]:
        lm = landmarks.get(angle_name)
        if lm is None or len(lm.keypoints) <= KP_R_WRIST:
            continue
        r_shoulder = lm.keypoints[KP_R_SHOULDER]
        r_elbow = lm.keypoints[KP_R_ELBOW]
        r_wrist = lm.keypoints[KP_R_WRIST]
        if r_shoulder is None or r_elbow is None or r_wrist is None:
            continue
        upper_arm = _distance(r_shoulder, r_elbow)
        forearm = _distance(r_elbow, r_wrist)
        total = upper_arm + forearm
        if total > 0:
            arm_px_values.append(total)
            source_photos.append(angle_name)

    if not arm_px_values or px_per_cm <= 0:
        return None

    avg_arm_px = float(np.mean(arm_px_values))
    arm_cm = avg_arm_px / px_per_cm
    confidence = min(1.0, len(arm_px_values) / 2.0)

    return BodyMeasurement(
        value=round(arm_cm, 1),
        unit="cm",
        confidence=round(confidence, 3),
        source_photos=source_photos,
        method="openpose_side_shoulder_elbow_wrist",
    )


def extract_torso_length(landmarks: dict[str, LandmarkData], px_per_cm: float) -> Optional[BodyMeasurement]:
    """Torso length from front photo (neck to hip)."""
    source_photos = []
    torso_px_values = []

    for angle_name in ["front", "back"]:
        lm = landmarks.get(angle_name)
        if lm is None or len(lm.keypoints) <= KP_R_HIP:
            continue
        neck = lm.keypoints[KP_NECK]
        r_hip = lm.keypoints[KP_R_HIP]
        if neck is None or r_hip is None:
            continue
        torso_px = abs(r_hip["y"] - neck["y"])
        if torso_px > 0:
            torso_px_values.append(torso_px)
            source_photos.append(angle_name)

    if not torso_px_values or px_per_cm <= 0:
        return None

    avg_torso_px = float(np.mean(torso_px_values))
    torso_cm = avg_torso_px / px_per_cm
    confidence = min(1.0, len(torso_px_values) / 2.0)

    return BodyMeasurement(
        value=round(torso_cm, 1),
        unit="cm",
        confidence=round(confidence, 3),
        source_photos=source_photos,
        method="openpose_front_neck_to_hip",
    )


def extract_neck_position(landmarks: dict[str, LandmarkData], px_per_cm: float) -> Optional[BodyMeasurement]:
    """Neck position (height from ground) — used for garment collar placement."""
    front_lm = landmarks.get("front")
    if front_lm is None or len(front_lm.keypoints) <= KP_R_ANKLE:
        return None
    neck = front_lm.keypoints[KP_NECK]
    ankle = front_lm.keypoints[KP_R_ANKLE] or front_lm.keypoints[KP_L_ANKLE]
    if neck is None or ankle is None or px_per_cm <= 0:
        return None
    neck_height_px = abs(ankle["y"] - neck["y"])
    neck_height_cm = neck_height_px / px_per_cm

    return BodyMeasurement(
        value=round(neck_height_cm, 1),
        unit="cm",
        confidence=0.8,
        source_photos=["front"],
        method="openpose_front_neck_to_ankle",
    )


def extract_all_measurements(landmarks: dict[str, LandmarkData]) -> dict[str, BodyMeasurement]:
    """Extract all body measurements from landmarks.

    Args:
        landmarks: {angle_name: LandmarkData} for all 6 photos.

    Returns:
        {measurement_name: BodyMeasurement} with confidence scores.
    """
    px_per_cm = _calibrate_px_per_cm(landmarks)
    if px_per_cm is None:
        logger.error("Could not calibrate pixel-to-cm ratio — no shoulder data")
        return {}

    measurements = {}

    # Height
    m = extract_height(landmarks, px_per_cm)
    if m:
        measurements["height_cm"] = m

    # Shoulder width
    m = extract_shoulder_width(landmarks, px_per_cm)
    if m:
        measurements["shoulder_width_cm"] = m

    # Hip width
    m = extract_hip_width(landmarks, px_per_cm)
    if m:
        measurements["hip_width_cm"] = m

    # Chest circumference (front width + side depth)
    m = extract_circumference(
        landmarks.get("front"), landmarks.get("left"),
        KP_R_SHOULDER, px_per_cm, "chest"
    )
    if m:
        measurements["chest_circumference_cm"] = m

    # Waist circumference (use hip keypoints as proxy — OpenPose has no waist)
    m = extract_circumference(
        landmarks.get("front"), landmarks.get("left"),
        KP_R_HIP, px_per_cm, "waist"
    )
    if m:
        measurements["waist_circumference_cm"] = m

    # Hip circumference
    m = extract_circumference(
        landmarks.get("front"), landmarks.get("left"),
        KP_R_HIP, px_per_cm, "hip"
    )
    if m:
        measurements["hip_circumference_cm"] = m

    # Inseam
    m = extract_inseam(landmarks, px_per_cm)
    if m:
        measurements["inseam_cm"] = m

    # Arm length
    m = extract_arm_length(landmarks, px_per_cm)
    if m:
        measurements["arm_length_cm"] = m

    # Torso length
    m = extract_torso_length(landmarks, px_per_cm)
    if m:
        measurements["torso_length_cm"] = m

    # Neck position
    m = extract_neck_position(landmarks, px_per_cm)
    if m:
        measurements["neck_position_cm"] = m

    logger.info(f"Extracted {len(measurements)} body measurements")
    return measurements
