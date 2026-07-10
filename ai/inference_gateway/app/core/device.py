from __future__ import annotations
import logging
from enum import Enum

logger = logging.getLogger(__name__)


class DeviceType(str, Enum):
    CUDA = "cuda"
    MPS = "mps"
    CPU = "cpu"


def detect_device(preferred: str = "auto") -> DeviceType:
    if preferred == "auto":
        return _auto_detect()
    return DeviceType(preferred)


def _auto_detect() -> DeviceType:
    try:
        import torch
        if torch.cuda.is_available():
            gpu_name = torch.cuda.get_device_name(0)
            vram_gb = torch.cuda.get_device_properties(0).total_memory / (1024**3)
            logger.info("CUDA device detected", extra={"gpu": gpu_name, "vram_gb": round(vram_gb, 1)})
            return DeviceType.CUDA
    except ImportError:
        logger.debug("torch not installed; cannot check CUDA")
    except Exception as e:
        logger.debug("CUDA check failed", extra={"error": str(e)})

    try:
        import torch
        if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            logger.info("MPS device detected (Apple Silicon)")
            return DeviceType.MPS
    except ImportError:
        pass
    except Exception as e:
        logger.debug("MPS check failed", extra={"error": str(e)})

    logger.warning("No GPU detected; falling back to CPU. Inference will be slow.")
    return DeviceType.CPU


def get_device_info(device: DeviceType) -> dict:
    info: dict = {"device": device.value}
    try:
        import torch
        if device == DeviceType.CUDA:
            info["gpu_name"] = torch.cuda.get_device_name(0)
            info["vram_gb"] = round(torch.cuda.get_device_properties(0).total_memory / (1024**3), 1)
            info["cuda_version"] = torch.version.cuda
        elif device == DeviceType.MPS:
            info["gpu_name"] = "Apple Silicon (MPS)"
        info["torch_version"] = torch.__version__
    except ImportError:
        info["note"] = "torch not installed"
    return info
