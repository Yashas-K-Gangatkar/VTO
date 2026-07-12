"""Data models for the persistent garment profile.

Model-independent. No renderer-specific code.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional
from uuid import uuid4
from datetime import datetime, timezone


@dataclass
class GarmentColor:
    """Extracted garment color."""
    primary: str  # hex, e.g. "#FF5733"
    secondary: Optional[str] = None
    name: str = ""  # human-readable, e.g. "orange"


@dataclass
class GarmentFabric:
    """Fabric classification with confidence."""
    type: str  # cotton, silk, denim, wool, synthetic
    confidence: float  # 0.0 to 1.0


@dataclass
class GarmentMeasurements:
    """Physical garment measurements in cm."""
    chest_width_cm: Optional[float] = None
    length_cm: Optional[float] = None
    sleeve_length_cm: Optional[float] = None
    shoulder_width_cm: Optional[float] = None
    hem_width_cm: Optional[float] = None


@dataclass
class GarmentProfile:
    """The persistent, model-independent garment profile.

    Created once per retailer SKU. Survives forever.
    Every future renderer consumes this profile.
    """
    garment_id: str = field(default_factory=lambda: str(uuid4()))
    version: int = 1
    created_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    updated_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())

    # Retailer metadata
    retailer_id: str = ""
    sku: str = ""

    # Classification
    category: str = ""  # t-shirt, shirt, dress, jacket, pants, skirt, hoodie, saree, coat
    subcategory: str = ""

    # Visual attributes
    color: Optional[GarmentColor] = None
    pattern: str = ""  # solid, striped, checkered, floral, graphic
    sleeve_length: str = ""  # short, long, sleeveless, 3/4
    collar_type: str = ""  # round, v-neck, polo, button, hooded, none

    # Fabric
    fabric: Optional[GarmentFabric] = None

    # Physical measurements
    measurements: Optional[GarmentMeasurements] = None

    # Texture maps (S3 URLs or local paths)
    texture_maps: dict[str, str] = field(default_factory=dict)  # {"front": "s3://...", "back": "s3://..."}

    # CLIP embedding for similarity search (768 floats)
    embedding: list[float] = field(default_factory=list)

    # Additional metadata
    metadata: dict = field(default_factory=dict)  # brand, size_label, etc.

    def to_dict(self) -> dict:
        """Serialize to JSON-compatible dict."""
        return {
            "garment_id": self.garment_id,
            "version": self.version,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "retailer_id": self.retailer_id,
            "sku": self.sku,
            "category": self.category,
            "subcategory": self.subcategory,
            "color": {
                "primary": self.color.primary,
                "secondary": self.color.secondary,
                "name": self.color.name,
            } if self.color else None,
            "pattern": self.pattern,
            "sleeve_length": self.sleeve_length,
            "collar_type": self.collar_type,
            "fabric": {
                "type": self.fabric.type,
                "confidence": round(self.fabric.confidence, 3),
            } if self.fabric else None,
            "measurements": {
                "chest_width_cm": self.measurements.chest_width_cm,
                "length_cm": self.measurements.length_cm,
                "sleeve_length_cm": self.measurements.sleeve_length_cm,
                "shoulder_width_cm": self.measurements.shoulder_width_cm,
                "hem_width_cm": self.measurements.hem_width_cm,
            } if self.measurements else None,
            "texture_maps": self.texture_maps,
            "embedding_len": len(self.embedding),
            "metadata": self.metadata,
        }
