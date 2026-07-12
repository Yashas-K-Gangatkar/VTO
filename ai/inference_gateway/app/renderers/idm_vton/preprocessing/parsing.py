"""Human parsing using Segformer-B2 trained on ATR clothes dataset.

Replaces the broken mattmdjaga/human_parsing model with
mattmdjaga/segformer_b2_clothes (validated working on 2025-07-12).

Label map (ATR format):
  0=background, 1=hat, 2=hair, 3=face, 4=upper-clothes,
  5=skirt, 6=pants, 7=arm, 8=leg, 9=shoe, 10=skin

The agnostic mask (where to inpaint the new garment) is white where
labels are 4 (upper-clothes), 5 (skirt), or 6 (pants).
"""

from __future__ import annotations

import logging
from typing import Optional

import numpy as np
from PIL import Image

logger = logging.getLogger(__name__)

# ATR label constants
LABEL_BACKGROUND = 0
LABEL_HAT = 1
LABEL_HAIR = 2
LABEL_FACE = 3
LABEL_UPPER_CLOTHES = 4
LABEL_SKIRT = 5
LABEL_PANTS = 6
LABEL_ARM = 7
LABEL_LEG = 8
LABEL_SHOE = 9
LABEL_SKIN = 10

# Garment labels — these are the regions we want to inpaint
GARMENT_LABELS = {LABEL_UPPER_CLOTHES, LABEL_SKIRT, LABEL_PANTS}

# Color palette for visualization (RGB)
LABEL_PALETTE = [
    (0, 0, 0),          # 0 background
    (255, 0, 0),        # 1 hat
    (255, 85, 0),       # 2 hair
    (255, 170, 0),      # 3 face
    (255, 0, 85),       # 4 upper-clothes
    (255, 0, 170),      # 5 skirt
    (0, 255, 0),        # 6 pants
    (170, 255, 85),     # 7 arm
    (85, 255, 170),     # 8 leg
    (0, 85, 255),       # 9 shoe
    (0, 170, 255),      # 10 skin
]


class HumanParsingPreprocessor:
    """Human parsing using Segformer-B2 (mattmdjaga/segformer_b2_clothes).

    Loads lazily on first use so the gateway can boot without ML deps.
    """

    MODEL_ID = "mattmdjaga/segformer_b2_clothes"

    def __init__(self, device: str = "cuda"):
        self._device = device
        self._processor = None
        self._model = None

    def _load(self):
        if self._model is not None:
            return
        import torch
        from transformers import SegformerForSemanticSegmentation, SegformerImageProcessor

        logger.info(f"Loading human parsing model: {self.MODEL_ID}")
        self._processor = SegformerImageProcessor.from_pretrained(self.MODEL_ID)
        self._model = SegformerForSemanticSegmentation.from_pretrained(self.MODEL_ID)
        self._model.to(self._device).eval()
        logger.info("Human parsing model loaded")

    def parse(self, image: Image.Image) -> np.ndarray:
        """Run human parsing on an image.

        Args:
            image: PIL RGB image.

        Returns:
            2D numpy array of label IDs (0-10), same H/W as input image.
        """
        self._load()
        import torch

        img = image.convert("RGB")
        inputs = self._processor(images=img, return_tensors="pt").to(self._device)
        with torch.no_grad():
            outputs = self._model(**inputs)
        logits = outputs.logits[0]  # (num_labels, H, W)
        parsed = logits.argmax(0).cpu().numpy().astype(np.uint8)
        # Resize back to original image size
        parsed_img = Image.fromarray(parsed).resize(img.size, Image.NEAREST)
        return np.array(parsed_img)

    def generate_agnostic_mask(self, image: Image.Image) -> Image.Image:
        """Generate the clothing-agnostic mask.

        White (255) where the garment goes (labels 4, 5, 6).
        Black (0) everywhere else (face, arms, legs, background).

        This tells the diffusion model which regions to inpaint.
        """
        parsed = self.parse(image)
        mask = np.zeros_like(parsed, dtype=np.uint8)
        for label in GARMENT_LABELS:
            mask[parsed == label] = 255
        return Image.fromarray(mask)

    def visualize(self, parsed: np.ndarray) -> Image.Image:
        """Convert a parsing map to a color-coded image for debugging."""
        color = np.zeros((*parsed.shape, 3), dtype=np.uint8)
        for label_id, rgb in enumerate(LABEL_PALETTE):
            color[parsed == label_id] = rgb
        return Image.fromarray(color)
