"""IDM-VTON TryonPipeline (SDXL Architecture)."""
from __future__ import annotations
import logging
from typing import Any, List
import numpy as np
import torch
import torch.nn.functional as F
from diffusers import DiffusionPipeline
from PIL import Image
from app.renderers.idm_vton.pipeline.attention_processor import setup_garment_attention

logger = logging.getLogger(__name__)

class TryonPipeline(DiffusionPipeline):
    model_cpu_offload_seq = "text_encoder->text_encoder_2->unet_encoder->unet->vae"
    
    def __init__(self, vae, text_encoder, text_encoder_2, tokenizer, tokenizer_2, unet_encoder, unet, scheduler, image_encoder=None, feature_extractor=None):
        super().__init__()
        self.register_modules(vae=vae, text_encoder=text_encoder, text_encoder_2=text_encoder_2, tokenizer=tokenizer, tokenizer_2=tokenizer_2, unet_encoder=unet_encoder, unet=unet, scheduler=scheduler, image_encoder=image_encoder, feature_extractor=feature_extractor)
        setup_garment_attention(self.unet)

    @torch.no_grad()
    def __call__(self, image, condition_image, mask, densepose, num_inference_steps=30, guidance_scale=2.0, generator=None, height=1024, width=768, **kwargs):
        device = self._execution_device
        dtype = self.unet.dtype
        person = self._pil_to_tensor(image, height, width).to(device, dtype)
        garment = self._pil_to_tensor(condition_image, height, width).to(device, dtype)
        densepose_tensor = self._pil_to_tensor(densepose, height, width).to(device, dtype)
        mask_tensor = self._mask_to_tensor(mask, height, width).to(device, dtype)

        prompt = "A photo of a person wearing the garment"
        prompt_embeds, pooled_prompt_embeds = self._encode_prompt(prompt, device, dtype, 1)
        negative_embeds, negative_pooled = self._encode_prompt("", device, dtype, 1)
        if guidance_scale > 1.0:
            prompt_embeds = torch.cat([negative_embeds, prompt_embeds])
            pooled_prompt_embeds = torch.cat([negative_pooled, pooled_prompt_embeds])

        person_latents = self.vae.encode(person).latent_dist.sample(generator)
        person_latents = person_latents * self.vae.config.scaling_factor
        garment_latents = self.vae.encode(garment).latent_dist.sample(generator)
        garment_latents = garment_latents * self.vae.config.scaling_factor
        mask_latents = F.interpolate(mask_tensor, size=(person_latents.shape[-2], person_latents.shape[-1]), mode="nearest")
        masked_person_latents = person_latents * (1 - mask_latents)
        densepose_latents = self.vae.encode(densepose_tensor).latent_dist.sample(generator)
        densepose_latents = densepose_latents * self.vae.config.scaling_factor
        inpaint_latents = torch.cat([masked_person_latents, densepose_latents], dim=1)

        garment_features = self._encode_garment(garment_latents, prompt_embeds, height, width)
        noise = torch.randn(person_latents.shape, generator=generator, device=device, dtype=dtype)
        latents = noise
        self.scheduler.set_timesteps(num_inference_steps, device=device)
        timesteps = self.scheduler.timesteps
        add_time_ids = self._get_add_time_ids((height, width), (0, 0), (height, width), dtype, device)

        for i, t in enumerate(timesteps):
            latent_model_input = torch.cat([latents] * 2) if guidance_scale > 1.0 else latents
            inpaint_input = torch.cat([inpaint_latents] * 2) if guidance_scale > 1.0 else inpaint_latents
            latent_model_input = torch.cat([latent_model_input, inpaint_input], dim=1)
            latent_model_input = self.scheduler.scale_model_input(latent_model_input, t)
            
            feat_to_set = garment_features[0] if isinstance(garment_features, list) else garment_features
            for module in self.unet.modules():
                if hasattr(module, "processor") and hasattr(module.processor, "garment_features"):
                    module.processor.garment_features = feat_to_set

            added_cond_kwargs = {"text_embeds": pooled_prompt_embeds, "time_ids": add_time_ids}
            noise_pred = self.unet(latent_model_input, t, encoder_hidden_states=prompt_embeds, added_cond_kwargs=added_cond_kwargs, return_dict=False)[0]
            if guidance_scale > 1.0:
                noise_pred_uncond, noise_pred_cond = noise_pred.chunk(2)
                noise_pred = noise_pred_uncond + guidance_scale * (noise_pred_cond - noise_pred_uncond)
            latents = self.scheduler.step(noise_pred, t, latents, generator=generator, return_dict=False)[0]

        result = self.vae.decode(latents / self.vae.config.scaling_factor, return_dict=False)[0]
        result = (result / 2 + 0.5).clamp(0, 1)
        result = result.cpu().permute(0, 2, 3, 1).numpy()
        result_images = [Image.fromarray((img * 255).astype(np.uint8)) for img in result]
        from dataclasses import dataclass
        @dataclass
        class Output: images: List[Image.Image]
        return Output(images=result_images)

    def _encode_garment(self, garment_latents, prompt_embeds, height, width):
        features = []
        def hook_fn(module, input, output): features.append(output)
        hooks = [m.register_forward_hook(hook_fn) for n, m in self.unet_encoder.named_modules() if "down_blocks" in n and "resnets" in n and n.endswith("0")]
        _ = self.unet_encoder(garment_latents, torch.tensor(0, device=garment_latents.device), encoder_hidden_states=prompt_embeds[:1] if prompt_embeds.shape[0] > 1 else prompt_embeds, return_dict=False)
        for h in hooks: h.remove()
        return features if features else [garment_latents]

    def _encode_prompt(self, prompt, device, dtype, num_images_per_prompt=1):
        tokens_1 = self.tokenizer(prompt, padding="max_length", max_length=self.tokenizer.model_max_length, truncation=True, return_tensors="pt").input_ids.to(device)
        embeds_1 = self.text_encoder(tokens_1, output_hidden_states=False).last_hidden_state
        tokens_2 = self.tokenizer_2(prompt, padding="max_length", max_length=self.tokenizer_2.model_max_length, truncation=True, return_tensors="pt").input_ids.to(device)
        out_2 = self.text_encoder_2(tokens_2)
        embeds_2 = out_2.last_hidden_state
        prompt_embeds = torch.cat([embeds_1, embeds_2], dim=-1)
        pooled_prompt_embeds = out_2.text_embeds
        bs_embed, seq_len, _ = prompt_embeds.shape
        prompt_embeds = prompt_embeds.repeat(1, num_images_per_prompt, 1).view(bs_embed * num_images_per_prompt, seq_len, -1)
        pooled_prompt_embeds = pooled_prompt_embeds.repeat(1, num_images_per_prompt, 1).view(bs_embed * num_images_per_prompt, -1)
        return prompt_embeds.to(dtype), pooled_prompt_embeds.to(dtype)

    def _get_add_time_ids(self, original_size, crops_coords_top_left, target_size, dtype, device):
        add_time_ids = list(original_size) + list(crops_coords_top_left) + list(target_size)
        return torch.tensor([add_time_ids], dtype=dtype, device=device)

    @staticmethod
    def _pil_to_tensor(image, height, width):
        image = image.convert("RGB").resize((width, height), Image.LANCZOS)
        np_image = np.array(image).astype(np.float32) / 255.0
        np_image = (np_image - 0.5) / 0.5
        return torch.from_numpy(np_image).permute(2, 0, 1).unsqueeze(0)

    @staticmethod
    def _mask_to_tensor(mask, height, width):
        mask = mask.convert("L").resize((width, height), Image.LANCZOS)
        np_mask = np.array(mask).astype(np.float32) / 255.0
        return torch.from_numpy(np_mask).unsqueeze(0).unsqueeze(0)
