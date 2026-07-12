"""IDM-VTON Renderer.

Implements the Renderer interface using IDM-VTON (per DR-044).
This is the v1 production renderer. Phase 2 will add FluxRenderer.

The renderer is responsible for:
1. Loading the model (delegated to IDMVTONModel)
2. Preprocessing inputs (person + garment → mask, pose, etc.)
3. Running inference through the TryonPipeline
4. Post-processing the result (resize, quality check, 3D texture mapping)

The gateway only calls renderer.render(request) — it never knows
which model is running.
"""

from __future__ import annotations

import logging
import time
from typing import Any

import numpy as np
from PIL import Image

from app.core.device import DeviceType, detect_device, get_device_info
from app.renderers.base import (
    RenderError,
    RenderRequest,
    RenderResult,
    Renderer,
    RendererUnavailableError,
)
from app.renderers.idm_vton.config import IDMVTONConfig
from app.renderers.idm_vton.model import IDMVTONModel, ModelNotLoadedError
from app.renderers.idm_vton.preprocessing import HumanParsingPreprocessor, PoseEstimator
from app.renderers.idm_vton.uv_mapping.texture_mapper import TextureMapper
from transformers import CLIPImageProcessor
import torch

logger = logging.getLogger(__name__)


class IDMVTONRenderer(Renderer):
    """Renders try-on images using IDM-VTON with LCM-LoRA + 3D texture mapping.

    Lifecycle:
        renderer = IDMVTONRenderer(model_path)
        renderer.warmup()     # loads model (~2 min)
        result = renderer.render(request)  # inference (~3-30s depending on GPU)
        renderer.teardown()   # releases model
    """

    def __init__(
        self,
        model_path: str,
        device: str = "auto",
        width: int = 768,
        height: int = 1024,
        num_inference_steps: int = 4,
        guidance_scale: float = 2.0,
        use_lcm: bool = True,
    ):
        self._device_type = detect_device(device)
        self._width = width
        self._height = height

        self._config = IDMVTONConfig(
            model_path=model_path,
            image_width=width,
            image_height=height,
            num_inference_steps=num_inference_steps,
            guidance_scale=guidance_scale,
            use_fp16=(self._device_type != DeviceType.CPU),
        )

        self._model = IDMVTONModel(self._config, self._device_type, use_lcm=use_lcm)

        # Preprocessing models on CPU to avoid GPU OOM
        # (IDM-VTON uses ~12GB VRAM, preprocessing needs ~700MB more)
        self._parsing = HumanParsingPreprocessor(device="cpu")
        self._pose = PoseEstimator(device="cpu")
        self._clip_processor = CLIPImageProcessor()

    # ============================================================
    # Renderer interface implementation
    # ============================================================

    def name(self) -> str:
        return "idm-vton"

    def version(self) -> str:
        return "v3.0.0-lcm"

    def device(self) -> DeviceType:
        return self._device_type

    def is_ready(self) -> bool:
        return self._model.is_loaded

    def warmup(self) -> None:
        """Load the model and run one dummy inference.

        Raises:
            RendererUnavailableError: if loading or warmup fails
        """
        if self._model.is_loaded:
            return

        logger.info(
            "Warming up IDM-VTON renderer",
            extra={
                "model_path": self._config.model_path,
                **get_device_info(self._device_type),
            },
        )

        try:
            self._model.load()
        except FileNotFoundError as e:
            raise RendererUnavailableError(
                f"IDM-VTON model files not found: {e}. "
                "Run: ./setup-idm-vton.sh to download weights."
            ) from e
        except ImportError as e:
            raise RendererUnavailableError(
                f"ML dependencies not installed: {e}. "
                "Run: pip install -r requirements-idm-vton.txt"
            ) from e
        except Exception as e:
            raise RendererUnavailableError(f"Failed to load IDM-VTON model: {e}") from e

        # Warmup: run one dummy inference to allocate GPU memory
        try:
            dummy_person = Image.new("RGB", (self._width, self._height), (128, 128, 128))
            dummy_garment = Image.new("RGB", (self._width, self._height), (200, 200, 200))
            dummy_request = RenderRequest(
                person_image=dummy_person,
                garment_image=dummy_garment,
                metadata={"warmup": True},
            )
            self._render_internal(dummy_request, is_warmup=True)
            logger.info("IDM-VTON renderer warmed up successfully")
        except Exception as e:
            self._model.unload()
            raise RendererUnavailableError(f"Warmup inference failed: {e}") from e

    def render(self, request: RenderRequest) -> RenderResult:
        """Render a try-on image.

        Args:
            request: Contains person_image, garment_image, and optional metadata.

        Returns:
            RenderResult with the try-on image + 3D model metadata.

        Raises:
            RendererUnavailableError: if model not loaded
            RenderError: if inference fails
        """
        if not self._model.is_loaded:
            raise RendererUnavailableError("IDM-VTON not loaded. Call warmup() first.")

        start = time.monotonic()

        try:
            result_image = self._render_internal(request, is_warmup=False)
        except ModelNotLoadedError as e:
            raise RendererUnavailableError(str(e)) from e
        except Exception as e:
            raise RenderError(f"IDM-VTON inference failed: {e}") from e

        elapsed_ms = int((time.monotonic() - start) * 1000)

        # Post-process: resize to standard output dimensions
        result_image = result_image.resize((self._width, self._height), Image.LANCZOS)
        thumbnail = result_image.resize(
            (self._width // 4, self._height // 4), Image.LANCZOS
        )

        # Sprint 5: Generate 3D rotatable model (non-blocking — errors don't fail the render)
        metadata_3d = {}
        try:
            mapper = TextureMapper(smplx_model_path="models/smplx/smplx.obj")
            glb_path = mapper.map_texture_to_mesh(
                result_image, output_path="/tmp/vto_3d_model.glb"
            )
            metadata_3d = {"glb_path": glb_path}
        except Exception as e:
            metadata_3d = {"3d_error": str(e)}

        quality_score = self._compute_quality_score(result_image)

        return RenderResult(
            image=result_image,
            thumbnail=thumbnail,
            quality_score=quality_score,
            model_version=self.version(),
            render_time_ms=elapsed_ms,
            metadata={
                "renderer": "idm-vton",
                "device": self._device_type.value,
                "view": request.view,
                "inference_steps": self._config.num_inference_steps,
                "guidance_scale": self._config.guidance_scale,
                **metadata_3d,
            },
        )

    def teardown(self) -> None:
        """Release model resources."""
        self._model.unload()
        logger.info("IDM-VTON renderer torn down")

    # ============================================================
    # Internal methods
    # ============================================================

    def _render_internal(self, request: RenderRequest, is_warmup: bool = False) -> Image.Image:
        """Run the actual IDM-VTON inference.

        Uses the src/tryon_pipeline.py API (original IDM-VTON):
          pipe(prompt_embeds=..., cloth=..., pose_img=..., mask_image=...,
               image=..., ip_adapter_image=...)
        """
        torch = self._model._torch
        pipe = self._model.pipe

        if torch is None or pipe is None:
            raise ModelNotLoadedError("Model not loaded")

        device = self._device_type.value
        dtype = self._model._dtype
        W = self._config.image_width
        H = self._config.image_height

        # 1. Resize inputs
        person = request.person_image.convert("RGB").resize((W, H), Image.LANCZOS)
        garment = request.garment_image.convert("RGB").resize((W, H), Image.LANCZOS)

        # 2. Generate agnostic mask (white where garment goes, black elsewhere)
        if is_warmup:
            mask = Image.new("L", (W, H), 255)
        else:
            mask = self._generate_agnostic_mask(person)

        # 3. Generate pose map (OpenPose skeleton)
        if is_warmup:
            pose = Image.new("RGB", (W, H), (128, 128, 128))
        else:
            pose = self._generate_pose(person)
            # OpenPose returns 512x768 — resize to match person image
            pose = pose.resize((W, H), Image.LANCZOS)

        # 4. Convert PIL -> tensors (all in model dtype, [-1, 1] range)
        person_tensor = torch.from_numpy(
            (np.array(person).astype(np.float32) / 127.5) - 1.0
        ).permute(2, 0, 1).unsqueeze(0).to(dtype)

        garment_tensor = torch.from_numpy(
            (np.array(garment).astype(np.float32) / 127.5) - 1.0
        ).permute(2, 0, 1).unsqueeze(0).to(dtype)

        mask_tensor = torch.from_numpy(
            np.array(mask).astype(np.float32) / 255.0
        ).unsqueeze(0).unsqueeze(0).to(dtype)

        pose_tensor = torch.from_numpy(
            (np.array(pose).astype(np.float32) / 127.5) - 1.0
        ).permute(2, 0, 1).unsqueeze(0).to(dtype)

        # CLIP garment embedding (for IP-Adapter)
        clip_image = self._clip_processor(
            images=garment, return_tensors="pt"
        ).pixel_values.to(dtype)

        # 5. Encode prompts
        prompt = "model is wearing a garment"
        negative_prompt = "monochrome, lowres, bad anatomy, worst quality, low quality"
        prompt_cloth = "a photo of garment"

        with torch.inference_mode():
            prompt_embeds, neg_prompt_embeds, pooled_embeds, neg_pooled_embeds = pipe.encode_prompt(
                [prompt],
                num_images_per_prompt=1,
                do_classifier_free_guidance=True,
                negative_prompt=[negative_prompt],
            )
            prompt_embeds_c, _, _, _ = pipe.encode_prompt(
                [prompt_cloth],
                num_images_per_prompt=1,
                do_classifier_free_guidance=False,
                negative_prompt=[negative_prompt],
            )

        # 6. Set up generator
        generator = None
        if request.seed is not None:
            generator = torch.Generator(device=device).manual_seed(request.seed)

        # 7. Run inference
        with torch.inference_mode():
            images = pipe(
                prompt_embeds=prompt_embeds,
                negative_prompt_embeds=neg_prompt_embeds,
                pooled_prompt_embeds=pooled_embeds,
                negative_pooled_prompt_embeds=neg_pooled_embeds,
                num_inference_steps=self._config.num_inference_steps,
                generator=generator,
                strength=1.0,
                pose_img=pose_tensor.to(device),
                text_embeds_cloth=prompt_embeds_c,
                cloth=garment_tensor.to(device),
                mask_image=mask_tensor.to(device),
                image=person_tensor.to(device),
                height=H,
                width=W,
                guidance_scale=self._config.guidance_scale,
                ip_adapter_image=clip_image.to(device),
            )

        # 8. Extract PIL image from pipeline output
        # Pipeline returns ([PIL.Image, ...],) tuple
        if isinstance(images, tuple) and len(images) > 0:
            images = images[0]
        if isinstance(images, list) and len(images) > 0:
            output = images[0]
        else:
            output = images[0] if hasattr(images, "__getitem__") else images

        if hasattr(output, "convert"):
            return output.convert("RGB")
        elif hasattr(output, "permute"):
            result_array = (output.permute(1, 2, 0).cpu().numpy() * 255).clip(0, 255).astype(np.uint8)
            return Image.fromarray(result_array)
        else:
            return Image.fromarray(output)

    def _generate_agnostic_mask(self, person: Image.Image) -> Image.Image:
        """Generate clothing-agnostic mask using Segformer-B2.

        White (255) where the garment goes (upper-clothes, skirt, pants).
        Black (0) everywhere else (face, arms, legs, background).
        """
        return self._parsing.generate_agnostic_mask(person)

    def _generate_pose(self, person: Image.Image) -> Image.Image:
        """Generate OpenPose skeleton for the person.

        The pose skeleton tells the diffusion model where shoulders, elbows,
        hips, and ankles are — so the garment aligns to the body correctly.
        """
        return self._pose.estimate(person)

    def _compute_quality_score(self, image: Image.Image) -> float:
        """Compute a quality score for the rendered image.

        v1: Simple heuristic based on image statistics.
        Sprint 5: CLIP similarity between garment region and result.

        Returns:
            Float between 0.0 and 1.0.
        """
        arr = np.array(image)
        mean = arr.mean()
        std = arr.std()

        if mean < 10 or mean > 245:
            return 0.3
        if std < 10:
            return 0.4

        score = min(1.0, std / 80.0)
        return round(max(0.5, score), 3)
