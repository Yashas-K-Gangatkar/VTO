from __future__ import annotations
import logging
import time
from pathlib import Path
import numpy as np
from PIL import Image
from app.core.device import DeviceType, detect_device, get_device_info
from app.renderers.base import (
    RenderError, RenderRequest, RenderResult, Renderer, RendererUnavailableError,
)

logger = logging.getLogger(__name__)


class IDMVTONRenderer(Renderer):
    def __init__(self, model_path: str, device: str = "auto", width: int = 1024, height: int = 1536):
        self._model_path = Path(model_path)
        self._device_type = detect_device(device)
        self._width = width
        self._height = height
        self._ready = False
        self._torch = None
        self._pipe = None

    def name(self) -> str:
        return "idm-vton"

    def version(self) -> str:
        return "v2.3.0"

    def device(self) -> DeviceType:
        return self._device_type

    def is_ready(self) -> bool:
        return self._ready and self._pipe is not None

    def warmup(self) -> None:
        if self._ready:
            return
        logger.info("Loading IDM-VTON model", extra={
            "model_path": str(self._model_path),
            **get_device_info(self._device_type),
        })
        try:
            self._load_model()
        except ImportError as e:
            raise RendererUnavailableError(f"ML dependencies not installed: {e}") from e
        dummy_person = Image.new("RGB", (self._width, self._height), (128, 128, 128))
        dummy_garment = Image.new("RGB", (self._width, self._height), (200, 200, 200))
        dummy_request = RenderRequest(
            person_image=dummy_person, garment_image=dummy_garment, metadata={"warmup": True},
        )
        try:
            self._render(dummy_request)
            self._ready = True
            logger.info("IDM-VTON warmed up successfully")
        except Exception as e:
            raise RendererUnavailableError(f"Warmup render failed: {e}") from e

    def render(self, request: RenderRequest) -> RenderResult:
        if not self.is_ready():
            raise RendererUnavailableError("IDM-VTON not loaded. Call warmup() first.")
        start = time.monotonic()
        try:
            image = self._render(request)
        except Exception as e:
            raise RenderError(f"IDM-VTON inference failed: {e}") from e
        elapsed_ms = int((time.monotonic() - start) * 1000)
        quality_score = self._compute_quality_score(request, image)
        thumbnail = image.resize((self._width // 4, self._height // 4), Image.LANCZOS)
        return RenderResult(
            image=image, thumbnail=thumbnail, quality_score=quality_score,
            model_version=self.version(), render_time_ms=elapsed_ms,
            metadata={"renderer": "idm-vton", "device": self._device_type.value, "view": request.view},
        )

    def teardown(self) -> None:
        if self._pipe is not None:
            del self._pipe
            self._pipe = None
        if self._torch is not None and self._device_type == DeviceType.CUDA:
            self._torch.cuda.empty_cache()
        self._ready = False

    def _load_model(self) -> None:
        import torch
        from diffusers import DiffusionPipeline
        self._torch = torch
        device_str = self._device_type.value
        dtype = torch.float16 if device_str in ("cuda", "mps") else torch.float32
        if not self._model_path.exists():
            raise RendererUnavailableError(f"Model path does not exist: {self._model_path}")
        self._pipe = DiffusionPipeline.from_pretrained(str(self._model_path), torch_dtype=dtype).to(device_str)
        try:
            if device_str == "cuda":
                self._pipe.enable_xformers_memory_efficient_attention()
        except Exception:
            logger.debug("xformers not available")
        try:
            self._pipe.enable_model_cpu_offload()
        except Exception:
            logger.debug("cpu offload not available")

    def _render(self, request: RenderRequest) -> Image.Image:
        torch = self._torch
        pipe = self._pipe
        if torch is None or pipe is None:
            raise RendererUnavailableError("Model not loaded")
        person = request.person_image.resize((self._width, self._height), Image.LANCZOS)
        garment = request.garment_image.resize((self._width, self._height), Image.LANCZOS)
        generator = None
        if request.seed is not None:
            generator = torch.Generator(device=self._device_type.value).manual_seed(request.seed)
        result = pipe(
            image=person, cloth=garment, num_inference_steps=4,
            guidance_scale=2.0, generator=generator,
        )
        output = result.images[0] if hasattr(result, "images") else result[0]
        return output.convert("RGB")

    def _compute_quality_score(self, request: RenderRequest, result: Image.Image) -> float:
        arr = np.array(result)
        mean = arr.mean()
        std = arr.std()
        if mean < 10 or mean > 245:
            return 0.3
        if std < 10:
            return 0.4
        score = min(1.0, std / 80.0)
        return round(max(0.5, score), 3)
