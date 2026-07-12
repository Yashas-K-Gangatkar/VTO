"""Stage 4 — Profile builder + Stage 5 — Validation.

Assembles the persistent BodyProfile and validates it.
Rejects profiles with low confidence or missing critical measurements.
"""

from __future__ import annotations

import logging
from typing import Optional

from app.digital_human.models import BodyProfile, BodyMeasurement, LandmarkData, ValidationErrorCode

logger = logging.getLogger(__name__)

# Overall confidence threshold — below this, the profile is rejected
MIN_OVERALL_CONFIDENCE = 0.7

# Critical measurements — if any are missing, profile is rejected
CRITICAL_MEASUREMENTS = ["height_cm", "shoulder_width_cm"]


def build_profile(
    landmarks: dict[str, LandmarkData],
    measurements: dict[str, BodyMeasurement],
    segmentation_masks: dict[str, object],  # PIL Images (paths assigned later)
    texture_maps: dict[str, object],
    body_embedding: Optional[list[float]] = None,
) -> BodyProfile:
    """Assemble the persistent BodyProfile from extracted data."""
    profile = BodyProfile(
        body_measurements=measurements,
        landmarks=landmarks,
        body_embedding=body_embedding or [],
    )

    # Validate
    errors = validate_profile(profile)
    if errors:
        profile.validation_status = "rejected"
        profile.validation_errors = errors
        logger.warning(f"Body profile rejected: {errors}")
    else:
        profile.validation_status = "approved"
        logger.info("Body profile approved")

    return profile


def validate_profile(profile: BodyProfile) -> list[str]:
    """Stage 5 — validate the profile. Returns list of error codes."""
    errors = []

    # Check critical measurements exist
    for critical in CRITICAL_MEASUREMENTS:
        if critical not in profile.body_measurements:
            errors.append(ValidationErrorCode.E_MISSING_BODY_PARTS.value)
            break  # one error code is enough

    # Check overall confidence
    if profile.body_measurements:
        confidences = [m.confidence for m in profile.body_measurements.values()]
        avg_confidence = sum(confidences) / len(confidences)
        if avg_confidence < MIN_OVERALL_CONFIDENCE:
            errors.append(ValidationErrorCode.E_LOW_CONFIDENCE.value)

    # Check landmark detection — if all 6 angles have 0 confidence, no person detected
    if profile.landmarks:
        all_zero = all(lm.confidence == 0.0 for lm in profile.landmarks.values())
        if all_zero:
            errors.append(ValidationErrorCode.E_NO_PERSON.value)

    return errors
