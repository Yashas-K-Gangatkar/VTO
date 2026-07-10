"""Integration test for IDM-VTON end-to-end rendering.

Proves: person.jpg + garment.jpg -> result.png using real IDM-VTON.
No placeholders. No mocks. Real model. Real inference. Real image.

Prerequisites:
    1. GPU available (CUDA or MPS)
    2. Model weights downloaded: ./setup-idm-vton.sh /path/to/models
    3. ML deps installed: pip install -r requirements-idm-vton.txt
    4. Test images present: tests/fixtures/person.jpg, tests/fixtures/garment.jpg

Run:
    VTO_RUN_GPU_TESTS=1 \
    VTO_IDM_VTON_MODEL_PATH=/path/to/models/idm-vton \
    pytest tests/test_idm_vton_integration.py -v -s

Definition of Done for Sprint 3:
    This test passes -> the platform produces real virtual try-on results.
"""

from __future__ import annotations
import os
from pathlib import Path
import numpy as np
import pytest
from PIL import Image

pytestmark = pytest.mark.skipif(
    not os.environ.get("VTO_RUN_GPU_TESTS"),
    reason="Set VTO_RUN_GPU_TESTS=1 to run GPU integration tests",
)

FIXTURES_DIR = Path(__file__).parent / "fixtures"
MODEL_PATH = os.environ.get("VTO_IDM_VTON_MODEL_PATH", "/models/idm-vton")
OUTPUT_DIR = Path(os.environ.get("VTO_TEST_OUTPUT_DIR", "/tmp/vto-test-output"))


@pytest.fixture(scope="module")
def renderer():
    from app.renderers.idm_vton.renderer import IDMVTONRenderer
    r = IDMVTONRenderer(model_path=MODEL_PATH, device="auto", width=768, height=1024, num_inference_steps=30, guidance_scale=2.0)
    r.warmup()
    yield r
    r.teardown()

@pytest.fixture
def person_image():
    img_path = FIXTURES_DIR / "person.jpg"
    if not img_path.exists():
        pytest.skip(f"Test image not found: {img_path}. Add person.jpg to tests/fixtures/")
    return Image.open(img_path)

@pytest.fixture
def garment_image():
    img_path = FIXTURES_DIR / "garment.jpg"
    if not img_path.exists():
        pytest.skip(f"Test image not found: {img_path}. Add garment.jpg to tests/fixtures/")
    return Image.open(img_path)


class TestIDMVTONEndToEnd:
    def test_renderer_loads(self, renderer):
        assert renderer.is_ready()
        assert renderer.name() == "idm-vton"

    def test_produces_real_image(self, renderer, person_image, garment_image):
        from app.renderers.base import RenderRequest
        request = RenderRequest(person_image=person_image, garment_image=garment_image, view="front", seed=42)
        result = renderer.render(request)
        assert result.image is not None
        assert result.image.mode == "RGB"
        assert result.image.size == (768, 1024)
        arr = np.array(result.image)
        assert arr.mean() > 10
        assert arr.mean() < 245
        assert arr.std() > 15
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        output_path = OUTPUT_DIR / "result.png"
        result.image.save(str(output_path))
        print(f"\n    Result saved to: {output_path}")
        print(f"    Render time: {result.render_time_ms}ms")

    def test_result_is_not_gray_rectangle(self, renderer, person_image, garment_image):
        from app.renderers.base import RenderRequest
        request = RenderRequest(person_image=person_image, garment_image=garment_image, view="front", seed=42)
        result = renderer.render(request)
        arr = np.array(result.image)
        assert not (arr[:, :, 0] == arr[:, :, 1]).all()
        assert not (arr[:, :, 1] == arr[:, :, 2]).all()

    def test_seed_reproducibility(self, renderer, person_image, garment_image):
        from app.renderers.base import RenderRequest
        req1 = RenderRequest(person_image=person_image, garment_image=garment_image, seed=42)
        req2 = RenderRequest(person_image=person_image, garment_image=garment_image, seed=42)
        result1 = renderer.render(req1)
        result2 = renderer.render(req2)
        arr1 = np.array(result1.image)
        arr2 = np.array(result2.image)
        assert np.array_equal(arr1, arr2)

    def test_render_time_under_60_seconds(self, renderer, person_image, garment_image):
        from app.renderers.base import RenderRequest
        request = RenderRequest(person_image=person_image, garment_image=garment_image, view="front")
        result = renderer.render(request)
        print(f"\n    Render time: {result.render_time_ms}ms ({result.render_time_ms / 1000:.1f}s)")
        assert result.render_time_ms < 60000
