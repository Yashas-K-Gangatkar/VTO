from __future__ import annotations
import io
from datetime import timedelta
from PIL import Image
from app.config import Settings


class StorageClient:
    def __init__(self, settings: Settings):
        import boto3
        from botocore.config import Config as BotoConfig
        self._settings = settings
        self._s3 = boto3.client(
            "s3",
            endpoint_url=settings.s3_endpoint if settings.s3_endpoint else None,
            aws_access_key_id=settings.s3_access_key,
            aws_secret_access_key=settings.s3_secret_key,
            region_name=settings.s3_region,
            config=BotoConfig(
                signature_version="s3v4",
                s3={"addressing_style": "path" if settings.s3_use_path_style else "auto"},
            ),
        )

    def get_image(self, bucket: str, key: str) -> Image.Image:
        response = self._s3.get_object(Bucket=bucket, Key=key)
        data = response["Body"].read()
        return Image.open(io.BytesIO(data)).convert("RGB")

    def put_image(self, bucket: str, key: str, image: Image.Image, format: str = "WEBP", quality: int = 90) -> str:
        buf = io.BytesIO()
        save_format = "PNG" if format.upper() == "WEBP" and image.mode == "RGBA" else format
        image.save(buf, format=save_format, quality=quality)
        buf.seek(0)
        content_type = f"image/{format.lower()}"
        self._s3.put_object(Bucket=bucket, Key=key, Body=buf, ContentType=content_type)
        return key

    def presigned_get_url(self, bucket: str, key: str, expiry_minutes: int = 1440) -> str:
        return self._s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": bucket, "Key": key},
            ExpiresIn=int(timedelta(minutes=expiry_minutes).total_seconds()),
        )

    def delete_object(self, bucket: str, key: str) -> None:
        self._s3.delete_object(Bucket=bucket, Key=key)
