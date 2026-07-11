from __future__ import annotations
from dataclasses import dataclass
from pathlib import Path

@dataclass
class IDMVTONConfig:
    model_path: str = "/models/idm-vton"
    num_inference_steps: int = 30
    guidance_scale: float = 2.0
    image_width: int = 768
    image_height: int = 1024
    use_fp16: bool = True
    enable_xformers: bool = True
    enable_cpu_offload: bool = False
    enable_attention_slicing: bool = False
    output_format: str = "webp"
    output_quality: int = 90

    @property
    def unet_encoder_path(self) -> Path: return Path(self.model_path) / "unet_encoder"
    @property
    def unet_main_path(self) -> Path: return Path(self.model_path) / "unet"
    @property
    def vae_path(self) -> Path: return Path(self.model_path) / "vae"
    @property
    def text_encoder_path(self) -> Path: return Path(self.model_path) / "text_encoder"
    @property
    def tokenizer_path(self) -> Path: return Path(self.model_path) / "tokenizer"
    @property
    def scheduler_path(self) -> Path: return Path(self.model_path) / "scheduler"

    def validate(self) -> list[str]:
        missing = []
        for name, path in [
            ("model_path", Path(self.model_path)),
            ("unet_encoder", self.unet_encoder_path),
            ("unet_main", self.unet_main_path),
            ("vae", self.vae_path),
            ("text_encoder", self.text_encoder_path),
            ("tokenizer", self.tokenizer_path),
        ]:
            if not path.exists(): missing.append(f"{name}: {path}")
        return missing
