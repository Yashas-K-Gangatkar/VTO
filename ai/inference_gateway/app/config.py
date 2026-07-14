from __future__ import annotations
from functools import lru_cache
from typing import Literal
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="VTO_", env_file=".env", env_file_encoding="utf-8",
        case_sensitive=False, extra="ignore",
    )

    env: Literal["dev", "staging", "production"] = "dev"
    log_level: Literal["debug", "info", "warning", "error"] = "info"
    host: str = "0.0.0.0"
    port: int = 8090

    database_url: str = Field(default="postgresql://vto:dev_password_change_me@postgres:5432/vto")
    redis_url: str = Field(default="redis://redis:6379/0")

    s3_endpoint: str = Field(default="http://minio:9000")
    s3_access_key: str = "vto_dev"
    s3_secret_key: str = "dev_password_change_me"
    s3_region: str = "us-east-1"
    s3_bucket_tryon_images: str = "vto-prod-tryon-images"
    s3_bucket_garment_images: str = "vto-prod-garment-images"
    s3_bucket_body_profiles: str = "vto-prod-body-profiles"
    s3_use_path_style: bool = True

    renderer: Literal["idm-vton", "mock"] = Field(default="mock")
    renderer_model_path: str = Field(default="/models/idm-vton")
    renderer_device: Literal["auto", "cuda", "mps", "cpu"] = "auto"
    renderer_warm_on_startup: bool = True

    job_poll_interval_seconds: float = 1.0
    job_max_concurrent: int = 1
    job_timeout_seconds: int = 30

    output_format: Literal["webp", "png", "jpeg"] = "webp"
    output_quality: int = 90
    output_width: int = 1024
    output_height: int = 1536
    image_url_expiry_minutes: int = 1440

    cost_circuit_breaker_enabled: bool = True
    max_jobs_per_minute: int = 60


@lru_cache
def get_settings() -> Settings:
    return Settings()
