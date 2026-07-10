from __future__ import annotations
import logging
from typing import Any
from PIL import Image

logger = logging.getLogger(__name__)

class OpenPosePreprocessor:
    def __init__(self, model_path: str | None = None):
        self._model_path = model_path
        self._detector: Any = None
        self._loaded = False

    @property
    def is_ready(self) -> bool:
        return self._loaded

    def load(self) -> None:
        try:
            from controlnet_aux import OpenposeDetector
            self._detector = OpenposeDetector.from_pretrained("lllyasviel/ControlNet")
            self._loaded = True
            logger.info("OpenPose preprocessor loaded")
        except Exception as e:
            logger.warning(f"Failed to load OpenPose: {e}")
            self._loaded = False

    def process(self, person_image: Image.Image, width: int, height: int) -> Image.Image:
        if not self._loaded:
            self.load()
        if self._detector is None:
            return Image.new("RGB", (width, height), (255, 255, 255))
        try:
            pose = self._detector(person_image, hand_and_face=False)
            return pose.resize((width, height), Image.LANCZOS).convert("RGB")
        except Exception as e:
            logger.warning(f"OpenPose inference failed: {e}")
            return Image.new("RGB", (width, height), (255, 255, 255))


class DensePosePreprocessor:
    def __init__(self, model_path: str | None = None):
        self._model_path = model_path
        self._detector: Any = None
        self._loaded = False

    @property
    def is_ready(self) -> bool:
        return self._loaded

    def load(self) -> None:
        try:
            from controlnet_aux import DenseposeDetector
            self._detector = DenseposeDetector.from_pretrained("lllyasviel/ControlNet")
            self._loaded = True
            logger.info("DensePose preprocessor loaded")
        except Exception as e:
            logger.warning(f"Failed to load DensePose: {e}")
            self._loaded = False

    def process(self, person_image: Image.Image, width: int, height: int) -> Image.Image:
        if not self._loaded:
            self.load()
        if self._detector is None:
            return Image.new("RGB", (width, height), (128, 128, 128))
        try:
            densepose = self._detector(person_image)
            return densepose.resize((width, height), Image.LANCZOS).convert("RGB")
        except Exception as e:
            logger.warning(f"DensePose inference failed: {e}")
            return Image.new("RGB", (width, height), (128, 128, 128))
