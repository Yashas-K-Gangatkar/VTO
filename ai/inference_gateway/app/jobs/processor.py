from __future__ import annotations
import asyncio
import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Any
import asyncpg
import redis.asyncio as aioredis
from app.config import Settings
from app.core.storage import StorageClient
from app.logging import bind_context, clear_context, get_logger
from app.renderers import RenderError, RenderRequest, Renderer, RendererUnavailableError
from PIL import Image
import io

logger = get_logger("job_processor")


class JobProcessor:
    def __init__(self, settings: Settings, db: asyncpg.Pool, redis: aioredis.Redis,
                 storage: StorageClient, renderer: Renderer):
        self._settings = settings
        self._db = db
        self._redis = redis
        self._storage = storage
        self._renderer = renderer
        self._running = False
        self._semaphore = asyncio.Semaphore(settings.job_max_concurrent)

    async def start(self) -> None:
        self._running = True
        logger.info("Job processor starting", extra={
            "max_concurrent": self._settings.job_max_concurrent,
            "poll_interval": self._settings.job_poll_interval_seconds,
        })
        while self._running:
            try:
                job = await self._claim_next_job()
                if job is None:
                    await asyncio.sleep(self._settings.job_poll_interval_seconds)
                    continue
                asyncio.create_task(self._process_with_semaphore(job))
            except asyncio.CancelledError:
                logger.info("Job processor cancelled")
                break
            except Exception as e:
                logger.error("Job processor error", extra={"error": str(e)})
                await asyncio.sleep(self._settings.job_poll_interval_seconds)

    async def stop(self) -> None:
        self._running = False
        logger.info("Job processor stopping (waiting for in-flight jobs)")

    async def _claim_next_job(self) -> dict[str, Any] | None:
        async with self._db.acquire() as conn:
            row = await conn.fetchrow("""
                UPDATE tryon.tryons
                SET status = 'processing'
                WHERE id = (
                    SELECT id FROM tryon.tryons
                    WHERE status = 'pending'
                    ORDER BY created_at
                    FOR UPDATE SKIP LOCKED
                    LIMIT 1
                )
                RETURNING id, retailer_id, shopper_ref, body_profile_id,
                          garment_sku, size, view, cache_key
            """)
            return dict(row) if row else None

    async def _process_with_semaphore(self, job: dict[str, Any]) -> None:
        async with self._semaphore:
            try:
                await asyncio.wait_for(
                    self._process_job(job),
                    timeout=self._settings.job_timeout_seconds,
                )
            except TimeoutError:
                await self._mark_failed(job["id"], job["retailer_id"], "timeout",
                    f"Job exceeded {self._settings.job_timeout_seconds}s timeout")
            except Exception as e:
                logger.exception("Job failed", extra={"job_id": str(job["id"])})
                await self._mark_failed(job["id"], job["retailer_id"], "internal_error", str(e))

    async def _process_job(self, job: dict[str, Any]) -> None:
        job_id = job["id"]
        retailer_id = job["retailer_id"]
        bind_context(job_id=str(job_id), retailer_id=str(retailer_id))
        logger.info("Processing job", extra={"garment_sku": job["garment_sku"], "view": job["view"]})
        try:
            person_image, garment_image = await self._load_inputs(job)
            render_request = RenderRequest(
                person_image=person_image, garment_image=garment_image,
                size=job.get("size"), view=job.get("view", "front"),
                seed=self._deterministic_seed(job),
                metadata={"job_id": str(job_id), "garment_sku": job["garment_sku"],
                          "retailer_id": str(retailer_id)},
            )
            result = await asyncio.to_thread(self._renderer.render, render_request)
            image_key = f"{retailer_id}/{datetime.now(timezone.utc).strftime('%Y%m')}/{job_id}.webp"
            self._storage.put_image(
                bucket=self._settings.s3_bucket_tryon_images, key=image_key,
                image=result.image, format=self._settings.output_format.upper(),
                quality=self._settings.output_quality,
            )
            thumbnail_key = f"{retailer_id}/{datetime.now(timezone.utc).strftime('%Y%m')}/{job_id}_thumb.webp"
            self._storage.put_image(
                bucket=self._settings.s3_bucket_tryon_images, key=thumbnail_key,
                image=result.thumbnail, format=self._settings.output_format.upper(),
                quality=self._settings.output_quality,
            )
            image_url = self._storage.presigned_get_url(
                bucket=self._settings.s3_bucket_tryon_images, key=image_key,
                expiry_minutes=self._settings.image_url_expiry_minutes,
            )
            thumbnail_url = self._storage.presigned_get_url(
                bucket=self._settings.s3_bucket_tryon_images, key=thumbnail_key,
                expiry_minutes=self._settings.image_url_expiry_minutes,
            )
            await self._mark_succeeded(
                job_id=job_id, retailer_id=retailer_id, image_url=image_url,
                thumbnail_url=thumbnail_url, model_version=result.model_version,
                quality_score=result.quality_score, render_time_ms=result.render_time_ms,
            )
            await self._publish_event(job, "tryon.succeeded", {
                "tryon_id": str(job_id), "image_url": image_url,
            })
            logger.info("Job succeeded", extra={
                "render_time_ms": result.render_time_ms, "quality_score": result.quality_score,
            })
        except RendererUnavailableError as e:
            await self._mark_failed(job_id, retailer_id, "renderer_unavailable", str(e))
            await self._publish_event(job, "tryon.failed", {
                "tryon_id": str(job_id), "error_code": "renderer_unavailable",
            })
        except RenderError as e:
            await self._mark_failed(job_id, retailer_id, "render_failed", str(e))
            await self._publish_event(job, "tryon.failed", {
                "tryon_id": str(job_id), "error_code": "render_failed",
            })
        finally:
            clear_context()

    async def _load_inputs(self, job: dict[str, Any]) -> tuple[Any, Any]:
        body_profile_id = job["body_profile_id"]
        garment_sku = job["garment_sku"]

        # Load person image (or generate placeholder if missing)
        person_key = f"{job['retailer_id']}/{body_profile_id}.png"
        try:
            person_image = await asyncio.to_thread(
                self._storage.get_image, self._settings.s3_bucket_body_profiles, person_key,
            )
        except Exception as e:
            logger.warning("Person image not found, using placeholder", extra={
                "key": person_key, "error": str(e)
            })
            person_image = self._generate_placeholder_image(128, 128, 128, f"Person\n{body_profile_id}")

        # Load garment image (or generate placeholder if missing)
        garment_key = f"{job['retailer_id']}/{garment_sku}/front.webp"
        try:
            garment_image = await asyncio.to_thread(
                self._storage.get_image, self._settings.s3_bucket_garment_images, garment_key,
            )
        except Exception as e:
            logger.warning("Garment image not found, using placeholder", extra={
                "key": garment_key, "error": str(e)
            })
            garment_image = self._generate_placeholder_image(200, 100, 50, f"Garment\n{garment_sku}")

        return person_image, garment_image

    def _generate_placeholder_image(self, r: int, g: int, b: int, label: str) -> Image.Image:
        """Generate a placeholder image for missing inputs."""
        img = Image.new("RGB", (1024, 1536), (r, g, b))
        return img

    def _deterministic_seed(self, job: dict[str, Any]) -> int:
        raw = f"{job['retailer_id']}:{job['garment_sku']}:{job.get('size', '')}:{job.get('view', 'front')}"
        return abs(hash(raw)) % (2**32)

    async def _mark_succeeded(self, job_id, retailer_id, image_url, thumbnail_url,
                              model_version, quality_score, render_time_ms) -> None:
        async with self._db.acquire() as conn:
            await conn.execute("""
                UPDATE tryon.tryons
                SET status = 'succeeded', image_url = $1, thumbnail_url = $2,
                    quality_score = $3, model_version = $4, render_time_ms = $5,
                    completed_at = NOW()
                WHERE id = $6 AND retailer_id = $7
            """, image_url, thumbnail_url, quality_score, model_version,
                render_time_ms, job_id, retailer_id)

    async def _mark_failed(self, job_id, retailer_id, error_code, error_detail) -> None:
        async with self._db.acquire() as conn:
            await conn.execute("""
                UPDATE tryon.tryons
                SET status = 'failed', error_code = $1, error_detail = $2, completed_at = NOW()
                WHERE id = $3 AND retailer_id = $4
            """, error_code, error_detail, job_id, retailer_id)

    async def _publish_event(self, job: dict[str, Any], event_type: str, data: dict) -> None:
        try:
            event = json.dumps({
                "event_id": str(uuid.uuid4()),
                "event_type": event_type,
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "retailer_id": str(job["retailer_id"]),
                "data": data,
            })
            await self._redis.lpush("events:webhooks", event)
        except Exception as e:
            logger.warning("Failed to publish event", extra={"error": str(e)})
