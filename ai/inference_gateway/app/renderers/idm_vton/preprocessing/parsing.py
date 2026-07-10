from __future__ import annotations
import logging
from typing import Any
import numpy as np
from PIL import Image

logger = logging.getLogger(__name__)

INPAINT_LABELS = {1, 3, 5, 6, 7, 8, 9, 10, 11, 12}

class HumanParsingPreprocessor:
    def __init__(self, model_path: str | None = None):
        self._model_path = model_path
        self._model: Any = None
        self._loaded = False

    @property
    def is_ready(self) -> bool:
        return self._loaded

    def load(self) -> None:
        try:
            import torch
            from torchvision import transforms
            from transformers import SegformerForSemanticSegmentation
            self._model = SegformerForSemanticSegmentation.from_pretrained("mattmdjaga/human_parsing")
            self._torch = torch
            self._transforms = transforms.Compose([
                transforms.ToTensor(),
                transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
            ])
            self._loaded = True
            logger.info("Human parsing preprocessor loaded")
        except Exception as e:
            logger.warning(f"Failed to load human parsing model: {e}")
            self._loaded = False

    def process(self, person_image: Image.Image, width: int, height: int) -> np.ndarray:
        if not self._loaded:
            self.load()
        if self._model is None:
            return np.ones((height, width), dtype=np.uint8) * 5
        try:
            torch = self._torch
            img = person_image.convert("RGB").resize((width, height), Image.LANCZOS)
            input_tensor = self._transforms(img).unsqueeze(0)
            device = next(self._model.parameters()).device
            input_tensor = input_tensor.to(device)
            with torch.no_grad():
                outputs = self._model(input_tensor)
                logits = outputs.logits
                logits = torch.nn.functional.interpolate(logits, size=(height, width), mode="bilinear", align_corners=False)
                parsing = logits.argmax(dim=1).squeeze(0).cpu().numpy()
            return parsing.astype(np.uint8)
        except Exception as e:
            logger.warning(f"Human parsing inference failed: {e}")
            return np.ones((height, width), dtype=np.uint8) * 5

    def generate_agnostic_mask(self, parsing: np.ndarray) -> Image.Image:
        mask = np.zeros_like(parsing, dtype=np.uint8)
        for label in INPAINT_LABELS:
            mask[parsing == label] = 255
        return Image.fromarray(mask, mode="L")
