from __future__ import annotations
import os
import numpy as np
import pytest
from PIL import Image
from app.core.device import DeviceType
from app.renderers.base import RenderRequest, Renderer, RendererUnavailableError
from app.renderers.idm_vton.renderer import IDMVTONRenderer


class TestIDMVTONRendererInterface:
    def test_renderer_is_subclass(self):
        assert issubclass(IDMVTONRenderer, Renderer)

    def test_name(self):
        r = IDMVTONRenderer(model_path="/nonexistent", device="cpu")
        assert r.name() == "idm-vton"

    def test_is_ready_false_before_warmup(self):
        r = IDMVTONRenderer(model_path="/nonexistent", device="cpu")
        assert not r.is_ready()

    def test_render_before_warmup_raises(self):
        r = IDMVTONRenderer(model_path="/nonexistent", device="cpu")
        req = RenderRequest(person_image=Image.new("RGB", (768, 1024)), garment_image=Image.new("RGB", (768, 1024)))
        with pytest.raises(RendererUnavailableError): r.render(req)

    def test_warmup_raises_on_missing_model(self):
        r = IDMVTONRenderer(model_path="/nonexistent/path", device="cpu")
        with pytest.raises(RendererUnavailableError, match="model files not found"): r.warmup()

    def test_teardown_when_not_loaded(self):
        r = IDMVTONRenderer(model_path="/nonexistent", device="cpu")
        r.teardown()
        assert not r.is_ready()


class TestIDMVTONRendererConfig:
    def test_fp16_disabled_on_cpu(self):
        r = IDMVTONRenderer(model_path="/nonexistent", device="cpu")
        assert r._config.use_fp16 is False

    def test_custom_inference_steps(self):
        r = IDMVTONRenderer(model_path="/nonexistent", device="cpu", num_inference_steps=4)
        assert r._config.num_inference_steps == 4


class TestIDMVTONRendererQuality:
    def test_quality_score_for_black_image(self):
        r = IDMVTONRenderer(model_path="/nonexistent", device="cpu")
        assert r._compute_quality_score(Image.new("RGB", (768, 1024), (0, 0, 0))) < 0.5

    def test_quality_score_for_white_image(self):
        r = IDMVTONRenderer(model_path="/nonexistent", device="cpu")
        assert r._compute_quality_score(Image.new("RGB", (768, 1024), (255, 255, 255))) < 0.5
