from __future__ import annotations
import logging
import time
import numpy as np
from PIL import Image
from app.core.device import DeviceType, detect_device, get_device_info
from app.renderers.base import RenderError, RenderRequest, RenderResult, Renderer, RendererUnavailableError
from app.renderers.idm_vton.config import IDMVTONConfig
from app.renderers.idm_vton.model import IDMVTONModel, ModelNotLoadedError
from app.renderers.idm_vton.preprocessing import HumanParsingPreprocessor, GarmentPreprocessor
from app.renderers.idm_vton.uv_mapping.texture_mapper import TextureMapper
from transformers import CLIPImageProcessor
import torch

logger = logging.getLogger(__name__)

class IDMVTONRenderer(Renderer):
    def __init__(self, model_path, device="auto", width=768, height=1024, num_inference_steps=4, guidance_scale=2.0, use_lcm=True):
        self._device_type = detect_device(device)
        self._width = width
        self._height = height
        self._config = IDMVTONConfig(model_path=model_path, image_width=width, image_height=height, num_inference_steps=num_inference_steps, guidance_scale=guidance_scale, use_fp16=(self._device_type != DeviceType.CPU))
        self._model = IDMVTONModel(self._config, self._device_type, use_lcm=use_lcm)
        self._parsing = HumanParsingPreprocessor()
        self._garment_pp = GarmentPreprocessor()
        self._clip_processor = CLIPImageProcessor()

    def name(self): return "idm-vton"
    def version(self): return "v3.0.0-lcm"
    def device(self): return self._device_type
    def is_ready(self): return self._model.is_loaded

    def warmup(self):
        if self._model.is_loaded: return
        logger.info("Warming up IDM-VTON renderer", extra={"model_path": self._config.model_path, **get_device_info(self._device_type)})
        try: self._model.load()
        except FileNotFoundError as e: raise RendererUnavailableError(f"IDM-VTON model files not found: {e}") from e
        except ImportError as e: raise RendererUnavailableError(f"ML dependencies not installed: {e}") from e
        except Exception as e: raise RendererUnavailableError(f"Failed to load IDM-VTON model: {e}") from e

    def render(self, request):
        if not self._model.is_loaded: raise RendererUnavailableError("IDM-VTON not loaded. Call warmup() first.")
        start = time.monotonic()
        try: result_image = self._render_internal(request)
        except ModelNotLoadedError as e: raise RendererUnavailableError(str(e)) from e
        except Exception as e: raise RenderError(f"IDM-VTON inference failed: {e}") from e
        elapsed_ms = int((time.monotonic() - start) * 1000)
        result_image = result_image.resize((self._width, self._height), Image.LANCZOS)
        thumbnail = result_image.resize((self._width // 4, self._height // 4), Image.LANCZOS)
        
        # Sprint 5: Generate 3D rotatable model
        try:
            mapper = TextureMapper(smplx_model_path="models/smplx/smplx.obj")
            glb_path = mapper.map_texture_to_mesh(result_image, output_path="/tmp/vto_3d_model.glb")
            metadata_3d = {"glb_path": glb_path}
        except Exception as e:
            metadata_3d = {"3d_error": str(e)}
            
        metadata = {"renderer": "idm-vton", "device": self._device_type.value, "view": request.view, "inference_steps": self._config.num_inference_steps, "guidance_scale": self._config.guidance_scale, **metadata_3d}
        return RenderResult(image=result_image, thumbnail=thumbnail, quality_score=self._compute_quality_score(result_image), model_version=self.version(), render_time_ms=elapsed_ms, metadata=metadata)


    def teardown(self): self._model.unload()

    def _render_internal(self, request):
        pipe = self._model.pipe
        torch = self._model._torch
        device = self._device_type.value
        dtype = self._model._dtype

        person_img = request.person_image.convert("RGB").resize((self._config.image_width, self._config.image_height), Image.LANCZOS)
        garment_img = request.garment_image.convert("RGB").resize((self._config.image_width, self._config.image_height), Image.LANCZOS)

        person_tensor = (np.array(person_img).astype(np.float32) / 127.5) - 1.0
        person_tensor = torch.from_numpy(person_tensor).permute(2, 0, 1).unsqueeze(0).to(dtype)

        garment_tensor = (np.array(garment_img).astype(np.float32) / 127.5) - 1.0
        garment_tensor = torch.from_numpy(garment_tensor).permute(2, 0, 1).unsqueeze(0).to(dtype)

        mask = self._parsing.generate_agnostic_mask(self._parsing.process(person_img, self._config.image_width, self._config.image_height))
        mask_tensor = torch.from_numpy(np.array(mask).astype(np.float32) / 255.0).unsqueeze(0).unsqueeze(0).to(dtype)
        mask_tensor = 1 - mask_tensor

        pose_img = Image.new("RGB", (self._config.image_width, self._config.image_height), (128, 128, 128))
        pose_tensor = (np.array(pose_img).astype(np.float32) / 127.5) - 1.0
        pose_tensor = torch.from_numpy(pose_tensor).permute(2, 0, 1).unsqueeze(0).to(dtype)

        clip_image = self._clip_processor(images=garment_img, return_tensors="pt").pixel_values.to(dtype)

        prompt = "model is wearing a garment"
        negative_prompt = "monochrome, lowres, bad anatomy, worst quality, low quality"
        prompt_cloth = "a photo of garment"

        with torch.inference_mode():
            prompt_embeds, negative_prompt_embeds, pooled_prompt_embeds, negative_pooled_prompt_embeds = pipe.encode_prompt(
                [prompt], num_images_per_prompt=1, do_classifier_free_guidance=True, negative_prompt=[negative_prompt]
            )
            prompt_embeds_c, _, _, _ = pipe.encode_prompt(
                [prompt_cloth], num_images_per_prompt=1, do_classifier_free_guidance=False, negative_prompt=[negative_prompt]
            )

            generator = torch.Generator(device).manual_seed(request.seed) if request.seed else None

            images = pipe(
                prompt_embeds=prompt_embeds,
                negative_prompt_embeds=negative_prompt_embeds,
                pooled_prompt_embeds=pooled_prompt_embeds,
                negative_pooled_prompt_embeds=negative_pooled_prompt_embeds,
                num_inference_steps=self._config.num_inference_steps,
                generator=generator,
                strength=1.0,
                pose_img=pose_tensor.to(device),
                text_embeds_cloth=prompt_embeds_c,
                cloth=garment_tensor.to(device),
                mask_image=mask_tensor.to(device),
                image=((person_tensor + 1.0) / 2.0).to(device),
                height=self._config.image_height,
                width=self._config.image_width,
                guidance_scale=self._config.guidance_scale,
                ip_adapter_image=clip_image.to(device),
            )[0]

        return images[0]

    def _compute_quality_score(self, image):
        arr = np.array(image)
        mean, std = arr.mean(), arr.std()
        if mean < 10 or mean > 245: return 0.3
        if std < 10: return 0.4
        return round(max(0.5, min(1.0, std / 80.0)), 3)
