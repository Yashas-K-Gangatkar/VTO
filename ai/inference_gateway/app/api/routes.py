"""VTO API routes — body scan, garment analysis, try-on, and 3D Cloud Sync.

These endpoints work in two modes:
- Real mode (GPU available): runs actual ML pipelines
- Mock mode (no GPU): returns placeholder results
"""

from __future__ import annotations

import base64
import io
import json
import logging
import os
import random
import time
from typing import Any
from uuid import uuid4

from fastapi import APIRouter, File, Form, UploadFile
from fastapi.responses import JSONResponse, Response

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/v1", tags=["VTO"])

GPU_ENABLED = os.getenv("VTO_GPU_ENABLED", "false").lower() == "true"

# In-memory storage for mock mode (replace with DB/Redis in production)
# Maps phone_number -> { "otp": "1234", "model_base64": "...", "body_id": "..." }b
CLOUD_WALLET_DB = {}


def _image_to_base64(img) -> str:
    from PIL import Image
    if not isinstance(img, Image.Image):
        return ""
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode("utf-8")


# ============================================================
# Digital Twin Wallet (Cloud Sync API)
# ============================================================

@router.post("/body/sync-upload")
async def sync_upload_body(
    phone_number: str = Form(...),
    model_file: UploadFile = File(...),
):
    """Upload a 3D body model (.glb) to the cloud wallet.
    
    This is called by the SDK after the user scans their body for the first time.
    The model is linked to their phone number.
    """
    model_bytes = await model_file.read()
    model_b64 = base64.b64encode(model_bytes).decode("utf-8")
    body_id = str(uuid4())
    
    CLOUD_WALLET_DB[phone_number] = {
        "body_id": body_id,
        "model_base64": model_b64,
        "created_at": time.time()
    }
    
    logger.info(f"Stored 3D model for phone: {phone_number}")
    return {
        "status": "success",
        "message": "Digital Twin stored in cloud wallet.",
        "body_id": body_id
    }


@router.post("/body/sync-request")
async def sync_request_otp(
    phone_number: str = Form(...),
):
    """Request an OTP to retrieve the 3D body model on a new device.
    
    This implements the cross-app magic. The user enters their phone number
    in the Zodio app, gets an OTP, and can download their 3D model.
    """
    if phone_number not in CLOUD_WALLET_DB:
        return JSONResponse(
            status_code=404,
            content={"status": "error", "message": "No 3D model found for this phone number."}
        )
    
    # Generate 4-digit OTP
    otp = str(random.randint(1000, 9999))
    CLOUD_WALLET_DB[phone_number]["otp"] = otp
    CLOUD_WALLET_DB[phone_number]["otp_expires"] = time.time() + 300  # 5 min expiry
    
    # In production: Send SMS via Twilio/Gupshup
    logger.info(f"OTP for {phone_number}: {otp} (Mock mode - SMS not sent)")
    
    return {
        "status": "success",
        "message": "OTP sent to your phone number.",
        # In mock mode, we return the OTP directly so you can test
        "mock_otp": otp
    }


@router.post("/body/sync-retrieve")
async def sync_retrieve_body(
    phone_number: str = Form(...),
    otp: str = Form(...),
):
    """Download the 3D body model (.glb) after OTP verification.
    
    This allows the Zodio app to download the 3D model created in the Westside app.
    """
    user_data = CLOUD_WALLET_DB.get(phone_number)
    
    if not user_data:
        return JSONResponse(status_code=404, content={"status": "error", "message": "Not found"})
    
    if user_data.get("otp") != otp:
        return JSONResponse(status_code=403, content={"status": "error", "message": "Invalid OTP"})
    
    if time.time() > user_data.get("otp_expires", 0):
        return JSONResponse(status_code=403, content={"status": "error", "message": "OTP expired"})
    
    # Clear OTP after use
    user_data["otp"] = None
    
    return {
        "status": "success",
        "body_id": user_data["body_id"],
        "model_base64": user_data["model_base64"],
        "message": "Digital Twin retrieved successfully. Render on device."
    }


# ============================================================
# Body Scan (Measurements)
# ============================================================

@router.post("/body/scan")
async def scan_body(
    photos: list[UploadFile] = File(...),
    angles: str = Form("front,back,left,right,three_quarter_left,three_quarter_right"),
):
    """Scan body from 6 photos. Returns persistent BodyProfile."""
    angle_list = angles.split(",")
    if GPU_ENABLED:
        return await _scan_body_real(photos, angle_list)
    return _scan_body_mock(angle_list)


async def _scan_body_real(photos: list[UploadFile], angles: list[str]) -> dict:
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
    """Analyze garment from photos. Returns GarmentProfile."""
    if GPU_ENABLED:
        return await _analyze_garment_real(front_image, back_image, retailer_id, sku)
    return _analyze_garment_mock(retailer_id, sku)


async def _analyze_garment_real(front, back, retailer_id, sku) -> dict:
    from PIL import Image
    from app.garment_intelligence import GarmentIntelligencePipeline

    front_img = Image.open(io.BytesIO(await front.read())).convert("RGB")
    back_img = None
    if back:
        back_img = Image.open(io.BytesIO(await back.read())).convert("RGB")

    pipeline = GarmentIntelligencePipeline(device="cpu")
    profile = pipeline.process(front_image=front_img, back_image=back_img, retailer_id=retailer_id, sku=sku)
    return profile.to_dict()


def _analyze_garment_mock(retailer_id, sku) -> dict:
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
# Try-On (2D AI - Premium Feature)
# ============================================================

@router.post("/tryon")
async def try_on(
    person_image: UploadFile = File(...),
    garment_image: UploadFile = File(...),
    width: int = Form(256),
    height: int = Form(384),
    seed: int = Form(42),
):
    """Run 2D photorealistic virtual try-on. (Requires GPU)"""
    if GPU_ENABLED:
        return await _tryon_real(person_image, garment_image, width, height, seed)
    return await _tryon_mock(person_image, garment_image)


async def _tryon_real(person, garment, width, height, seed) -> dict:
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

    req = RenderRequest(person_image=person_img, garment_image=garment_img, seed=seed)
    result = renderer.render(req)

    return {
        "image": _image_to_base64(result.image),
        "render_time_ms": result.render_time_ms,
        "quality_score": result.quality_score,
        "metadata": result.metadata,
        "mode": "real",
    }


async def _tryon_mock(person: UploadFile, garment: UploadFile) -> dict:
    from PIL import Image
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
    return {
        "gpu_enabled": GPU_ENABLED,
        "mode": "real" if GPU_ENABLED else "mock",
        "endpoints": ["/body/scan", "/garment/analyze", "/tryon", "/body/sync-upload", "/body/sync-request", "/body/sync-retrieve"],
    }
