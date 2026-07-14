"""Digital Human Pipeline — orchestrates all 5 stages.

Entry point: DigitalHumanPipeline.process(photos) → BodyProfile

The pipeline:
  Stage 1: Capture validation (blur, lighting, pose, multiple persons)
  Stage 2: Body extraction (background removal, segmentation, pose, keypoints)
  Stage 3: Measurement extraction (9 measurements with uncertainty)
  Stage 4: Profile assembly (persistent BodyProfile)
  Stage 5: Profile validation (reject bad profiles)

The BodyProfile is model-independent. Future renderers consume it
to drive try-on inference without rescanning the customer.
"""

from __future__ import annotations

import logging
from typing import Optional

from PIL import Image

from app.digital_human.body_extraction import BodyExtractor
from app.digital_human.capture_validation import validate_capture
from app.digital_human.measurement_extraction import extract_all_measurements
from app.digital_human.models import BodyProfile, PhotoAngle
from app.digital_human.profile_builder import build_profile

logger = logging.getLogger(__name__)


class DigitalHumanPipeline:
    """Transforms 6 customer photos into a persistent BodyProfile.

    Usage:
        pipeline = DigitalHumanPipeline(device="cuda")
        profile = pipeline.process(photos)
        if profile.validation_status == "approved":
            # Store profile, use for all future try-ons
        else:
            # Show validation_errors to customer
    """

    def __init__(self, device: str = "cuda"):
        self._device = device
        self._extractor = BodyExtractor(device=device)

    def process(self, photos: dict[PhotoAngle, Image.Image]) -> BodyProfile:
        """Run the full pipeline on 6 photos.

        Args:
            photos: {PhotoAngle.FRONT: PIL.Image, PhotoAngle.BACK: ..., ...}
                    Must include at least front + back + one side.

        Returns:
            BodyProfile with validation_status "approved" or "rejected".
        """
        logger.info(f"Starting digital human pipeline with {len(photos)} photos")

        # Stage 1: Quick capture validation (blur + lighting, no keypoints yet)
        validation_results = validate_capture(photos)
        early_errors = []
        for angle, result in validation_results.items():
            if not result.is_valid:
                early_errors.extend(result.errors)
                logger.warning(f"{angle.value} failed validation: {result.errors}")

        # Stage 2: Body extraction (runs ML models)
        extraction = self._extractor.extract(photos)

        # Stage 1 (continued): Now validate with keypoints (pose, multiple persons)
        keypoints_by_angle = {
            angle: extraction["keypoints_raw"][angle.value]
            for angle in photos
            if extraction["keypoints_raw"].get(angle.value) is not None
        }
        validation_results_with_kp = validate_capture(photos, keypoints_by_angle)
        for angle, result in validation_results_with_kp.items():
            for err in result.errors:
                if err not in early_errors:
                    early_errors.append(err)

        # Stage 3: Measurement extraction
        measurements = extract_all_measurements(extraction["landmarks"])

        # Stage 4 + 5: Build profile + validate
        profile = build_profile(
            landmarks=extraction["landmarks"],
            measurements=measurements,
            segmentation_masks=extraction["segmentation_masks"],
            texture_maps=extraction["texture_maps"],
        )

        # Merge any capture validation errors
        if early_errors and profile.validation_status == "approved":
            profile.validation_status = "rejected"
        profile.validation_errors = list(set(profile.validation_errors + early_errors))

        logger.info(
            f"Pipeline complete: {profile.validation_status} "
            f"({len(profile.body_measurements)} measurements, "
            f"{len(profile.validation_errors)} errors)"
        )

        return profile
