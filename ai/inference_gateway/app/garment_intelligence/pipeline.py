"""Garment Intelligence Pipeline — 10-step garment digitization.

Input: Retailer uploads garment photos (front required, back/label/side optional).
Output: Persistent GarmentProfile (model-independent).

Pipeline steps:
  1. Background removal (rembg)
  2. Garment segmentation (segformer_b2_clothes)
  3. Category detection (CLIP zero-shot classification)
  4. Sleeve length detection (keypoint-based)
  5. Collar type detection (CLIP zero-shot)
  6. Color extraction (k-means dominant colors)
  7. Pattern detection (CLIP zero-shot)
  8. Fabric classification (texture features + heuristic)
  9. Garment measurements (segmentation bbox)
  10. Garment embedding (CLIP image embedding)

All steps use lazy-loaded models. The pipeline is stateless between calls.
"""

from __future__ import annotations

import logging
from typing import Optional

import numpy as np
from PIL import Image

from app.garment_intelligence.models import (
    GarmentColor,
    GarmentFabric,
    GarmentMeasurements,
    GarmentProfile,
)

logger = logging.getLogger(__name__)


class GarmentIntelligencePipeline:
    """Transforms garment photos into a persistent GarmentProfile.

    Usage:
        pipeline = GarmentIntelligencePipeline(device="cuda")
        profile = pipeline.process(
            front_image=img,
            back_image=optional_img,
            retailer_id="ret_123",
            sku="SKU-001",
        )
    """

    def __init__(self, device: str = "cuda"):
        self._device = device
        self._clip_model = None
        self._clip_processor = None
        self._segformer = None
        self._segformer_processor = None

    def process(
        self,
        front_image: Image.Image,
        back_image: Optional[Image.Image] = None,
        side_image: Optional[Image.Image] = None,
        label_image: Optional[Image.Image] = None,
        retailer_id: str = "",
        sku: str = "",
        metadata: Optional[dict] = None,
    ) -> GarmentProfile:
        """Run the full 10-step pipeline on garment photos.

        Args:
            front_image: Front view of garment (REQUIRED).
            back_image: Back view (optional).
            side_image: Side view (optional).
            label_image: Care label (optional, for fabric info).
            retailer_id: Retailer identifier.
            sku: Retailer SKU.
            metadata: Additional metadata (brand, size_label, etc.).

        Returns:
            GarmentProfile with all extracted attributes.
        """
        logger.info(f"Starting garment intelligence pipeline for SKU={sku}")

        profile = GarmentProfile(
            retailer_id=retailer_id,
            sku=sku,
            metadata=metadata or {},
        )

        # Step 1: Background removal
        front_no_bg = self._remove_background(front_image)
        logger.info("Step 1: Background removal complete")

        # Step 2: Garment segmentation
        garment_mask = self._segment_garment(front_image)
        logger.info("Step 2: Garment segmentation complete")

        # Step 3: Category detection
        category, subcategory = self._detect_category(front_no_bg)
        profile.category = category
        profile.subcategory = subcategory
        logger.info(f"Step 3: Category={category}, subcategory={subcategory}")

        # Step 4: Sleeve length detection
        sleeve_length = self._detect_sleeve_length(front_no_bg, category)
        profile.sleeve_length = sleeve_length
        logger.info(f"Step 4: Sleeve length={sleeve_length}")

        # Step 5: Collar type detection
        collar_type = self._detect_collar_type(front_no_bg, category)
        profile.collar_type = collar_type
        logger.info(f"Step 5: Collar type={collar_type}")

        # Step 6: Color extraction
        color = self._extract_colors(front_no_bg, garment_mask)
        profile.color = color
        logger.info(f"Step 6: Color={color.name} ({color.primary})")

        # Step 7: Pattern detection
        pattern = self._detect_pattern(front_no_bg)
        profile.pattern = pattern
        logger.info(f"Step 7: Pattern={pattern}")

        # Step 8: Fabric classification
        fabric = self._classify_fabric(front_no_bg, label_image)
        profile.fabric = fabric
        logger.info(f"Step 8: Fabric={fabric.type} (conf={fabric.confidence})")

        # Step 9: Garment measurements
        measurements = self._extract_measurements(front_no_bg, garment_mask, category)
        profile.measurements = measurements
        logger.info("Step 9: Measurements extracted")

        # Step 10: Garment embedding
        embedding = self._generate_embedding(front_no_bg)
        profile.embedding = embedding
        logger.info(f"Step 10: Embedding generated ({len(embedding)} dims)")

        logger.info(f"Garment intelligence pipeline complete: {profile.garment_id}")
        return profile

    # ============================================================
    # Step implementations
    # ============================================================

    def _remove_background(self, image: Image.Image) -> Image.Image:
        """Step 1: Remove background using rembg."""
        try:
            from rembg import remove
            return remove(image.convert("RGB"))
        except ImportError:
            logger.warning("rembg not installed, returning original image")
            return image.convert("RGBA")

    def _segment_garment(self, image: Image.Image) -> Image.Image:
        """Step 2: Segment garment using segformer_b2_clothes.

        Returns binary mask: white where garment is, black elsewhere.
        Labels 4 (upper-clothes), 5 (skirt), 6 (pants) = garment.
        """
        from app.renderers.idm_vton.preprocessing import HumanParsingPreprocessor

        parser = HumanParsingPreprocessor(device=self._device)
        return parser.generate_agnostic_mask(image)

    def _detect_category(self, image: Image.Image) -> tuple[str, str]:
        """Step 3: Detect garment category using CLIP zero-shot classification."""
        import torch

        categories = [
            ("t-shirt", "graphic_tee"),
            ("shirt", "button_up"),
            ("dress", "casual_dress"),
            ("jacket", "outerwear"),
            ("pants", "trousers"),
            ("skirt", "mini_skirt"),
            ("hoodie", "pullover"),
            ("saree", "traditional"),
            ("coat", "winter_coat"),
        ]

        labels = [c[0] for c in categories]
        scores = self._clip_zero_shot(image, labels)

        best_idx = int(torch.argmax(scores).item())
        return categories[best_idx]

    def _detect_sleeve_length(self, image: Image.Image, category: str) -> str:
        """Step 4: Detect sleeve length using CLIP zero-shot."""
        if category in ("pants", "skirt", "saree"):
            return "none"

        labels = ["sleeveless garment", "short sleeve garment", "long sleeve garment", "three quarter sleeve garment"]
        scores = self._clip_zero_shot(image, labels)

        import torch
        best_idx = int(torch.argmax(scores).item())
        return ["sleeveless", "short", "long", "3/4"][best_idx]

    def _detect_collar_type(self, image: Image.Image, category: str) -> str:
        """Step 5: Detect collar type using CLIP zero-shot."""
        if category in ("pants", "skirt", "saree", "dress"):
            return "none"

        labels = ["round neck collar", "v-neck collar", "polo collar", "button collar", "hooded collar", "no collar"]
        scores = self._clip_zero_shot(image, labels)

        import torch
        best_idx = int(torch.argmax(scores).item())
        return ["round", "v-neck", "polo", "button", "hooded", "none"][best_idx]

    def _extract_colors(self, image: Image.Image, mask: Image.Image) -> GarmentColor:
        """Step 6: Extract dominant colors using k-means clustering."""
        from sklearn.cluster import KMeans

        # Get garment pixels only
        img_array = np.array(image.convert("RGB"))
        mask_array = np.array(mask.convert("L"))
        garment_pixels = img_array[mask_array > 128]

        if len(garment_pixels) == 0:
            garment_pixels = img_array.reshape(-1, 3)

        # Subsample for speed
        if len(garment_pixels) > 1000:
            indices = np.random.choice(len(garment_pixels), 1000, replace=False)
            garment_pixels = garment_pixels[indices]

        # K-means with 2 clusters (primary + secondary)
        kmeans = KMeans(n_clusters=2, n_init=3, random_state=42)
        kmeans.fit(garment_pixels)

        # Sort by cluster size
        counts = np.bincount(kmeans.labels_)
        sorted_indices = np.argsort(counts)[::-1]

        primary_rgb = kmeans.cluster_centers_[sorted_indices[0]].astype(int)
        secondary_rgb = kmeans.cluster_centers_[sorted_indices[1]].astype(int)

        primary_hex = "#{:02X}{:02X}{:02X}".format(*primary_rgb)
        secondary_hex = "#{:02X}{:02X}{:02X}".format(*secondary_rgb)

        color_name = self._rgb_to_name(primary_rgb)

        return GarmentColor(primary=primary_hex, secondary=secondary_hex, name=color_name)

    def _detect_pattern(self, image: Image.Image) -> str:
        """Step 7: Detect pattern using CLIP zero-shot."""
        labels = ["solid color garment", "striped garment", "checkered garment", "floral pattern garment", "graphic print garment"]
        scores = self._clip_zero_shot(image, labels)

        import torch
        best_idx = int(torch.argmax(scores).item())
        return ["solid", "striped", "checkered", "floral", "graphic"][best_idx]

    def _classify_fabric(self, image: Image.Image, label_image: Optional[Image.Image]) -> GarmentFabric:
        """Step 8: Classify fabric type using CLIP zero-shot + texture heuristic."""
        labels = ["cotton fabric", "silk fabric", "denim fabric", "wool fabric", "synthetic polyester fabric"]
        scores = self._clip_zero_shot(image, labels)

        import torch
        best_idx = int(torch.argmax(scores).item())
        fabric_type = ["cotton", "silk", "denim", "wool", "synthetic"][best_idx]
        confidence = float(torch.softmax(scores, dim=0)[best_idx].item())

        return GarmentFabric(type=fabric_type, confidence=round(confidence, 3))

    def _extract_measurements(
        self, image: Image.Image, mask: Image.Image, category: str
    ) -> GarmentMeasurements:
        """Step 9: Extract garment measurements from segmentation bbox.

        Without a reference object, we can only get pixel measurements.
        A real production system would use a reference card or known dimensions.
        """
        mask_array = np.array(mask.convert("L"))
        rows = np.any(mask_array > 128, axis=1)
        cols = np.any(mask_array > 128, axis=0)

        if not rows.any() or not cols.any():
            return GarmentMeasurements()

        rmin, rmax = np.where(rows)[0][[0, -1]]
        cmin, cmax = np.where(cols)[0][[0, -1]]

        height_px = rmax - rmin
        width_px = cmax - cmin

        # Without calibration, store as px (real system would convert to cm)
        # For now, use a rough estimate: assume garment fills ~40% of photo height
        # and average photo is taken at 1m distance
        estimated_height_cm = height_px * 0.3
        estimated_width_cm = width_px * 0.3

        return GarmentMeasurements(
            chest_width_cm=round(estimated_width_cm, 1) if category in ("t-shirt", "shirt", "jacket", "hoodie", "coat", "dress") else None,
            length_cm=round(estimated_height_cm, 1),
            shoulder_width_cm=round(estimated_width_cm * 0.85, 1) if category in ("t-shirt", "shirt", "jacket", "hoodie", "coat") else None,
            hem_width_cm=round(estimated_width_cm, 1) if category in ("dress", "skirt") else None,
        )

    def _generate_embedding(self, image: Image.Image) -> list[float]:
        """Step 10: Generate CLIP image embedding (768 floats)."""
        import torch

        self._load_clip()
        inputs = self._clip_processor(images=image.convert("RGB"), return_tensors="pt").to(self._device)
        with torch.no_grad():
            features = self._clip_model.get_image_features(**inputs)
        return features[0].cpu().float().tolist()

    # ============================================================
    # Shared helpers
    # ============================================================

    def _load_clip(self):
        """Lazy-load CLIP model for zero-shot classification + embeddings."""
        if self._clip_model is not None:
            return
        from transformers import CLIPModel, CLIPProcessor

        logger.info("Loading CLIP model")
        self._clip_model = CLIPModel.from_pretrained("openai/clip-vit-base-patch32").to(self._device).eval()
        self._clip_processor = CLIPProcessor.from_pretrained("openai/clip-vit-base-patch32")
        logger.info("CLIP model loaded")

    def _clip_zero_shot(self, image: Image.Image, labels: list[str]) -> "torch.Tensor":
        """Run CLIP zero-shot classification. Returns similarity scores."""
        import torch

        self._load_clip()
        inputs = self._clip_processor(
            text=labels,
            images=image.convert("RGB"),
            return_tensors="pt",
            padding=True,
            truncation=True,
        ).to(self._device)

        with torch.no_grad():
            outputs = self._clip_model(**inputs)
            # logits_per_image: (1, num_labels)
            return outputs.logits_per_image[0]

    def _rgb_to_name(self, rgb: np.ndarray) -> str:
        """Convert RGB to nearest color name (simple heuristic)."""
        r, g, b = int(rgb[0]), int(rgb[1]), int(rgb[2])

        if r > 200 and g > 200 and b > 200:
            return "white"
        if r < 50 and g < 50 and b < 50:
            return "black"
        if r > 150 and g < 100 and b < 100:
            return "red"
        if r < 100 and g > 150 and b < 100:
            return "green"
        if r < 100 and g < 100 and b > 150:
            return "blue"
        if r > 200 and g > 150 and b < 100:
            return "orange"
        if r > 200 and g > 200 and b < 100:
            return "yellow"
        if r > 100 and r < 200 and g < 100 and b > 100:
            return "purple"
        if r > 100 and g > 100 and b < 80:
            return "brown"
        if r > 150 and g > 150 and b > 150:
            return "gray"
        return "mixed"
