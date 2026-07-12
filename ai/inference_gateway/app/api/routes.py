"""VTO API routes — body scan, garment analysis, try-on.

These endpoints work in two modes:
- Real mode (GPU available): runs actual ML pipelines
- Mock mode (no GPU): returns placeholder results

Mock mode lets the API deploy to free tiers (Render) for testing.
Set VTO_GPU_ENABLED=true to enable real inference.
"""

from __future__ import annotations

import base64
import io
import json
import logging
import os
import time
from typing import Any
from uuid import uuid4

from fastapi import APIRouter, File, Form, UploadFile
from fastapi.responses import JSONResponse, Response

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/v1", tags=["VTO"])

GPU_ENABLED = os.getenv("VTO_GPU_ENABLED", "false").lower() == "true"


def _image_to_base64(img) -> str:
    """Convert PIL Image to base64 string."""
    from PIL import Image
    if not isinstance(img, Image.Image):
        return ""
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode("utf-8")


def _base64_to_image(b64: str):
    """Convert base64 string to PIL Image."""
    from PIL import Image
    img_data = base64.b64decode(b64)
    return Image.open(io.BytesIO(img_data))


# ============================================================
# Body Scan
# ============================================================

@router.post("/body/scan")
async def scan_body(
    photos: list[UploadFile] = File(...),
    angles: str = Form("front,back,left,right,three_quarter_left,three_quarter_right"),
):
    """Scan body from 6 photos. Returns persistent BodyProfile.

    Upload 6 photos (front, back, left, right, 3/4-left, 3/4-right).
    Returns body measurements, landmarks, and validation status.
    """
    angle_list = angles.split(",")

    if GPU_ENABLED:
        return await _scan_body_real(photos, angle_list)
    return _scan_body_mock(angle_list)


async def _scan_body_real(photos: list[UploadFile], angles: list[str]) -> dict:
    """Run real DigitalHumanPipeline (needs GPU)."""
    from PIL import Image
    from app.digital_human import DigitalHumanPipeline, PhotoAngle

    angle_map = {a: PhotoAngle(a) for a in [
        "front", "back", "left", "right",
        "three_quarter_left", "three_quarter_right"
    ]}

    photo_dict = {}
    for i, (photo, angle) in enumerate(zip(photos, angles)):
        if angle in angle_map:
            img = Image.open(io.BytesIO(await photo.read())).convert("RGB")
            photo_dict[angle_map[angle]] = img

    pipeline = DigitalHumanPipeline(device="cpu")
    profile = pipeline.process(photo_dict)
    return profile.to_dict()


def _scan_body_mock(angles: list[str]) -> dict:
    """Mock response for testing without GPU."""
    return {
        "body_id": str(uuid4()),
        "version": 1,
        "created_at": "2025-01-01T00:00:00Z",
        "body_measurements": {
            "height_cm": {"value": 175.0, "unit": "cm", "confidence": 0.92, "source_photos": ["front"], "method": "mock"},
            "shoulder_width_cm": {"value": 42.0, "unit": "cm", "confidence": 0.88, "source_photos": ["front"], "method": "mock"},
            "chest_circumference_cm": {"value": 98.0, "unit": "cm", "confidence": 0.85, "source_photos": ["front", "left"], "method": "mock"},
            "waist_circumference_cm": {"value": 84.0, "unit": "cm", "confidence": 0.85, "source_photos": ["front", "left"], "method": "mock"},
            "hip_circumference_cm": {"value": 96.0, "unit": "cm", "confidence": 0.85, "source_photos": ["front", "left"], "method": "mock"},
        },
        "landmarks": {a: {"keypoints": [], "confidence": 0.9} for a in angles},
        "validation_status": "approved",
        "validation_errors": [],
        "mode": "mock",
    }


# ============================================================
# Garment Analysis
# ============================================================

@router.post("/garment/analyze")
async def analyze_garment(
    front_image: UploadFile = File(...),
    back_image: UploadFile | None = File(None),
    retailer_id: str = Form(""),
    sku: str = Form(""),
):
    """Analyze garment from photos. Returns GarmentProfile.

    Upload front photo (required) + optional back photo.
    Returns category, color, fabric, measurements, embedding.
    """
    if GPU_ENABLED:
        return await _analyze_garment_real(front_image, back_image, retailer_id, sku)
    return _analyze_garment_mock(retailer_id, sku)


async def _analyze_garment_real(
    front: UploadFile, back: UploadFile | None,
    retailer_id: str, sku: str,
) -> dict:
    from PIL import Image
    from app.garment_intelligence import GarmentIntelligencePipeline

    front_img = Image.open(io.BytesIO(await front.read())).convert("RGB")
    back_img = None
    if back:
        back_img = Image.open(io.BytesIO(await back.read())).convert("RGB")

    pipeline = GarmentIntelligencePipeline(device="cpu")
    profile = pipeline.process(
        front_image=front_img,
        back_image=back_img,
        retailer_id=retailer_id,
        sku=sku,
    )
    return profile.to_dict()


def _analyze_garment_mock(retailer_id: str, sku: str) -> dict:
    return {
        "garment_id": str(uuid4()),
        "version": 1,
        "retailer_id": retailer_id,
        "sku": sku,
        "category": "t-shirt",
        "subcategory": "graphic_tee",
        "color": {"primary": "#FF5733", "secondary": "#000000", "name": "orange"},
        "pattern": "graphic",
        "sleeve_length": "short",
        "collar_type": "round",
        "fabric": {"type": "cotton", "confidence": 0.85},
        "measurements": {"chest_width_cm": 50.0, "length_cm": 70.0, "sleeve_length_cm": 20.0},
        "embedding": [],
        "mode": "mock",
    }


# ============================================================
# Try-On
# ============================================================

@router.post("/tryon")
async def try_on(
    person_image: UploadFile = File(...),
    garment_image: UploadFile = File(...),
    width: int = Form(256),
    height: int = Form(384),
    seed: int = Form(42),
):
    """Run virtual try-on. Returns result image as base64 PNG.

    Upload person photo + garment photo.
    Returns the try-on result image.
    """
    if GPU_ENABLED:
        return await _tryon_real(person_image, garment_image, width, height, seed)
    return await _tryon_mock(person_image, garment_image)


async def _tryon_real(
    person: UploadFile, garment: UploadFile,
    width: int, height: int, seed: int,
) -> dict:
    from PIL import Image
    from app.renderers.idm_vton.renderer import IDMVTONRenderer
    from app.renderers.base import RenderRequest
    from huggingface_hub import snapshot_download

    person_img = Image.open(io.BytesIO(await person.read())).convert("RGB")
    garment_img = Image.open(io.BytesIO(await garment.read())).convert("RGB")

    model_path = snapshot_download(repo_id="yisol/IDM-VTON")
    renderer = IDMVTONRenderer(
        model_path=model_path, device="cuda",
        width=width, height=height,
        num_inference_steps=4, guidance_scale=2.0, use_lcm=True,
    )
    renderer.warmup()

    req = RenderRequest(
        person_image=person_img,
        garment_image=garment_img,
        seed=seed,
    )
    result = renderer.render(req)

    return {
        "image": _image_to_base64(result.image),
        "render_time_ms": result.render_time_ms,
        "quality_score": result.quality_score,
        "metadata": result.metadata,
        "mode": "real",
    }


async def _tryon_mock(person: UploadFile, garment: UploadFile) -> dict:
    """Return the person image as placeholder (no GPU)."""
    from PIL import Image

    # Read person image and return it as placeholder
    person_bytes = await person.read()
    person_img = Image.open(io.BytesIO(person_bytes)).convert("RGB")

    return {
        "image": _image_to_base64(person_img),
        "render_time_ms": 0,
        "quality_score": 0.5,
        "metadata": {"renderer": "mock", "device": "cpu"},
        "mode": "mock",
    }


# ============================================================
# Health check for API
# ============================================================

@router.get("/status")
async def status():
    """Check if GPU inference is available."""
    return {
        "gpu_enabled": GPU_ENABLED,
        "mode": "real" if GPU_ENABLED else "mock",
        "endpoints": ["/body/scan", "/garment/analyze", "/tryon"],
    }
