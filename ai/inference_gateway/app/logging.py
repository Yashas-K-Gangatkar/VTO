from __future__ import annotations
import logging
import sys
from typing import Any
import structlog
from app.config import Settings


def configure_logging(settings: Settings) -> structlog.BoundLogger:
    level = getattr(logging, settings.log_level.upper(), logging.INFO)
    if settings.env == "dev":
        renderer = structlog.dev.ConsoleRenderer(colors=True)
    else:
        renderer = structlog.processors.JSONRenderer()

    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            renderer,
        ],
        wrapper_class=structlog.make_filtering_bound_logger(level),
        context_class=dict,
        logger_factory=structlog.PrintLoggerFactory(file=sys.stdout),
        cache_logger_on_first_use=True,
    )
    logging.basicConfig(level=level, stream=sys.stdout, format="%(message)s")
    logger = structlog.get_logger("inference_gateway")
    logger.info("logging_configured", env=settings.env, log_level=settings.log_level)
    return logger


def get_logger(name: str = "inference_gateway") -> structlog.BoundLogger:
    return structlog.get_logger(name)


def bind_context(**kwargs: Any) -> None:
    structlog.contextvars.bind_contextvars(**kwargs)


def clear_context() -> None:
    structlog.contextvars.clear_contextvars()
