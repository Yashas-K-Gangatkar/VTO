# VTO PROJECT MASTER BLUEPRINT & MEMORY FILE
**Last Updated:** 2025-07-14
**Status:** Active Development

## 1. PROJECT VISION & BUSINESS MODEL
**Name:** VTO (Virtual Try-On) Platform
**Architecture:** B2B SaaS + SDK Infrastructure ("Visa Network for Digital Bodies")

### The Problem Solved
Customers in retail stores (Westside, Zodio, Versace) wait in long queues for trial rooms. They want to try many garments quickly without physical trial.

### The Core Solution
1. **Scan Once, Use Forever:** Customer creates a 3D "Digital Twin" of their body ONE time.
2. **Cross-App SDK:** This 3D model is stored in VTO's cloud and accessible across *any* retailer's app that uses the VTO SDK.
3. **Zero-Cost Rendering:** Try-ons are rendered on the phone's GPU (3D Asset Mapping), not cloud GPUs. Cost per try-on = $0.00.
4. **Luxury vs Mass Market:** 
   - Mass Market (Westside): 2D photo converted to 3D garment (80% accuracy).
   - Luxury (Versace): Requires brand's 3D CAD files for 95% accuracy.

### Revenue Model
- **Mass Market:** ₹10,000/month base fee per store + 3% commission on sales.
- **Luxury:** ₹50,000/month base fee per boutique.
- **Zero per-click costs:** Browsing 100 garments costs the retailer $0.00.

---

## 2. TECHNOLOGY STACK & STATUS

### Backend (Python / FastAPI)
- **API Server:** `ai/inference_gateway/app/standalone_server.py`
- **Status:** ✅ Working (Mock mode on Render free tier, Real mode needs GPU)
- **Endpoints Built:**
  - `/api/v1/body/scan` (Extracts measurements from 6 photos)
  - `/api/v1/garment/analyze` (Extracts metadata from garment photo)
  - `/api/v1/tryon` (Calls IDM-VTON or returns mock)
  - `/api/v1/status` (Checks GPU availability)

### AI Engine (Python / PyTorch)
- **IDM-VTON Integration:** ✅ Working (Requires NVIDIA GPU, 16GB+ VRAM)
  - Bug fixes applied: `compat.py` (PositionNet stub), `_remove_lora` removed, `enable_sequential_cpu_offload` for T4.
  - Preprocessing: Segformer-B2 (parsing), OpenPose (pose).
- **Digital Human Pipeline:** ✅ Code written (`app/digital_human/`)
  - Stages: Capture Validation -> Body Extraction -> Measurement Extraction -> Profile Builder.
  - Visual Hull: ✅ Working (Voxel carving from 6 silhouettes, pure geometry, $0 cost).
- **Garment Intelligence Pipeline:** ✅ Code written (`app/garment_intelligence/`)
  - Steps: BG removal -> Segmentation -> Category -> Sleeve -> Collar -> Color -> Pattern -> Fabric -> Measurements -> CLIP Embedding.

### Frontend / SDKs (TypeScript / React Native)
- **Web SDK:** ✅ Basic structure built (`sdks/web/src/index.ts`)
  - Methods: `scanBody`, `analyzeGarment`, `tryOn`, `getStatus`.
- **Mobile App (Expo):** ✅ Basic 2D UI built (`apps/mobile/App.tsx`)
  - Needs upgrade to `react-three-fiber` for 3D Asset Mapping.
- **Retailer Dashboard:** ❌ Not started (Web UI for catalog upload).

### Infrastructure
- **Repository:** https://github.com/Yashas-K-Gangatkar/VTO
- **Hosting:** Render.com (API), Cloudflare R2/AWS S3 (Storage).
- **3D Reconstruction:** Luma AI API (freemium) or PIFuHD (self-hosted).

---

## 3. CRITICAL BUG FIXES & PATCHES (DO NOT LOSE THESE)

### IDM-VTON on Kaggle/Colab (diffusers 0.27.2)
1. **PositionNet:** Inject stub into `diffusers.models.embeddings` (removed in 0.22+). Handled by `app/renderers/idm_vton/compat.py`.
2. **`_remove_lora`:** Remove parameter from `set_attn_processor` calls in `src/unet_hacked_tryon.py` and `src/unet_hacked_garmnet.py` (removed in 0.26+).
3. **T4 OOM:** Use `enable_sequential_cpu_offload()` instead of `.to(device_str)` in `model.py`.
4. **LCMScheduler:** Use `EulerDiscreteScheduler` as shim if diffusers 0.25.0, else native LCMScheduler.
5. **Pose Image:** OpenPose returns 512x768. MUST resize to match person image (e.g., 256x384) before tensor conversion.
6. **Transformers/Scipy Crash:** Kaggle's `scipy`/`numpy` ABI breaks `transformers`. Use `os.environ["TRANSFORMERS_NO_TF"] = "1"` and `onnxruntime` for rembg. If scipy breaks, use OpenCV GrabCut for silhouettes instead of rembg.

### Kaggle Environment Specifics
- Kaggle T4 has 16GB VRAM. IDM-VTON fits at 128x192 or 256x384 resolution with CPU offload.
- Kaggle system RAM is 13GB (free) or 30GB (Kaggle T4 x2). Preprocessing models (Segformer, OpenPose) must run on CPU to avoid GPU OOM.

---

## 4. IMMEDIATE NEXT STEPS (ROADMAP)

### Step 1: Cloud Sync API (Digital Twin Wallet) [IN PROGRESS]
- Add endpoints to `routes.py`:
  - `POST /api/v1/body/sync-upload` (Upload .glb file + phone number)
  - `POST /api/v1/body/sync-request` (Request OTP via phone number)
  - `GET /api/v1/body/sync-retrieve` (Download .glb file using OTP token)

### Step 2: React Native SDK Module
- Package 3D viewer (`react-three-fiber`) and camera capture into `apps/mobile` or a standalone SDK package.
- Implement "Scan Once" flow and "Retrieve Digital Twin" flow.

### Step 3: Retailer Dashboard
- Web UI for shopkeepers to upload garment photos.
- Backend automatically runs Garment Intelligence Pipeline and assigns QR code.

### Step 4: 3D Asset Mapping Engine
- Integrate Three.js into mobile app.
- Load `.glb` body model and `.glb` garment model.
- Render on phone GPU for $0.00 cost per try-on.

---

## 5. IMPORTANT CONVERSATION CONTEXT
- User (Yashas) is building this for the Indian retail market (Westside, Zodio, etc.).
- Budget is currently $0. All solutions must work on free tiers or local machines.
- Yashas independently invented "Visual Hull" (voxel carving) and "Edge Computing/3D Asset Mapping" to solve the cost problem.
- The goal is to pitch to brands to raise funds, using the demo built on free tiers.
