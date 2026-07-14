"""Standalone VTO API server for free-tier deployment.

This server runs WITHOUT Postgres, Redis, or GPU.
It serves the API in mock mode by default.
Set VTO_GPU_ENABLED=true to enable real inference (needs GPU).

Deploy to Render.com:
  render.yaml is in the repo root.

Run locally:
  pip install fastapi uvicorn python-multipart pillow
  python -m app.standalone_server
"""

from __future__ import annotations

import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

# Apply compat patches before any IDM-VTON imports
if os.getenv("VTO_GPU_ENABLED", "false").lower() == "true":
    import app.renderers.idm_vton.compat  # noqa: F401

from app.api.routes import router

app = FastAPI(
    title="VTO API",
    version="1.0.0",
    description="Virtual Try-On API — body scanning, garment analysis, try-on inference",
    docs_url="/docs",
    redoc_url="/redoc",
)

# Allow all origins (for mobile app + retailer SDK)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount API routes
app.include_router(router)


@app.get("/")
async def root():
    return {
        "name": "VTO API",
        "version": "1.0.0",
        "docs": "/docs",
        "status": "/api/v1/status",
    }


@app.get("/health")
async def health():
    return {"status": "ok"}


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
