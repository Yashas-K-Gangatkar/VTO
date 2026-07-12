"""Data models for the persistent body profile.

These are model-independent. No renderer-specific code lives here.
Future renderers consume the BodyProfile to drive try-on inference.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Optional
from uuid import uuid4
from datetime import datetime, timezone


class PhotoAngle(str, Enum):
    """The 6 standard capture angles."""
    FRONT = "front"
    BACK = "back"
    LEFT = "left"
    RIGHT = "right"
    THREE_QUARTER_LEFT = "three_quarter_left"
    THREE_QUARTER_RIGHT = "three_quarter_right"


class ValidationErrorCode(str, Enum):
    """Machine-readable validation error codes."""
    E_MOTION_BLUR = "E_MOTION_BLUR"
    E_MISSING_BODY_PARTS = "E_MISSING_BODY_PARTS"
    E_INCORRECT_POSE = "E_INCORRECT_POSE"
    E_MULTIPLE_PEOPLE = "E_MULTIPLE_PEOPLE"
    E_POOR_LIGHTING = "E_POOR_LIGHTING"
    E_LOW_CONFIDENCE = "E_LOW_CONFIDENCE"
    E_NO_PERSON = "E_NO_PERSON"


@dataclass
class BodyMeasurement:
    """A single body measurement with uncertainty metadata.

    Every measurement stores: value, unit, confidence (0-1),
    which photos it came from, and the method used.
    """
    value: float
    unit: str  # "cm", "degrees", etc.
    confidence: float  # 0.0 to 1.0
    source_photos: list[str]  # e.g. ["front", "back"]
    method: str  # e.g. "openpose_neck_to_ankle"

    def to_dict(self) -> dict:
        return {
            "value": self.value,
            "unit": self.unit,
            "confidence": round(self.confidence, 3),
            "source_photos": self.source_photos,
            "method": self.method,
        }


@dataclass
class LandmarkData:
    """Pose keypoints for a single photo angle."""
    angle: str
    keypoints: list[Optional[dict]]  # 18 keypoints: {x, y} or None
    confidence: float  # overall detection confidence 0-1

    def to_dict(self) -> dict:
        return {
            "keypoints": self.keypoints,
            "confidence": round(self.confidence, 3),
        }


@dataclass
class BodyProfile:
    """The persistent, model-independent digital body profile.

    Created once per customer. Survives forever. Every future
    renderer consumes this profile to drive try-on inference.

    The customer never rescans unless they choose to update.
    """
    body_id: str = field(default_factory=lambda: str(uuid4()))
    version: int = 1
    created_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    updated_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())

    # Stage 3 output — measurements with uncertainty
    body_measurements: dict[str, BodyMeasurement] = field(default_factory=dict)

    # Stage 2 output — landmarks per angle
    landmarks: dict[str, LandmarkData] = field(default_factory=dict)

    # Stage 2 output — segmentation mask paths (S3 URLs or local paths)
    segmentation_masks: dict[str, str] = field(default_factory=dict)

    # Stage 2 output — texture map paths (cropped person images)
    texture_maps: dict[str, str] = field(default_factory=dict)

    # Body embedding for similarity search (768 floats from CLIP)
    body_embedding: list[float] = field(default_factory=list)

    # Stage 5 output — validation
    validation_status: str = "pending"  # "approved" | "rejected" | "pending"
    validation_errors: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        """Serialize to JSON-compatible dict for storage."""
        return {
            "body_id": self.body_id,
            "version": self.version,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "body_measurements": {k: v.to_dict() for k, v in self.body_measurements.items()},
            "landmarks": {k: v.to_dict() for k, v in self.landmarks.items()},
            "segmentation_masks": self.segmentation_masks,
            "texture_maps": self.texture_maps,
            "body_embedding": self.body_embedding[:10] + ["..."] if len(self.body_embedding) > 10 else self.body_embedding,
            "validation_status": self.validation_status,
            "validation_errors": self.validation_errors,
        }
