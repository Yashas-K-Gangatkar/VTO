from __future__ import annotations
import abc
from dataclasses import dataclass, field
from enum import Enum
from typing import Any
import numpy as np
from PIL import Image


class RenderError(Exception):
    pass


class RendererUnavailableError(RenderError):
    pass


class RenderTimeoutError(RenderError):
    pass


class DeviceType(str, Enum):
    CUDA = "cuda"
    MPS = "mps"
    CPU = "cpu"


@dataclass
class RenderRequest:
    person_image: Image.Image
    person_keypoints: np.ndarray | None = None
    person_densepose: Image.Image | None = None
    person_mask: Image.Image | None = None
    garment_image: Image.Image
    garment_mask: Image.Image | None = None
    garment_attributes: dict[str, Any] = field(default_factory=dict)
    face_embedding: np.ndarray | None = None
    face_mask: Image.Image | None = None
    size: str | None = None
    view: str = "front"
    seed: int | None = None
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass
class RenderResult:
    image: Image.Image
    thumbnail: Image.Image
    quality_score: float
    model_version: str
    render_time_ms: int
    metadata: dict[str, Any] = field(default_factory=dict)


class Renderer(abc.ABC):
    @abc.abstractmethod
    def name(self) -> str: ...

    @abc.abstractmethod
    def version(self) -> str: ...

    @abc.abstractmethod
    def device(self) -> DeviceType: ...

    @abc.abstractmethod
    def is_ready(self) -> bool: ...

    @abc.abstractmethod
    def warmup(self) -> None: ...

    @abc.abstractmethod
    def render(self, request: RenderRequest) -> RenderResult: ...

    def teardown(self) -> None:
        pass
