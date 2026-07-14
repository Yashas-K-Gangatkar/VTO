from __future__ import annotations
import pytest
from PIL import Image
from app.config import Settings
from app.renderers import DeviceType, MockRenderer, RenderRequest


@pytest.fixture
def settings() -> Settings:
    return Settings(
        env="dev", log_level="debug", renderer="mock", renderer_device="cpu",
        renderer_warm_on_startup=False,
        database_url="postgresql://test:test@localhost:5432/test",
        redis_url="redis://localhost:6379/0",
        s3_endpoint="http://localhost:9000", s3_access_key="test", s3_secret_key="test",
        s3_bucket_tryon_images="test-tryon", s3_bucket_garment_images="test-garment",
        s3_bucket_body_profiles="test-body",
    )


@pytest.fixture
def mock_renderer() -> MockRenderer:
    r = MockRenderer(device=DeviceType.CPU, width=512, height=768)
    r.warmup()
    return r


@pytest.fixture
def sample_person_image() -> Image.Image:
    return Image.new("RGB", (512, 768), (100, 150, 200))


@pytest.fixture
def sample_garment_image() -> Image.Image:
    return Image.new("RGB", (512, 768), (200, 100, 50))


@pytest.fixture
def render_request(sample_person_image, sample_garment_image) -> RenderRequest:
    return RenderRequest(
        person_image=sample_person_image, garment_image=sample_garment_image,
        view="front", metadata={"garment_sku": "TEST-SKU-001"},
    )
