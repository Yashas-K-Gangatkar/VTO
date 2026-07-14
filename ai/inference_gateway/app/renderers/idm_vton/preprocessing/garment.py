from __future__ import annotations
import logging
from typing import Any
from PIL import Image

logger = logging.getLogger(__name__)

class GarmentPreprocessor:
    def __init__(self):
        self._loaded = False

    @property
    def is_ready(self) -> bool:
        return self._loaded

    def load(self) -> None:
        try:
            from rembg import remove, new_session
            self._session = new_session("u2net")
            self._remove = remove
            self._loaded = True
            logger.info("Garment preprocessor loaded (rembg/u2net)")
        except Exception as e:
            logger.warning(f"Failed to load rembg: {e}")
            self._loaded = False

    def process(self, garment_image: Image.Image, width: int, height: int) -> Image.Image:
        if not self._loaded:
            self.load()
        img = garment_image.convert("RGB")
        if self._loaded:
            try:
                img = self._remove(img, session=self._session)
                if img.mode == "RGBA":
                    bg = Image.new("RGB", img.size, (255, 255, 255))
                    bg.paste(img, mask=img.split()[3])
                    img = bg
            except Exception as e:
                logger.warning(f"Background removal failed: {e}")
        return img.resize((width, height), Image.LANCZOS)
