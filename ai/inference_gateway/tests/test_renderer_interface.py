from __future__ import annotations
from app.renderers import MockRenderer, Renderer
from app.renderers.factory import create_renderer
from app.renderers.idm_vton.renderer import IDMVTONRenderer


class TestRendererInterface:
    def test_renderer_is_abstract(self):
        try:
            Renderer()
            assert False
        except TypeError:
            pass

    def test_mock_is_subclass(self):
        assert issubclass(MockRenderer, Renderer)

    def test_idm_vton_is_subclass(self):
        assert issubclass(IDMVTONRenderer, Renderer)


class TestFactory:
    def test_create_mock(self, settings):
        r = create_renderer(settings)
        assert r.name() == "mock"

    def test_create_idm_vton(self):
        from app.config import Settings
        s = Settings(renderer="idm-vton", renderer_device="cpu", renderer_model_path="/tmp/fake")
        r = create_renderer(s)
        assert r.name() == "idm-vton"
