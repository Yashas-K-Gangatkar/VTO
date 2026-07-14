from __future__ import annotations
import logging
from app.config import Settings
from app.core.device import detect_device
from app.renderers.base import Renderer, RendererUnavailableError
from app.renderers.mock import MockRenderer

logger = logging.getLogger(__name__)


def create_renderer(settings: Settings) -> Renderer:
    renderer_name = settings.renderer
    device = detect_device(settings.renderer_device)
    logger.info("Creating renderer", extra={
        "renderer": renderer_name, "device": device.value,
        "model_path": settings.renderer_model_path,
    })
    if renderer_name == "mock":
        return MockRenderer(device=device, width=settings.output_width, height=settings.output_height)
    if renderer_name == "idm-vton":
        from app.renderers.idm_vton.renderer import IDMVTONRenderer
        return IDMVTONRenderer(
            model_path=settings.renderer_model_path,
            device=settings.renderer_device,
            width=settings.output_width, height=settings.output_height,
        )
    raise ValueError(f"Unknown renderer: {renderer_name}")


def ensure_ready(renderer: Renderer, max_retries: int = 1) -> None:
    if renderer.is_ready():
        return
    last_error: Exception | None = None
    for attempt in range(max_retries + 1):
        try:
            renderer.warmup()
            return
        except RendererUnavailableError as e:
            last_error = e
            logger.warning("Renderer warmup failed, retrying", extra={
                "attempt": attempt + 1, "error": str(e),
            })
    raise RendererUnavailableError(f"Renderer failed to warm up after {max_retries + 1} attempts: {last_error}")
