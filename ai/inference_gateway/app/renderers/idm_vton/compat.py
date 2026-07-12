"""Diffusers/accelerate compatibility patches.

Handles API differences between diffusers 0.25.0 (what IDM-VTON source
was written for) and 0.27.2 (what we install):

1. PositionNet — removed from diffusers.models.embeddings in 0.22+.
   IDM-VTON's unet_hacked_tryon.py imports it. We inject a stub.

2. clear_device_cache — added in accelerate 0.26+.
   peft 0.19+ needs it. We add a stub if missing.

This module MUST be imported before any IDM-VTON source imports.
"""

from __future__ import annotations

import logging

logger = logging.getLogger(__name__)

_applied = False


def apply_patches() -> None:
    """Apply all compatibility patches. Idempotent."""
    global _applied
    if _applied:
        return
    _applied = True

    _patch_position_net()
    _patch_clear_device_cache()


def _patch_position_net() -> None:
    """Inject PositionNet stub into diffusers.models.embeddings.

    PositionNet was removed in diffusers 0.22+. IDM-VTON's source code
    imports it but never calls it during try-on inference (it's only
    used for GLIGEN grounded generation, which we don't use).
    """
    import diffusers.models.embeddings as _emb

    if hasattr(_emb, "PositionNet"):
        return

    import torch
    import torch.nn as nn

    class PositionNet(nn.Module):
        """GLIGEN PositionNet stub — constructed but never called."""

        def __init__(self, positive_len, out_dim, feature_type="text-only", final_layer_norm=True):
            super().__init__()
            self.positive_len = positive_len
            self.out_dim = out_dim
            self.positive_norm = nn.LayerNorm(positive_len)
            self.final_layer_norm = nn.LayerNorm(out_dim) if final_layer_norm else None
            self.positive_net = nn.Sequential(
                nn.Linear(positive_len, out_dim), nn.SiLU(), nn.Linear(out_dim, out_dim)
            )
            self.object_net = (
                None
                if feature_type == "text-only"
                else nn.Sequential(
                    nn.Linear(positive_len, out_dim), nn.SiLU(), nn.Linear(out_dim, out_dim)
                )
            )

        def forward(self, boxes, masks, positive_embeddings):
            embeddings = self.positive_norm(positive_embeddings)
            if self.object_net is not None:
                embeddings = self.positive_net(embeddings) + self.object_net(embeddings)
            else:
                embeddings = self.positive_net(embeddings)
            return embeddings, masks

    _emb.PositionNet = PositionNet
    logger.info("Injected PositionNet stub into diffusers.models.embeddings")


def _patch_clear_device_cache() -> None:
    """Add clear_device_cache to accelerate.utils.memory if missing."""
    import accelerate.utils.memory as _mem

    if hasattr(_mem, "clear_device_cache"):
        return

    import gc
    import torch

    def clear_device_cache(garbage_collection: bool = True):
        if garbage_collection:
            gc.collect()
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
            torch.cuda.synchronize()

    _mem.clear_device_cache = clear_device_cache
    logger.info("Patched accelerate.utils.memory.clear_device_cache")


apply_patches()
