from __future__ import annotations
import logging
import time
import numpy as np
from PIL import Image
from app.core.device import DeviceType, detect_device, get_device_info
from app.renderers.base import RenderError, RenderRequest, RenderResult, Renderer, RendererUnavailableError
from app.renderers.idm_vton.config import IDMVTONConfig
from app.renderers.idm_vton.model import IDMVTONModel, ModelNotLoadedError
from app.renderers.idm_vton.preprocessing import OpenPosePreprocessor, DensePosePreprocessor, HumanParsingPreprocessor, GarmentPreprocessor

logger = logging.getLogger(__name__)

class IDMVTONRenderer(Renderer):
    def __init__(self, model_path, device="auto", width=768, height=1024, num_inference_steps=30, guidance_scale=2.0):
        self._device_type = detect_device(device)
        self._width = width
        self._height = height
        self._config = IDMVTONConfig(model_path=model_path, image_width=width, image_height=height, num_inference_steps=num_inference_steps, guidance_scale=guidance_scale, use_fp16=(self._device_type != DeviceType.CPU))
        self._model = IDMVTONModel(self._config, self._device_type)
        self._densepose = DensePosePreprocessor()
        self._parsing = HumanParsingPreprocessor()
        self._garment_pp = GarmentPreprocessor()

    def name(self): return "idm-vton"
    def version(self): return "v1.1.0"
    def device(self): return self._device_type
    def is_ready(self): return self._model.is_loaded

    def warmup(self):
        if self._model.is_loaded: return
        logger.info("Warming up IDM-VTON renderer", extra={"model_path": self._config.model_path, **get_device_info(self._device_type)})
        try: self._model.load()
        except FileNotFoundError as e: raise RendererUnavailableError(f"IDM-VTON model files not found: {e}") from e
        except ImportError as e: raise RendererUnavailableError(f"ML dependencies not installed: {e}") from e
        except Exception as e: raise RendererUnavailableError(f"Failed to load IDM-VTON model: {e}") from e
        try:
            dummy_person = Image.new("RGB", (self._width, self._height), (128, 128, 128))
            dummy_garment = Image.new("RGB", (self._width, self._height), (200, 200, 200))
            self._render_internal(RenderRequest(person_image=dummy_person, garment_image=dummy_garment, metadata={"warmup": True}), is_warmup=True)
            logger.info("IDM-VTON renderer warmed up successfully")
        except Exception as e:
            self._model.unload()
            raise RendererUnavailableError(f"Warmup inference failed: {e}") from e

    def render(self, request):
        if not self._model.is_loaded: raise RendererUnavailableError("IDM-VTON not loaded. Call warmup() first.")
        start = time.monotonic()
        try: result_image = self._render_internal(request, is_warmup=False)
        except ModelNotLoadedError as e: raise RendererUnavailableError(str(e)) from e
        except Exception as e: raise RenderError(f"IDM-VTON inference failed: {e}") from e
        elapsed_ms = int((time.monotonic() - start) * 1000)
        result_image = result_image.resize((self._width, self._height), Image.LANCZOS)
        thumbnail = result_image.resize((self._width // 4, self._height // 4), Image.LANCZOS)
        return RenderResult(image=result_image, thumbnail=thumbnail, quality_score=self._compute_quality_score(result_image), model_version=self.version(), render_time_ms=elapsed_ms, metadata={"renderer": "idm-vton", "device": self._device_type.value, "view": request.view, "inference_steps": self._config.num_inference_steps, "guidance_scale": self._config.guidance_scale})

    def teardown(self): self._model.unload()

    def _render_internal(self, request, is_warmup=False):
        torch = self._model._torch
        pipe = self._model.pipe
        if torch is None or pipe is None: raise ModelNotLoadedError("Model not loaded")
        person = request.person_image.convert("RGB").resize((self._config.image_width, self._config.image_height), Image.LANCZOS)
        if is_warmup:
            garment = request.garment_image.convert("RGB").resize((self._config.image_width, self._config.image_height), Image.LANCZOS)
            mask = Image.new("L", (self._config.image_width, self._config.image_height), 255)
            densepose = Image.new("RGB", (self._config.image_width, self._config.image_height), (128, 128, 128))
        else:
            garment = self._garment_pp.process(request.garment_image, self._config.image_width, self._config.image_height)
            parsing = self._parsing.process(person, self._config.image_width, self._config.image_height)
            mask = self._parsing.generate_agnostic_mask(parsing)
            densepose = self._densepose.process(person, self._config.image_width, self._config.image_height)
        generator = None
        if request.seed is not None: generator = torch.Generator(device=self._device_type.value).manual_seed(request.seed)
        result = pipe(image=person, condition_image=garment, mask=mask, densepose=densepose, num_inference_steps=self._config.num_inference_steps, guidance_scale=self._config.guidance_scale, generator=generator, height=self._config.image_height, width=self._config.image_width)
        output = result.images[0] if hasattr(result, "images") else result[0]
        return output.convert("RGB")

    def _compute_quality_score(self, image):
        arr = np.array(image)
        mean, std = arr.mean(), arr.std()
        if mean < 10 or mean > 245: return 0.3
        if std < 10: return 0.4
        return round(max(0.5, min(1.0, std / 80.0)), 3)
