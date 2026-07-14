"""Digital Human Pipeline — persistent body profile from 6 photos.

The profile is model-independent. Future renderers (IDM-VTON, FLUX,
CAT-VTON, future diffusion models) consume it via BodyProfile.
"""

from app.digital_human.models import BodyProfile, BodyMeasurement, PhotoAngle
from app.digital_human.pipeline import DigitalHumanPipeline

__all__ = ["BodyProfile", "BodyMeasurement", "PhotoAngle", "DigitalHumanPipeline"]
