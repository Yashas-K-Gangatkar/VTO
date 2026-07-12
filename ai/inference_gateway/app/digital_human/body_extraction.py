"""Stage 2 — Body extraction.

Runs background removal, human segmentation, pose estimation,
and keypoint extraction on each of the 6 photos.

Uses the same preprocessing models as the IDM-VTON renderer
to keep the ML stack consistent.
"""

from __future__ import annotations

import logging
from typing import Optional

import numpy as np
from PIL import Image

from app.digital_human.models import LandmarkData, PhotoAngle
from app.renderers.idm_vton.preprocessing import HumanParsingPreprocessor, PoseEstimator

logger = logging.getLogger(__name__)


class BodyExtractor:
    """Extracts body data from photos: segmentation, pose, keypoints.

    All models are lazy-loaded and shared across photos.
    """

    def __init__(self, device: str = "cuda"):
        self._parsing = HumanParsingPreprocessor(device=device)
        self._pose = PoseEstimator(device=device)

    def extract(self, photos: dict[PhotoAngle, Image.Image]) -> dict:
        """Run full extraction on all 6 photos.

        Returns dict with:
          - landmarks: {angle: LandmarkData}
          - segmentation_masks: {angle: PIL Image}
          - texture_maps: {angle: PIL Image (background removed)}
          - keypoints_raw: {angle: dict or None}
        """
        landmarks = {}
        segmentation_masks = {}
        texture_maps = {}
        keypoints_raw = {}

        for angle, image in photos.items():
            logger.info(f"Extracting body data from {angle.value} photo")

            # 1. Background removal (rembg)
            texture = self._remove_background(image)
            texture_maps[angle.value] = texture

            # 2. Human segmentation (segformer)
            parsed = self._parsing.parse(image)
            # Convert to binary mask: person (non-background) = 255
            seg_mask = Image.fromarray((parsed > 0).astype(np.uint8) * 255)
            segmentation_masks[angle.value] = seg_mask

            # 3. Pose estimation + keypoint extraction
            kp_data = self._pose.extract_keypoints(image)
            keypoints_raw[angle.value] = kp_data

            if kp_data is not None:
                confidence = self._compute_keypoint_confidence(kp_data["keypoints"])
                landmarks[angle.value] = LandmarkData(
                    angle=angle.value,
                    keypoints=kp_data["keypoints"],
                    confidence=confidence,
                )
            else:
                landmarks[angle.value] = LandmarkData(
                    angle=angle.value,
                    keypoints=[None] * 18,
                    confidence=0.0,
                )

        return {
            "landmarks": landmarks,
            "segmentation_masks": segmentation_masks,
            "texture_maps": texture_maps,
            "keypoints_raw": keypoints_raw,
        }

    def _remove_background(self, image: Image.Image) -> Image.Image:
        """Remove background using rembg. Returns RGBA image."""
        try:
            from rembg import remove
            return remove(image.convert("RGB"))
        except ImportError:
            logger.warning("rembg not installed, returning original image")
            return image.convert("RGBA")

    def _compute_keypoint_confidence(self, keypoints: list) -> float:
        """Fraction of detected keypoints (non-None out of 18)."""
        if not keypoints:
            return 0.0
        detected = sum(1 for kp in keypoints if kp is not None)
        return detected / 18.0
