from __future__ import annotations
import time
import numpy as np
from PIL import Image, ImageDraw
from app.renderers.base import DeviceType, RenderRequest, RenderResult, Renderer


class MockRenderer(Renderer):
    def __init__(self, device: DeviceType = DeviceType.CPU, width: int = 1024, height: int = 1536):
        self._device = device
        self._width = width
        self._height = height
        self._ready = False

    def name(self) -> str:
        return "mock"

    def version(self) -> str:
        return "v0.1.0-mock"

    def device(self) -> DeviceType:
        return self._device

    def is_ready(self) -> bool:
        return self._ready

    def warmup(self) -> None:
        self._render_placeholder(np.zeros((self._height, self._width, 3), dtype=np.uint8))
        self._ready = True

    def render(self, request: RenderRequest) -> RenderResult:
        if not self._ready:
            from app.renderers.base import RendererUnavailableError
            raise RendererUnavailableError("MockRenderer not warmed up. Call warmup() first.")
        start = time.monotonic()
        person_array = np.array(request.person_image.resize((self._width, self._height)))
        garment_sku = request.metadata.get("garment_sku", "unknown")
        image = self._render_placeholder(person_array, garment_sku)
        thumbnail = image.resize((self._width // 4, self._height // 4), Image.LANCZOS)
        elapsed_ms = int((time.monotonic() - start) * 1000)
        return RenderResult(
            image=image, thumbnail=thumbnail, quality_score=0.75,
            model_version=self.version(), render_time_ms=elapsed_ms,
            metadata={"renderer": "mock", "note": "not for production"},
        )

    def _render_placeholder(self, person_array: np.ndarray, garment_sku: str = "unknown") -> Image.Image:
        image = Image.fromarray(person_array)
        draw = ImageDraw.Draw(image)
        label = f"MOCK TRY-ON\nGarment: {garment_sku}"
        draw.multiline_text((20, 20), label, fill=(255, 255, 0))
        return image

    def teardown(self) -> None:
        self._ready = False
