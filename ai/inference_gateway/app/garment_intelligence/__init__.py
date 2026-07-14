"""Garment Intelligence Pipeline — persistent garment profile from photos.

Converts retailer garment photos into structured, model-independent data.
Every future renderer can consume the GarmentProfile without reprocessing.
"""

from app.garment_intelligence.models import GarmentProfile
from app.garment_intelligence.pipeline import GarmentIntelligencePipeline

__all__ = ["GarmentProfile", "GarmentIntelligencePipeline"]
