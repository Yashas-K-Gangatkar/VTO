# Inference Gateway

GPU inference gateway for VTO try-on jobs. Model-agnostic via Renderer interface.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | /health | Liveness + renderer status |
| GET | /health/ready | Readiness (200 only if renderer ready) |
| GET | /metrics | Basic metrics |
| GET | /docs | OpenAPI Swagger UI |

## Run locally

    pip install -r requirements.txt
    VTO_RENDERER=mock uvicorn app.main:app --reload --port 8090
    pytest tests/ -v
