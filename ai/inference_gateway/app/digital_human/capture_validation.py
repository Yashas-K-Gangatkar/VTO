"""Stage 1 — Capture validation.

Validates the 6 input photos before any ML processing.
Rejects bad inputs early with machine-readable error codes.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Optional

import cv2
import numpy as np
from PIL import Image

from app.digital_human.models import PhotoAngle, ValidationErrorCode

logger = logging.getLogger(__name__)

# Thresholds (tuned empirically — adjust based on real-world testing)
BLUR_LAPLACIAN_THRESHOLD = 100.0
BRIGHTNESS_MIN = 50
BRIGHTNESS_MAX = 220
SHOULDER_ANGLE_MAX_DEGREES = 15.0


@dataclass
class ValidationResult:
    is_valid: bool
    errors: list[str]
    metrics: dict  # blur_score, brightness, etc.


def detect_blur(image: Image.Image) -> float:
    """Laplacian variance — higher = sharper. Below 100 = blurry."""
    gray = cv2.cvtColor(np.array(image.convert("RGB")), cv2.COLOR_RGB2GRAY)
    return float(cv2.Laplacian(gray, cv2.CV_64F).var())


def detect_brightness(image: Image.Image) -> float:
    """Mean pixel brightness (0-255)."""
    gray = cv2.cvtColor(np.array(image.convert("RGB")), cv2.COLOR_RGB2GRAY)
    return float(gray.mean())


def detect_multiple_persons(keypoints_data: Optional[dict]) -> bool:
    """Check if OpenPose detected more than one person."""
    if keypoints_data is None:
        return False
    return keypoints_data.get("num_persons", 1) > 1


def check_shoulder_angle(keypoints: list) -> Optional[float]:
    """Returns shoulder angle in degrees, or None if shoulders not visible.

    OpenPose indices: 2=R shoulder, 5=L shoulder.
    Angle > 15° from horizontal means the person is tilting.
    """
    if len(keypoints) < 6:
        return None
    r_shoulder = keypoints[2]
    l_shoulder = keypoints[5]
    if r_shoulder is None or l_shoulder is None:
        return None
    dx = l_shoulder["x"] - r_shoulder["x"]
    dy = l_shoulder["y"] - r_shoulder["y"]
    if dx == 0:
        return 90.0
    angle = float(np.degrees(np.arctan(abs(dy) / abs(dx))))
    return angle


def validate_photo(
    image: Image.Image,
    angle: PhotoAngle,
    keypoints_data: Optional[dict] = None,
) -> ValidationResult:
    """Validate a single photo. Returns errors + metrics."""
    errors = []
    metrics = {}

    # Blur check
    blur_score = detect_blur(image)
    metrics["blur_score"] = blur_score
    if blur_score < BLUR_LAPLACIAN_THRESHOLD:
        errors.append(ValidationErrorCode.E_MOTION_BLUR.value)

    # Lighting check
    brightness = detect_brightness(image)
    metrics["brightness"] = brightness
    if brightness < BRIGHTNESS_MIN or brightness > BRIGHTNESS_MAX:
        errors.append(ValidationErrorCode.E_POOR_LIGHTING.value)

    # Multiple persons check (requires keypoints)
    if keypoints_data is not None:
        if detect_multiple_persons(keypoints_data):
            errors.append(ValidationErrorCode.E_MULTIPLE_PEOPLE.value)

        # Keypoint confidence — if no keypoints, person not detected
        if keypoints_data is None or not keypoints_data.get("keypoints"):
            errors.append(ValidationErrorCode.E_NO_PERSON.value)
        else:
            # Check shoulder angle for pose validation
            angle_val = check_shoulder_angle(keypoints_data["keypoints"])
            if angle_val is not None:
                metrics["shoulder_angle"] = angle_val
                if angle_val > SHOULDER_ANGLE_MAX_DEGREES:
                    errors.append(ValidationErrorCode.E_INCORRECT_POSE.value)

    return ValidationResult(
        is_valid=len(errors) == 0,
        errors=errors,
        metrics=metrics,
    )


def validate_capture(
    photos: dict[PhotoAngle, Image.Image],
    keypoints_by_angle: Optional[dict[PhotoAngle, dict]] = None,
) -> dict[PhotoAngle, ValidationResult]:
    """Validate all 6 photos. Returns per-angle results."""
    if keypoints_by_angle is None:
        keypoints_by_angle = {}

    results = {}
    for angle, image in photos.items():
        kp = keypoints_by_angle.get(angle)
        results[angle] = validate_photo(image, angle, kp)
        if not results[angle].is_valid:
            logger.warning(f"{angle.value}: validation failed — {results[angle].errors}")

    return results
