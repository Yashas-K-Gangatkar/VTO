# VTO — Virtual Try-On Platform

B2B SaaS platform for retail virtual try-on. Customers scan QR codes
on garment tags, upload photos, and see themselves wearing the garment.

## Quick Start

### 1. API (free deployment on Render.com)

```bash
# Local development
cd ai/inference_gateway
pip install -r requirements.txt
python -m uvicorn app.standalone_server:app --reload --port 8000

# Deploy to Render (free)
# 1. Go to render.com → New → Web Service
# 2. Connect your GitHub repo
# 3. Render will auto-detect render.yaml
# 4. Click Create
```

API docs available at `http://localhost:8000/docs`

### 2. Mobile App (test on phone via Expo Go)

```bash
cd apps/mobile
npm install
npx expo start
# Scan the QR code with Expo Go app on your phone
```

Install Expo Go on your phone:
- iOS: App Store → "Expo Go"
- Android: Play Store → "Expo Go"

### 3. Retailer SDK (TypeScript)

```bash
cd sdks/web
npm install
npm run build
```

Use in any web project:

```typescript
import { VTOClient } from '@vto/sdk';

const client = new VTOClient({
  apiKey: 'your-api-key',
  baseUrl: 'https://your-api.onrender.com',
});

// Scan body from 6 photos
const profile = await client.scanBody(photos);

// Analyze garment
const garment = await client.analyzeGarment(frontPhoto);

// Run try-on
const result = await client.tryOn(personPhoto, garmentPhoto);
// result.image = base64 PNG
```

## Architecture

```
Customer Phone (Expo app)
        ↓
    VTO API (FastAPI on Render)
        ├── /api/v1/body/scan → BodyProfile
        ├── /api/v1/garment/analyze → GarmentProfile
        └── /api/v1/tryon → try-on image
        ↓
    GPU Server (when VTO_GPU_ENABLED=true)
        ├── DigitalHumanPipeline
        ├── GarmentIntelligencePipeline
        └── IDM-VTON Renderer
```

## Modes

| Mode | VTO_GPU_ENABLED | What happens |
|------|-----------------|-------------|
| Mock | false | Returns placeholder data. Deploys free. |
| Real | true | Runs actual ML inference. Needs GPU. |

Mock mode lets you test the full app flow without GPU.
Switch to real mode when you have GPU infrastructure.

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/body/scan` | POST | Scan body from 6 photos |
| `/api/v1/garment/analyze` | POST | Analyze garment from photo |
| `/api/v1/tryon` | POST | Run virtual try-on |
| `/api/v1/status` | GET | Check GPU mode |
| `/health` | GET | Health check |
| `/docs` | GET | API documentation |
