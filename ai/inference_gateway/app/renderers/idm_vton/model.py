from __future__ import annotations
import logging
import os
import sys
from typing import Any
from app.core.device import DeviceType
from app.renderers.idm_vton.config import IDMVTONConfig

logger = logging.getLogger(__name__)

class ModelNotLoadedError(Exception):
    pass

class IDMVTONModel:
    def __init__(self, config: IDMVTONConfig, device: DeviceType):
        self._config = config
        self._device = device
        self._loaded = False
        self._torch: Any = None
        self._pipe: Any = None
        self._dtype: Any = None

    @property
    def is_loaded(self) -> bool:
        return self._loaded and self._pipe is not None

    @property
    def device(self) -> DeviceType:
        return self._device

    @property
    def pipe(self) -> Any:
        if not self.is_loaded:
            raise ModelNotLoadedError("Model not loaded. Call load() first.")
        return self._pipe

    def load(self) -> None:
        if self._loaded: return
        
        missing = self._config.validate()
        if missing:
            missing_str = "\n  ".join(missing)
            raise FileNotFoundError(f"IDM-VTON model files not found. Missing:\n  {missing_str}")

        if self._device == DeviceType.MPS:
            os.environ["PYTORCH_MPS_HIGH_WATERMARK_RATIO"] = "0.0"

        logger.info("Loading IDM-VTON model", extra={"model_path": self._config.model_path, "device": self._device.value})
        try:
            self._load_pipeline()
        except ImportError as e:
            raise ImportError(f"ML dependencies not installed: {e}") from e

        self._loaded = True
        logger.info("IDM-VTON model loaded successfully")

    def _load_pipeline(self) -> None:
        import torch
        from diffusers import AutoencoderKL, DDPMScheduler
        from transformers import CLIPTextModel, CLIPTextModelWithProjection, CLIPTokenizer, CLIPVisionModelWithProjection, CLIPImageProcessor

        from app.renderers.idm_vton.src.unet_hacked_tryon import UNet2DConditionModel
        from app.renderers.idm_vton.src.unet_hacked_garmnet import UNet2DConditionModel as UNet2DConditionModel_ref
        from app.renderers.idm_vton.src.tryon_pipeline import StableDiffusionXLInpaintPipeline as TryonPipeline

        self._torch = torch
        device_str = self._device.value
        self._dtype = torch.float16

        cfg = self._config
        model_path = cfg.model_path

        logger.info("Loading VAE...")
        vae = AutoencoderKL.from_pretrained(f"{model_path}/vae", torch_dtype=self._dtype)

        logger.info("Loading text encoders...")
        text_encoder_one = CLIPTextModel.from_pretrained(f"{model_path}/text_encoder", torch_dtype=self._dtype)
        text_encoder_two = CLIPTextModelWithProjection.from_pretrained(f"{model_path}/text_encoder_2", torch_dtype=self._dtype)

        logger.info("Loading tokenizers...")
        tokenizer_one = CLIPTokenizer.from_pretrained(f"{model_path}/tokenizer", use_fast=False)
        tokenizer_two = CLIPTokenizer.from_pretrained(f"{model_path}/tokenizer_2", use_fast=False)

        logger.info("Loading scheduler...")
        noise_scheduler = DDPMScheduler.from_pretrained(f"{model_path}/scheduler")

        logger.info("Loading main UNet...")
        unet = UNet2DConditionModel.from_pretrained(f"{model_path}/unet", torch_dtype=self._dtype)

        logger.info("Loading garment encoder UNet...")
        unet_encoder = UNet2DConditionModel_ref.from_pretrained(f"{model_path}/unet_encoder", torch_dtype=self._dtype)

        logger.info("Loading image encoder...")
        image_encoder = CLIPVisionModelWithProjection.from_pretrained(f"{model_path}/image_encoder", torch_dtype=self._dtype)

        logger.info("Constructing pipeline...")
        self._pipe = TryonPipeline.from_pretrained(
            model_path,
            unet=unet,
            vae=vae,
            feature_extractor=CLIPImageProcessor(),
            text_encoder=text_encoder_one,
            text_encoder_2=text_encoder_two,
            tokenizer=tokenizer_one,
            tokenizer_2=tokenizer_two,
            scheduler=noise_scheduler,
            image_encoder=image_encoder,
            unet_encoder=unet_encoder,
            torch_dtype=self._dtype,
        ).to(device_str)

    def unload(self) -> None:
        if self._pipe is not None:
            del self._pipe
            self._pipe = None
        if self._torch is not None and self._device == DeviceType.CUDA:
            self._torch.cuda.empty_cache()
        self._loaded = False
        logger.info("IDM-VTON model unloaded")

    def get_info(self) -> dict:
        return {
            "model": "idm-vton", "model_path": self._config.model_path,
            "device": self._device.value, "dtype": str(self._dtype) if self._dtype else None,
            "loaded": self.is_loaded, "inference_steps": self._config.num_inference_steps,
            "guidance_scale": self._config.guidance_scale,
            "image_size": f"{self._config.image_width}x{self._config.image_height}",
        }
