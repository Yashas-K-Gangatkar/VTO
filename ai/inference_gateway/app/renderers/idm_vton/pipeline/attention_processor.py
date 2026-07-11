"""Custom attention processor for IDM-VTON (IP-Adapter style)."""
from __future__ import annotations
import torch
import torch.nn as nn
from diffusers.models.attention_processor import Attention, AttnProcessor2_0

class GarmentCrossAttentionProcessor(nn.Module):
    def __init__(self, hidden_size, cross_attention_dim=None):
        super().__init__()
        self.to_k_ip = nn.Linear(cross_attention_dim or hidden_size, hidden_size, bias=False)
        self.to_v_ip = nn.Linear(cross_attention_dim or hidden_size, hidden_size, bias=False)
        self.garment_features = None

    def __call__(self, attn: Attention, hidden_states, encoder_hidden_states=None, attention_mask=None, temb=None, *args, **kwargs):
        residual = hidden_states
        if attn.spatial_norm is not None: hidden_states = attn.spatial_norm(hidden_states, temb)
        input_ndim = hidden_states.ndim
        if input_ndim == 4:
            batch_size, channel, height, width = hidden_states.shape
            hidden_states = hidden_states.view(batch_size, channel, height * width).transpose(1, 2)
        batch_size, sequence_length, _ = hidden_states.shape if encoder_hidden_states is None else encoder_hidden_states.shape
        attention_mask = attn.prepare_attention_mask(attention_mask, sequence_length, batch_size)
        if attn.group_norm is not None: hidden_states = attn.group_norm(hidden_states.transpose(1, 2)).transpose(1, 2)
        query = attn.to_q(hidden_states)
        if encoder_hidden_states is None: encoder_hidden_states = hidden_states
        key = attn.to_k(encoder_hidden_states)
        value = attn.to_v(encoder_hidden_states)
        query = attn.head_to_batch_dim(query)
        key = attn.head_to_batch_dim(key)
        value = attn.head_to_batch_dim(value)
        attention_probs = attn.get_attention_scores(query, key, attention_mask)
        hidden_states = torch.bmm(attention_probs, value)
        hidden_states = attn.batch_to_head_dim(hidden_states)
        hidden_states = attn.to_out[0](hidden_states)
        hidden_states = attn.to_out[1](hidden_states)

        if self.garment_features is not None:
            ip_hidden_states = self.garment_features
            if ip_hidden_states.shape[0] < batch_size: ip_hidden_states = ip_hidden_states.repeat(batch_size // ip_hidden_states.shape[0], 1, 1)
            ip_key = self.to_k_ip(ip_hidden_states)
            ip_value = self.to_v_ip(ip_hidden_states)
            ip_key = attn.head_to_batch_dim(ip_key)
            ip_value = attn.head_to_batch_dim(ip_value)
            ip_attention_probs = attn.get_attention_scores(query, ip_key, None)
            ip_hidden_states = torch.bmm(ip_attention_probs, ip_value)
            ip_hidden_states = attn.batch_to_head_dim(ip_hidden_states)
            hidden_states = hidden_states + ip_hidden_states

        if input_ndim == 4:
            batch_size, channel, height, width = hidden_states.shape
            hidden_states = hidden_states.transpose(-1, -2).reshape(batch_size, channel, height, width)
        if attn.residual_connection: hidden_states = hidden_states + residual
        hidden_states = hidden_states / attn.rescale_output_factor
        return hidden_states

def setup_garment_attention(unet_main):
    processors = {}
    for name, module in unet_main.named_modules():
        if isinstance(module, Attention):
            if name.endswith("attn2"):
                hidden_size = module.to_q.in_features
                cross_attention_dim = module.to_k.in_features
                processors[f"{name}.processor"] = GarmentCrossAttentionProcessor(hidden_size, cross_attention_dim)
            else:
                processors[f"{name}.processor"] = AttnProcessor2_0()
    if processors:
        unet_main.set_attn_processor(processors)
