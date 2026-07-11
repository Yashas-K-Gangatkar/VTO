#!/usr/bin/env python3
"""Benchmark script for IDM-VTON inference.

Runs a single inference, measures everything, writes a report.

Usage:
    cd ai/inference_gateway
    python scripts/benchmark.py --model-path /path/to/idm-vton --person person.jpg --garment garment.jpg

On Mac (MPS):
    python scripts/benchmark.py --model-path /path/to/idm-vton --person tests/fixtures/person.jpg --garment tests/fixtures/garment.jpg --device mps

Output:
    - benchmarks/outputs/baseline/result.png (the rendered image)
    - benchmarks/reports/baseline.csv (appended row with measurements)
    - Console summary with all metrics
"""

import argparse
import csv
import os
import sys
import time
from datetime import datetime
from pathlib import Path

# Add parent to path so we can import app
sys.path.insert(0, str(Path(__file__).parent.parent))

from PIL import Image
import numpy as np


def detect_device():
    """Auto-detect best available device."""
    try:
        import torch
        if torch.cuda.is_available():
            return "cuda", torch.cuda.get_device_name(0)
        if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            return "mps", "Apple Silicon (MPS)"
        return "cpu", "CPU"
    except ImportError:
        print("ERROR: PyTorch not installed. Run: pip install -r requirements-idm-vton.txt")
        sys.exit(1)


def measure_vram(device):
    """Measure current VRAM usage in MB."""
    try:
        import torch
        if device == "cuda":
            return torch.cuda.memory_allocated() / (1024 * 1024)
        elif device == "mps":
            return torch.mps.current_allocated_memory() / (1024 * 1024)
        else:
            return 0.0
    except Exception:
        return 0.0


def get_gpu_memory_total(device):
    """Get total GPU memory in MB."""
    try:
        import torch
        if device == "cuda":
            return torch.cuda.get_device_properties(0).total_memory / (1024 * 1024)
        elif device == "mps":
            # MPS doesn't expose total memory directly — use system memory
            import subprocess
            result = subprocess.run(["sysctl", "-n", "hw.memsize"], capture_output=True, text=True)
            return int(result.stdout.strip()) / (1024 * 1024)
        else:
            return 0.0
    except Exception:
        return 0.0


def run_benchmark(model_path, person_path, garment_path, device, steps, output_dir):
    """Run a single benchmark inference."""
    from app.renderers.idm_vton.renderer import IDMVTONRenderer
    from app.renderers.base import RenderRequest

    print(f"\n{'='*60}")
    print(f"IDM-VTON Benchmark")
    print(f"{'='*60}")
    print(f"  Model:    {model_path}")
    print(f"  Person:   {person_path}")
    print(f"  Garment:  {garment_path}")
    print(f"  Device:   {device}")
    print(f"  Steps:    {steps}")
    print()

    # Check model path
    if not os.path.exists(model_path):
        print(f"ERROR: Model path does not exist: {model_path}")
        print("Run: ./setup-idm-vton.sh /path/to/models")
        sys.exit(1)

    # Check images
    if not os.path.exists(person_path):
        print(f"ERROR: Person image not found: {person_path}")
        sys.exit(1)
    if not os.path.exists(garment_path):
        print(f"ERROR: Garment image not found: {garment_path}")
        sys.exit(1)

    # Load images
    person_img = Image.open(person_path).convert("RGB")
    garment_img = Image.open(garment_path).convert("RGB")
    print(f"  Person image:   {person_img.size}")
    print(f"  Garment image:  {garment_img.size}")
    print()

    # Create renderer
    print("Loading model (this takes 10-30 seconds)...")
    load_start = time.monotonic()

    # On MPS, disable FP16 (it's buggy)
    use_fp16 = (device == "cuda")

    renderer = IDMVTONRenderer(
        model_path=model_path,
        device=device,
        width=768,
        height=1024,
        num_inference_steps=steps,
        guidance_scale=2.0,
    )

    renderer.warmup()
    load_time = time.monotonic() - load_start
    print(f"  Model loaded in {load_time:.1f}s")
    print()

    # Measure VRAM before inference
    vram_before = measure_vram(device)

    # Run inference
    print(f"Running inference ({steps} steps)...")

    request = RenderRequest(
        person_image=person_img,
        garment_image=garment_img,
        view="front",
        seed=42,
    )

    inference_start = time.monotonic()
    result = renderer.render(request)
    inference_time = time.monotonic() - inference_start

    # Measure VRAM after inference
    vram_after = measure_vram(device)
    vram_used = vram_after - vram_before

    print(f"  Inference complete in {inference_time:.1f}s ({inference_time*1000:.0f}ms)")
    print(f"  VRAM used: {vram_after:.0f} MB")
    print(f"  Quality score: {result.quality_score}")
    print()

    # Save result image
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    result_path = output_dir / "result.png"
    result.image.save(str(result_path))
    print(f"  Result saved to: {result_path}")
    print()

    # Verify it's not a placeholder
    arr = np.array(result.image)
    is_placeholder = (arr[:, :, 0] == arr[:, :, 1]).all() and (arr[:, :, 1] == arr[:, :, 2]).all()

    if is_placeholder:
        status = "FAIL_PLACEHOLDER"
        print("  WARNING: Result appears to be a placeholder (gray image)")
    elif arr.mean() < 10 or arr.mean() > 245:
        status = "FAIL_BAD_IMAGE"
        print("  WARNING: Result image is too dark or too bright")
    else:
        status = "PASS"
        print("  RESULT IS A REAL IMAGE — NOT A PLACEHOLDER")

    # Print summary
    gpu_name = "Apple Silicon (MPS)" if device == "mps" else "Unknown"
    if device == "cuda":
        import torch
        gpu_name = torch.cuda.get_device_name(0)

    total_vram = get_gpu_memory_total(device)

    print(f"\n{'='*60}")
    print(f"BENCHMARK SUMMARY")
    print(f"{'='*60}")
    print(f"  GPU:              {gpu_name}")
    print(f"  Device:           {device}")
    print(f"  Inference steps:  {steps}")
    print(f"  Inference time:   {inference_time:.2f}s ({inference_time*1000:.0f}ms)")
    print(f"  VRAM used:        {vram_after:.0f} MB / {total_vram:.0f} MB total")
    print(f"  Resolution:       768x1024")
    print(f"  Quality score:    {result.quality_score}")
    print(f"  Status:           {status}")
    print(f"  Result image:     {result_path}")
    print(f"{'='*60}")
    print()

    # Write to CSV
    csv_path = Path(__file__).parent.parent.parent.parent / "benchmarks" / "reports" / "baseline.csv"
    csv_path.parent.mkdir(parents=True, exist_ok=True)

    row = [
        datetime.now().isoformat(),
        gpu_name,
        device,
        steps,
        int(inference_time * 1000),
        int(vram_after),
        "768x1024",
        result.quality_score,
        status,
    ]

    with open(csv_path, "a", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(row)

    print(f"  Benchmark written to: {csv_path}")

    # Cleanup
    renderer.teardown()

    return 0 if status == "PASS" else 1


def main():
    parser = argparse.ArgumentParser(description="IDM-VTON Benchmark")
    parser.add_argument("--model-path", required=True, help="Path to IDM-VTON model weights")
    parser.add_argument("--person", required=True, help="Path to person image")
    parser.add_argument("--garment", required=True, help="Path to garment image")
    parser.add_argument("--device", default="auto", help="Device: auto, cuda, mps, cpu")
    parser.add_argument("--steps", type=int, default=30, help="Number of inference steps")
    parser.add_argument("--output-dir", default="benchmarks/outputs/baseline", help="Output directory")
    args = parser.parse_args()

    # Auto-detect device
    if args.device == "auto":
        device, _ = detect_device()
        print(f"Auto-detected device: {device}")
    else:
        device = args.device

    # Set MPS fallback settings
    if device == "mps":
        os.environ["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"

    return run_benchmark(
        model_path=args.model_path,
        person_path=args.person,
        garment_path=args.garment,
        device=device,
        steps=args.steps,
        output_dir=args.output_dir,
    )


if __name__ == "__main__":
    sys.exit(main())
