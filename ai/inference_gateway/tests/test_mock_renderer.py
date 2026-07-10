from __future__ import annotations
from app.renderers import DeviceType, MockRenderer, RenderRequest


class TestMockRenderer:
    def test_name(self, mock_renderer):
        assert mock_renderer.name() == "mock"

    def test_is_ready_after_warmup(self):
        r = MockRenderer(device=DeviceType.CPU, width=256, height=256)
        assert not r.is_ready()
        r.warmup()
        assert r.is_ready()

    def test_render_returns_valid_result(self, mock_renderer, render_request):
        result = mock_renderer.render(render_request)
        assert result.image.mode == "RGB"
        assert result.image.size == (1024, 1536)
        assert 0.0 <= result.quality_score <= 1.0

    def test_teardown(self, mock_renderer):
        mock_renderer.teardown()
        assert not mock_renderer.is_ready()
