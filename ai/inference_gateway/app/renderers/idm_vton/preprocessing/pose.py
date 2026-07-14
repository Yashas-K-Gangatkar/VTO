"""Pose estimation using OpenPose via controlnet_aux.

Replaces the gray placeholder Image.new("RGB", (W,H), (128,128,128))
that was in renderer.py. The pose skeleton tells the diffusion model
where the body's joints are, so the garment aligns correctly.
"""

from __future__ import annotations

import logging
from typing import Optional

import numpy as np
from PIL import Image

logger = logging.getLogger(__name__)


class PoseEstimator:
    """OpenPose pose estimator via controlnet_aux.

    Loads lazily on first use.
    """

    MODEL_ID = "lllyasviel/ControlNet"

    def __init__(self, device: str = "cuda"):
        self._device = device
        self._detector = None

    def _load(self):
        if self._detector is not None:
            return
        from controlnet_aux import OpenposeDetector

        logger.info(f"Loading OpenPose model: {self.MODEL_ID}")
        self._detector = OpenposeDetector.from_pretrained(self.MODEL_ID)
        logger.info("OpenPose model loaded")

    def estimate(self, image: Image.Image, hand_and_face: bool = False) -> Image.Image:
        """Run pose estimation on an image.

        Args:
            image: PIL RGB image.
            hand_and_face: If True, also detect hand and face keypoints.

        Returns:
            PIL RGB image with pose skeleton drawn on black background.
        """
        self._load()
        img = image.convert("RGB")
        pose_img = self._detector(img, hand_and_face=hand_and_face)
        return pose_img

    def extract_keypoints(self, image: Image.Image) -> Optional[dict]:
        """Extract raw keypoint coordinates.

        Uses OpenPose's internal body detector to get (x, y, confidence)
        for each of the 18 body keypoints.

        Returns None if no person detected.

        Keypoint indices (BODY18):
          0=nose, 1=neck, 2=R shoulder, 3=R elbow, 4=R wrist,
          5=L shoulder, 6=L elbow, 7=L wrist, 8=R hip, 9=R knee,
          10=R ankle, 11=L hip, 12=L knee, 13=L ankle,
          14=R eye, 15=L eye, 16=R ear, 17=L ear
        """
        self._load()
        img = image.convert("RGB")
        # Access the internal body estimation model
        if not hasattr(self._detector, "body_estimation"):
            self._detector.body_estimation = self._detector.body

        body = self._detector.body_estimation
        candidate, subset = body(np.array(img))

        if len(subset) == 0:
            return None

        # Take the first (highest confidence) person
        person = subset[0]
        keypoints = []
        for idx in person[:18]:
            if idx >= 0 and idx < len(candidate):
                keypoints.append(
                    {"x": float(candidate[int(idx)][0]), "y": float(candidate[int(idx)][1])}
                )
            else:
                keypoints.append(None)
        return {"keypoints": keypoints, "num_persons": len(subset)}
