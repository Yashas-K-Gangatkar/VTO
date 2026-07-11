# GPU Validation Runbook (Sprint 3.5)

## Goal

Prove IDM-VTON produces a real try-on image and establish baseline metrics.

## Prerequisites

- Python 3.11+
- Git
- 15GB free disk space (for model weights)
- A GPU: NVIDIA (CUDA) or Apple Silicon (MPS)

## Step 1: Install dependencies

    cd ai/inference_gateway
    pip install -r requirements.txt
    pip install -r requirements-idm-vton.txt

For Mac (MPS), install CPU-only PyTorch:

    pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu

## Step 2: Download model weights

    cd ai/inference_gateway
    ./setup-idm-vton.sh ~/models

This downloads ~7GB:
- IDM-VTON model weights (yisol/IDM-VTON from HuggingFace)
- OpenPose model
- Human parsing model

## Step 3: Get test images

Option A — Use IDM-VTON repo test images:

    git clone https://github.com/yisol/IDM-VTON.git /tmp/idm-vton
    cp /tmp/idm-vton/test/image tests/fixtures/person.jpg
    cp /tmp/idm-vton/test/garment tests/fixtures/garment.jpg

Option B — Use your own:
- person.jpg: Full-body photo of a person
- garment.jpg: Garment product photo on white background

## Step 4: Run the benchmark

    cd ai/inference_gateway
    python scripts/benchmark.py \
        --model-path ~/models/idm-vton \
        --person tests/fixtures/person.jpg \
        --garment tests/fixtures/garment.jpg

On Mac (force MPS):

    python scripts/benchmark.py \
        --model-path ~/models/idm-vton \
        --person tests/fixtures/person.jpg \
        --garment tests/fixtures/garment.jpg \
        --device mps

## Step 5: Check the results

The script prints a summary like:

    BENCHMARK SUMMARY
    GPU:              Apple Silicon (MPS)
    Device:           mps
    Inference steps:  30
    Inference time:   120.5s
    VRAM used:        8234 MB
    Resolution:       768x1024
    Quality score:    0.82
    Status:           PASS
    Result image:     benchmarks/outputs/baseline/result.png

Open result.png and verify it looks like a real try-on image.

## Step 6: Record the benchmark

The script automatically appends to benchmarks/reports/baseline.csv.

Copy the result image and summary to the GPU-specific file:

    benchmarks/gpu/mps-m5.md      (for Mac)
    benchmarks/gpu/rtx4090.md     (for NVIDIA)

## What to look for

PASS criteria:
- result.png shows a person wearing the garment (not a gray rectangle)
- Inference completes without crashing
- Quality score > 0.5

FAIL criteria:
- Result is a gray rectangle (MockRenderer placeholder)
- Result is pure black or pure white
- Crash or OOM error

## After validation

Once the benchmark passes:
1. Commit the benchmark results to the repo
2. The baseline is established — Sprint 4 can begin
3. Each Sprint 4 optimization (FP16, LCM, TensorRT) re-runs this benchmark
4. Compare before/after to measure improvement

## Troubleshooting

### MPS out of memory
Reduce resolution: --steps 15 (half the inference steps)

### MPS operation not supported
Set: export PYTORCH_ENABLE_MPS_FALLBACK=1
This falls back to CPU for unsupported ops (slower but works)

### Model not found
Run: ./setup-idm-vton.sh ~/models
Verify: ls ~/models/idm-vton/ should show unet_encoder, unet_main, vae, etc.

### ImportError: No module named torch
pip install -r requirements-idm-vton.txt
