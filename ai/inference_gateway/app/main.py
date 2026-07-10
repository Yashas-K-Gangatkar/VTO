from __future__ import annotations
import asyncio
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Any
from fastapi import FastAPI, Response
from fastapi.responses import JSONResponse
from app.config import Settings, get_settings
from app.core.device import get_device_info
from app.jobs.processor import JobProcessor
from app.logging import configure_logging, get_logger
from app.renderers import Renderer, create_renderer, ensure_ready


class AppState:
    def __init__(self):
        self.settings: Settings | None = None
        self.renderer: Renderer | None = None
        self.job_processor: JobProcessor | None = None
        self._startup_time: datetime | None = None
        self._job_task: asyncio.Task | None = None

    @property
    def startup_time(self) -> datetime:
        return self._startup_time or datetime.now(timezone.utc)


state = AppState()


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    state.settings = settings
    configure_logging(settings)
    logger = get_logger("lifespan")
    logger.info("Starting inference gateway", extra={
        "env": settings.env, "renderer": settings.renderer, "device": settings.renderer_device,
    })

    renderer = create_renderer(settings)
    state.renderer = renderer

    if settings.renderer_warm_on_startup:
        logger.info("Warming up renderer")
        try:
            ensure_ready(renderer)
            logger.info("Renderer ready", extra={
                "renderer": renderer.name(), "version": renderer.version(),
                **get_device_info(renderer.device()),
            })
        except Exception as e:
            logger.error("Renderer warmup failed — service will start but cannot process jobs",
                         extra={"error": str(e)})

    import asyncpg
    db = await asyncpg.create_pool(settings.database_url, min_size=2, max_size=10)

    import redis.asyncio as aioredis
    redis_client = aioredis.from_url(settings.redis_url)

    from app.core.storage import StorageClient
    storage = StorageClient(settings)

    state.job_processor = JobProcessor(
        settings=settings, db=db, redis=redis_client,
        storage=storage, renderer=renderer,
    )
    state._job_task = asyncio.create_task(state.job_processor.start())
    state._startup_time = datetime.now(timezone.utc)
    logger.info("Inference gateway started")

    yield

    logger.info("Shutting down inference gateway")
    if state.job_processor:
        await state.job_processor.stop()
    if state._job_task:
        state._job_task.cancel()
        try:
            await state._job_task
        except asyncio.CancelledError:
            pass
    if renderer.is_ready():
        renderer.teardown()
    await db.close()
    await redis_client.close()
    logger.info("Inference gateway stopped")


def create_app() -> FastAPI:
    app = FastAPI(
        title="VTO Inference Gateway", version="0.1.0",
        description="GPU inference gateway for VTO try-on jobs",
        lifespan=lifespan, docs_url="/docs", redoc_url="/redoc",
    )

    @app.get("/health", tags=["Health"])
    async def health() -> dict[str, Any]:
        renderer_ready = state.renderer.is_ready() if state.renderer else False
        uptime_seconds = (
            (datetime.now(timezone.utc) - state.startup_time).total_seconds()
            if state._startup_time else 0
        )
        return {
            "status": "ok" if renderer_ready else "degraded",
            "version": "0.1.0",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "uptime_seconds": round(uptime_seconds, 1),
            "renderer": {
                "name": state.renderer.name() if state.renderer else None,
                "version": state.renderer.version() if state.renderer else None,
                "device": state.renderer.device().value if state.renderer else None,
                "ready": renderer_ready,
            },
        }

    @app.get("/health/ready", tags=["Health"])
    async def readiness() -> Response:
        if state.renderer and state.renderer.is_ready():
            return Response(status_code=200)
        return Response(status_code=503, content="Renderer not ready")

    @app.get("/metrics", tags=["Observability"])
    async def metrics() -> dict[str, Any]:
        return {
            "renderer_ready": state.renderer.is_ready() if state.renderer else False,
            "uptime_seconds": (
                (datetime.now(timezone.utc) - state.startup_time).total_seconds()
                if state._startup_time else 0
            ),
        }

    @app.exception_handler(Exception)
    async def unhandled_exception_handler(request, exc):
        logger = get_logger("error_handler")
        logger.exception("Unhandled exception", extra={"path": request.url.path})
        return JSONResponse(
            status_code=500,
            content={
                "type": "https://docs.vto.example/errors/internal",
                "title": "Internal server error", "status": 500, "detail": str(exc),
            },
        )

    return app


app = create_app()
