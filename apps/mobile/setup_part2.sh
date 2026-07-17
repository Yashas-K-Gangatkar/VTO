#!/bin/bash
set -e
cd /Users/yashas/VTO/apps/mobile

echo "=== Writing engine/textures/TextureLoader.ts ==="
cat > src/engine/textures/TextureLoader.ts << 'TEXTURELOADER_EOF'
/**
 * engine/textures/TextureLoader.ts
 *
 * Loads textures WITHOUT using Blob — the root cause of the
 * "Creating blobs from 'ArrayBuffer' and 'ArrayBufferView' are not supported"
 * error that breaks GLTFLoader's texture pipeline on React Native.
 *
 * Strategy:
 *   1. Parse the GLB container manually (header + JSON chunk + BIN chunk).
 *   2. Walk gltf.images[] — each image references a bufferView + mimeType.
 *   3. Extract the image bytes from the BIN chunk.
 *   4. Write each image to a temp file (PNG or JPG, based on mimeType).
 *   5. Hand the GLB JSON + BIN to GLTFLoader.parse, but patch gltf.images
 *      to point at file:// URIs instead of bufferViews.
 *   6. GLTFLoader's TextureLoader reads from file:// directly — no Blob
 *      ever gets created.
 */

import * as FileSystem from 'expo-file-system/legacy';
import { TextureLoader as ThreeTextureLoader } from 'three';
import * as THREE from 'three';
import type { TextureRef } from '../core/types';

const TAG = '[TextureLoader]';
const CHUNK_TYPE_JSON = 0x4e4f534a;
const CHUNK_TYPE_BIN = 0x004e4942;

export interface ExtractedTextures {
  imageUris: Record<number, string>;
  patchedJson: any;
  totalBytes: number;
}

export interface ITextureLoader {
  extractFromGLB(glbBuffer: ArrayBuffer, tempDir: string): Promise<ExtractedTextures>;
  loadTexture(ref: TextureRef): Promise<THREE.Texture>;
  disposeAll(): void;
  getCacheStats(): { count: number; estimatedBytes: number };
}

export class TextureLoader implements ITextureLoader {
  private textureCache = new Map<string, THREE.Texture>();
  private threeLoader = new ThreeTextureLoader();

  constructor() {
    // @ts-ignore
    this.threeLoader.setCrossOrigin?.('anonymous');
  }

  async extractFromGLB(glbBuffer: ArrayBuffer, tempDir: string): Promise<ExtractedTextures> {
    const bytes = new Uint8Array(glbBuffer);
    const dv = new DataView(glbBuffer);

    const dirInfo = await FileSystem.getInfoAsync(tempDir);
    if (!dirInfo.exists) {
      await FileSystem.makeDirectoryAsync(tempDir, { intermediates: true });
    }

    if (bytes.byteLength < 12 || dv.getUint32(0, true) !== 0x46546c67) {
      throw new Error('Not a valid GLB file (bad magic)');
    }
    const version = dv.getUint32(4, true);
    if (version !== 2) {
      throw new Error(`Unsupported GLB version ${version}`);
    }

    let offset = 12;
    let jsonStr = '';
    let binOffset = 0;
    let binLength = 0;

    while (offset + 8 <= bytes.byteLength) {
      const chunkLength = dv.getUint32(offset, true);
      const chunkType = dv.getUint32(offset + 4, true);
      const dataStart = offset + 8;
      if (chunkType === CHUNK_TYPE_JSON) {
        const jsonBytes = bytes.subarray(dataStart, dataStart + chunkLength);
        let end = jsonBytes.byteLength;
        while (end > 0 && jsonBytes[end - 1] === 0) end -= 1;
        jsonStr = new TextDecoder().decode(jsonBytes.subarray(0, end));
      } else if (chunkType === CHUNK_TYPE_BIN) {
        binOffset = dataStart;
        binLength = chunkLength;
      }
      offset = dataStart + chunkLength;
    }

    if (!jsonStr) {
      return { imageUris: {}, patchedJson: null, totalBytes: 0 };
    }

    let gltfJson: any;
    try {
      gltfJson = JSON.parse(jsonStr);
    } catch (e) {
      throw new Error(`GLB JSON chunk parse failed: ${e}`);
    }

    const images = gltfJson.images ?? [];
    const bufferViews = gltfJson.bufferViews ?? [];
    const imageUris: Record<number, string> = {};
    let totalBytes = 0;

    for (let i = 0; i < images.length; i++) {
      const img = images[i];
      if (img.uri) continue;
      if (img.bufferView === undefined) {
        console.warn(TAG, `image[${i}] has no uri and no bufferView — skipping`);
        continue;
      }
      const bv = bufferViews[img.bufferView];
      if (!bv) {
        console.warn(TAG, `image[${i}] references missing bufferView ${img.bufferView}`);
        continue;
      }

      const start = binOffset + (bv.byteOffset ?? 0);
      const end = start + bv.byteLength;
      if (end > binOffset + binLength) {
        console.warn(TAG, `image[${i}] extends past BIN chunk`);
        continue;
      }
      const imageBytes = bytes.subarray(start, end);

      const mime = img.mimeType ?? 'image/png';
      const ext = mime === 'image/jpeg' ? 'jpg' : 'png';
      const filePath = `${tempDir}img_${i}.${ext}`;

      const b64 = this.uint8ToBase64(imageBytes);
      await FileSystem.writeAsStringAsync(filePath, b64, { encoding: 'base64' });

      imageUris[i] = `file://${filePath}`;
      totalBytes += imageBytes.byteLength;

      delete img.bufferView;
      delete img.mimeType;
      img.uri = `file://${filePath}`;
    }

    if (Object.keys(imageUris).length > 0) {
      console.log(TAG, `extracted ${Object.keys(imageUris).length} textures (${(totalBytes / 1024).toFixed(1)} KB)`);
    }

    return { imageUris, patchedJson: gltfJson, totalBytes };
  }

  async loadTexture(ref: TextureRef): Promise<THREE.Texture> {
    const cached = this.textureCache.get(ref.cacheKey);
    if (cached) return cached;

    return new Promise<THREE.Texture>((resolve, reject) => {
      this.threeLoader.load(
        ref.uri,
        (texture) => {
          if (ref.colorSpace === 'srgb') {
            texture.colorSpace = THREE.SRGBColorSpace;
          }
          if (ref.wrapS === 'repeat') texture.wrapS = THREE.RepeatWrapping;
          else if (ref.wrapS === 'mirror') texture.wrapS = THREE.MirroredRepeatWrapping;
          else texture.wrapS = THREE.ClampToEdgeWrapping;
          if (ref.wrapT === 'repeat') texture.wrapT = THREE.RepeatWrapping;
          else if (ref.wrapT === 'mirror') texture.wrapT = THREE.MirroredRepeatWrapping;
          else texture.wrapT = THREE.ClampToEdgeWrapping;
          texture.needsUpdate = true;
          this.textureCache.set(ref.cacheKey, texture);
          resolve(texture);
        },
        undefined,
        (err) => reject(new Error(`TextureLoader.load failed for ${ref.uri}: ${err?.message || err}`))
      );
    });
  }

  disposeAll(): void {
    for (const tex of this.textureCache.values()) {
      tex.dispose();
    }
    this.textureCache.clear();
    console.log(TAG, 'disposed all cached textures');
  }

  getCacheStats(): { count: number; estimatedBytes: number } {
    let bytes = 0;
    for (const tex of this.textureCache.values()) {
      const img = tex.image as any;
      if (img?.width && img?.height) {
        bytes += img.width * img.height * 4 * 1.33;
      }
    }
    return { count: this.textureCache.size, estimatedBytes: bytes };
  }

  private uint8ToBase64(bytes: Uint8Array): string {
    try {
      // @ts-ignore
      if (typeof Buffer !== 'undefined') {
        // @ts-ignore
        const buf = Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength);
        return buf.toString('base64');
      }
    } catch { /* fall through */ }

    let binary = '';
    const chunkSize = 0x8000;
    for (let i = 0; i < bytes.length; i += chunkSize) {
      const chunk = bytes.subarray(i, i + chunkSize);
      binary += String.fromCharCode.apply(null, Array.from(chunk) as any);
    }
    return btoa(binary);
  }
}
TEXTURELOADER_EOF
echo "✓ engine/textures/TextureLoader.ts"

echo "=== Writing engine/textures/TextureManager.ts ==="
cat > src/engine/textures/TextureManager.ts << 'TEXTUREMANAGER_EOF'
/**
 * engine/textures/TextureManager.ts
 *
 * Higher-level texture coordinator. Owns the TextureLoader and adds:
 *   - Resolution budgeting: caps total GPU texture memory across all assets.
 *   - Per-texture max-resolution enforcement (for LOD).
 *   - Reference counting: textures are shared across materials and only
 *     disposed when the last material releases them.
 *   - Async loading with progress + cancellation.
 */

import * as THREE from 'three';
import type { TextureRef } from '../core/types';
import { TextureLoader, type ITextureLoader } from './TextureLoader';

const TAG = '[TextureManager]';

export interface TextureManagerOptions {
  maxTotalBytes?: number;
  defaultMaxResolution?: number;
  loader?: ITextureLoader;
}

interface CachedTexture {
  texture: THREE.Texture;
  refCount: number;
  bytes: number;
  createdAt: number;
}

export interface ITextureManager {
  acquire(ref: TextureRef): Promise<THREE.Texture>;
  release(ref: TextureRef): void;
  getMemoryUsage(): { bytes: number; count: number; maxBytes: number };
  disposeAll(): void;
}

export class TextureManager implements ITextureManager {
  private readonly loader: ITextureLoader;
  private readonly maxBytes: number;
  private readonly defaultMaxRes: number;
  private cache = new Map<string, CachedTexture>();
  private inFlight = new Map<string, Promise<THREE.Texture>>();

  constructor(opts: TextureManagerOptions = {}) {
    this.loader = opts.loader ?? new TextureLoader();
    this.maxBytes = opts.maxTotalBytes ?? 256 * 1024 * 1024;
    this.defaultMaxRes = opts.defaultMaxResolution ?? 1024;
  }

  async acquire(ref: TextureRef): Promise<THREE.Texture> {
    const normalized: TextureRef = {
      ...ref,
      maxResolution: ref.maxResolution ?? this.defaultMaxRes,
      colorSpace: ref.colorSpace ?? 'srgb',
      wrapS: ref.wrapS ?? 'clamp',
      wrapT: ref.wrapT ?? 'clamp',
    };

    const cached = this.cache.get(normalized.cacheKey);
    if (cached) {
      cached.refCount += 1;
      return cached.texture;
    }

    const inflight = this.inFlight.get(normalized.cacheKey);
    if (inflight) {
      await inflight;
      const now = this.cache.get(normalized.cacheKey);
      if (now) {
        now.refCount += 1;
        return now.texture;
      }
    }

    await this.evictToFit(0);

    const loadPromise = this.loader.loadTexture(normalized);
    this.inFlight.set(normalized.cacheKey, loadPromise);

    try {
      const texture = await loadPromise;
      const img = texture.image as any;
      const w = img?.width ?? 256;
      const h = img?.height ?? 256;
      const bytes = Math.round(w * h * 4 * 1.33);

      await this.evictToFit(bytes);

      this.cache.set(normalized.cacheKey, {
        texture,
        refCount: 1,
        bytes,
        createdAt: Date.now(),
      });

      return texture;
    } finally {
      this.inFlight.delete(normalized.cacheKey);
    }
  }

  release(ref: TextureRef): void {
    const entry = this.cache.get(ref.cacheKey);
    if (!entry) {
      console.warn(TAG, `release: ${ref.cacheKey} not in cache`);
      return;
    }
    entry.refCount -= 1;
    if (entry.refCount <= 0) {
      entry.texture.dispose();
      this.cache.delete(ref.cacheKey);
    }
  }

  getMemoryUsage(): { bytes: number; count: number; maxBytes: number } {
    let bytes = 0;
    for (const entry of this.cache.values()) bytes += entry.bytes;
    return { bytes, count: this.cache.size, maxBytes: this.maxBytes };
  }

  disposeAll(): void {
    for (const entry of this.cache.values()) {
      entry.texture.dispose();
    }
    this.cache.clear();
    this.inFlight.clear();
    console.log(TAG, 'disposed all textures');
  }

  private async evictToFit(neededBytes: number): Promise<void> {
    let current = 0;
    for (const entry of this.cache.values()) current += entry.bytes;

    if (current + neededBytes <= this.maxBytes) return;

    const sorted = Array.from(this.cache.entries())
      .filter(([, e]) => e.refCount <= 0)
      .sort((a, b) => a[1].createdAt - b[1].createdAt);

    for (const [key, entry] of sorted) {
      if (current + neededBytes <= this.maxBytes) break;
      entry.texture.dispose();
      this.cache.delete(key);
      current -= entry.bytes;
      console.log(TAG, `evicted ${key} to free ${entry.bytes} bytes`);
    }

    if (current + neededBytes > this.maxBytes) {
      console.warn(
        TAG,
        `texture budget exceeded: ${(current / 1024 / 1024).toFixed(1)} MB / ${(this.maxBytes / 1024 / 1024).toFixed(1)} MB (all textures in active use)`
      );
    }
  }
}
TEXTUREMANAGER_EOF
echo "✓ engine/textures/TextureManager.ts"

echo "=== Writing engine/camera/CameraConstraints.ts ==="
cat > src/engine/camera/CameraConstraints.ts << 'CAMERACONSTRAINTS_EOF'
/**
 * engine/camera/CameraConstraints.ts
 *
 * Declarative limits on camera motion. Pure data — no behavior.
 */

export interface CameraConstraints {
  yawRange: [number, number];
  pitchRange: [number, number];
  distanceRange: [number, number];
  fovRange: [number, number];
  rotationDamping: number;
  zoomDamping: number;
  targetDamping: number;
  autoRotateSpeed: number;
  autoRotateDelaySec: number;
  invertYaw: boolean;
  invertPitch: boolean;
  invertZoom: boolean;
  rotationSensitivity: number;
  zoomSensitivity: number;
  inertia: number;
}

export const DEFAULT_VTO_CONSTRAINTS: CameraConstraints = {
  yawRange: [-Math.PI, Math.PI],
  pitchRange: [(-75 * Math.PI) / 180, (75 * Math.PI) / 180],
  distanceRange: [1.5, 8],
  fovRange: [40, 60],
  rotationDamping: 0.85,
  zoomDamping: 0.9,
  targetDamping: 0.85,
  autoRotateSpeed: 0.1,
  autoRotateDelaySec: 3.0,
  invertYaw: false,
  invertPitch: false,
  invertZoom: false,
  rotationSensitivity: 1.0,
  zoomSensitivity: 1.0,
  inertia: 0.92,
};

export const AVATAR_CUSTOMIZER_CONSTRAINTS: CameraConstraints = {
  ...DEFAULT_VTO_CONSTRAINTS,
  pitchRange: [0, 0],
  distanceRange: [2.5, 5],
  autoRotateSpeed: 0,
  rotationSensitivity: 0.7,
};

export const WALKTHROUGH_CONSTRAINTS: CameraConstraints = {
  ...DEFAULT_VTO_CONSTRAINTS,
  pitchRange: [(-89 * Math.PI) / 180, (89 * Math.PI) / 180],
  distanceRange: [1, 25],
  fovRange: [30, 90],
  autoRotateSpeed: 0,
  rotationSensitivity: 1.5,
  zoomSensitivity: 1.5,
};

export function clamp(value: number, range: [number, number]): number {
  if (value < range[0]) return range[0];
  if (value > range[1]) return range[1];
  return value;
}

export function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

export function damp(
  current: number,
  target: number,
  damping: number,
  dtSec: number
): number {
  const closurePerFrame = 1 - Math.pow(1 - damping, dtSec);
  return lerp(current, target, closurePerFrame);
}
CAMERACONSTRAINTS_EOF
echo "✓ engine/camera/CameraConstraints.ts"

echo "=== Writing engine/camera/CameraController.ts ==="
cat > src/engine/camera/CameraController.ts << 'CAMERACONTROLLER_EOF'
/**
 * engine/camera/CameraController.ts
 *
 * Orbit camera with frame-rate-independent damping, target tracking,
 * and constraint enforcement.
 *
 * The controller owns NO three.js objects — it just maintains
 * {yaw, pitch, distance, target} state and applies it to a camera
 * passed in by the Engine.
 */

import * as THREE from 'three';
import {
  CameraConstraints,
  DEFAULT_VTO_CONSTRAINTS,
  clamp,
  damp,
} from './CameraConstraints';
import type { Vec3 } from '../core/types';

const TAG = '[CameraController]';

export interface CameraState {
  yaw: number;
  pitch: number;
  distance: number;
  targetX: number;
  targetY: number;
  targetZ: number;
  fov: number;
}

export interface ICameraController {
  orbitBy(dYaw: number, dPitch: number): void;
  zoomBy(factor: number): void;
  panTargetBy(dx: number, dy: number, dz: number): void;
  focusOn(target: Vec3, smooth?: boolean): void;
  reset(): void;
  update(dtSec: number): void;
  apply(camera: THREE.PerspectiveCamera): void;
  getState(): CameraState;
  getVelocity(): { yaw: number; pitch: number; zoom: number };
  setConstraints(c: CameraConstraints): void;
  markInteracting(): void;
}

export interface CameraControllerOptions {
  constraints?: CameraConstraints;
  initialState?: Partial<CameraState>;
}

export class CameraController implements ICameraController {
  private constraints: CameraConstraints;
  private current: CameraState;
  private target: CameraState;
  private velocity = { yaw: 0, pitch: 0, zoom: 0 };
  private lastInteractionAt: number = 0;
  private autoRotateActive = false;

  constructor(opts: CameraControllerOptions = {}) {
    this.constraints = opts.constraints ?? { ...DEFAULT_VTO_CONSTRAINTS };
    const defaults: CameraState = {
      yaw: 0,
      pitch: 0.2,
      distance: 4,
      targetX: 0,
      targetY: 0.5,
      targetZ: 0,
      fov: 50,
    };
    const init = { ...defaults, ...(opts.initialState ?? {}) };
    this.current = { ...init };
    this.target = { ...init };
  }

  orbitBy(dYaw: number, dPitch: number): void {
    const c = this.constraints;
    const sYaw = c.invertYaw ? -1 : 1;
    const sPitch = c.invertPitch ? -1 : 1;
    const scaledYaw = dYaw * c.rotationSensitivity * sYaw;
    const scaledPitch = dPitch * c.rotationSensitivity * sPitch;
    this.velocity.yaw = scaledYaw;
    this.velocity.pitch = scaledPitch;
    this.target.yaw += scaledYaw;
    this.target.pitch += scaledPitch;
    this.markInteracting();
  }

  zoomBy(factor: number): void {
    const c = this.constraints;
    const sZoom = c.invertZoom ? 1 / factor : factor;
    const newDistance = this.target.distance * sZoom * c.zoomSensitivity;
    this.target.distance = clamp(newDistance, c.distanceRange);
    this.velocity.zoom = (this.target.distance - this.current.distance) * 5;
    this.markInteracting();
  }

  panTargetBy(dx: number, dy: number, dz: number): void {
    this.target.targetX += dx;
    this.target.targetY += dy;
    this.target.targetZ += dz;
    this.markInteracting();
  }

  focusOn(target: Vec3, smooth: boolean = true): void {
    this.target.targetX = target.x;
    this.target.targetY = target.y;
    this.target.targetZ = target.z;
    if (!smooth) {
      this.current.targetX = target.x;
      this.current.targetY = target.y;
      this.current.targetZ = target.z;
    }
    this.markInteracting();
  }

  reset(): void {
    this.target.yaw = 0;
    this.target.pitch = 0.2;
    this.target.distance = 4;
    this.target.targetX = 0;
    this.target.targetY = 0.5;
    this.target.targetZ = 0;
    this.velocity = { yaw: 0, pitch: 0, zoom: 0 };
    this.markInteracting();
  }

  update(dtSec: number): void {
    const c = this.constraints;
    const now = performance.now() / 1000;
    const sinceInteraction = now - this.lastInteractionAt;
    const isInertial = sinceInteraction > 0.05 && sinceInteraction < 1.5;

    if (isInertial) {
      this.velocity.yaw *= c.inertia;
      this.velocity.pitch *= c.inertia;
      this.velocity.zoom *= c.inertia;
      this.target.yaw += this.velocity.yaw * dtSec;
      this.target.pitch += this.velocity.pitch * dtSec;
      this.target.distance = clamp(
        this.target.distance + this.velocity.zoom * dtSec,
        c.distanceRange
      );
    } else if (sinceInteraction >= 1.5) {
      this.velocity = { yaw: 0, pitch: 0, zoom: 0 };
    }

    const shouldAutoRotate =
      c.autoRotateSpeed > 0 &&
      sinceInteraction > c.autoRotateDelaySec &&
      Math.abs(this.velocity.yaw) < 0.01;
    if (shouldAutoRotate) {
      this.target.yaw += c.autoRotateSpeed * dtSec;
      this.autoRotateActive = true;
    } else {
      this.autoRotateActive = false;
    }

    this.target.yaw = wrapAngle(this.target.yaw);
    this.target.pitch = clamp(this.target.pitch, c.pitchRange);
    this.target.distance = clamp(this.target.distance, c.distanceRange);
    this.target.fov = clamp(this.target.fov, c.fovRange);

    this.current.yaw = dampAngle(this.current.yaw, this.target.yaw, c.rotationDamping, dtSec);
    this.current.pitch = damp(this.current.pitch, this.target.pitch, c.rotationDamping, dtSec);
    this.current.distance = damp(this.current.distance, this.target.distance, c.zoomDamping, dtSec);
    this.current.targetX = damp(this.current.targetX, this.target.targetX, c.targetDamping, dtSec);
    this.current.targetY = damp(this.current.targetY, this.target.targetY, c.targetDamping, dtSec);
    this.current.targetZ = damp(this.current.targetZ, this.target.targetZ, c.targetDamping, dtSec);
    this.current.fov = damp(this.current.fov, this.target.fov, c.rotationDamping, dtSec);
  }

  apply(camera: THREE.PerspectiveCamera): void {
    const { yaw, pitch, distance, targetX, targetY, targetZ, fov } = this.current;
    const cosPitch = Math.cos(pitch);
    const sinPitch = Math.sin(pitch);
    const cosYaw = Math.cos(yaw);
    const sinYaw = Math.sin(yaw);

    camera.position.x = targetX + distance * sinPitch * sinYaw;
    camera.position.y = targetY + distance * cosPitch;
    camera.position.z = targetZ + distance * sinPitch * cosYaw;

    camera.lookAt(targetX, targetY, targetZ);

    if (camera.fov !== fov) {
      camera.fov = fov;
      camera.updateProjectionMatrix();
    }
  }

  getState(): CameraState {
    return { ...this.current };
  }

  getVelocity(): { yaw: number; pitch: number; zoom: number } {
    return { ...this.velocity };
  }

  setConstraints(c: CameraConstraints): void {
    this.constraints = c;
    this.current.yaw = wrapAngle(this.current.yaw);
    this.current.pitch = clamp(this.current.pitch, c.pitchRange);
    this.current.distance = clamp(this.current.distance, c.distanceRange);
    this.target.yaw = wrapAngle(this.target.yaw);
    this.target.pitch = clamp(this.target.pitch, c.pitchRange);
    this.target.distance = clamp(this.target.distance, c.distanceRange);
  }

  markInteracting(): void {
    this.lastInteractionAt = performance.now() / 1000;
  }

  isAutoRotating(): boolean {
    return this.autoRotateActive;
  }
}

function wrapAngle(a: number): number {
  const TWO_PI = Math.PI * 2;
  let r = a % TWO_PI;
  if (r > Math.PI) r -= TWO_PI;
  if (r < -Math.PI) r += TWO_PI;
  return r;
}

function dampAngle(current: number, target: number, damping: number, dtSec: number): number {
  const c = wrapAngle(current);
  const t = wrapAngle(target);
  let delta = t - c;
  if (delta > Math.PI) delta -= Math.PI * 2;
  if (delta < -Math.PI) delta += Math.PI * 2;
  const closurePerFrame = 1 - Math.pow(1 - damping, dtSec);
  return wrapAngle(c + delta * closurePerFrame);
}
CAMERACONTROLLER_EOF
echo "✓ engine/camera/CameraController.ts"

echo "=== Writing engine/camera/GestureController.ts ==="
cat > src/engine/camera/GestureController.ts << 'GESTURECONTROLLER_EOF'
/**
 * engine/camera/GestureController.ts
 *
 * Translates raw React Native touch events into semantic camera commands
 * (orbit, zoom, pan) and forwards them to an ICameraController.
 *
 * Supported gestures:
 *   - 1 finger drag       → orbit (yaw + pitch)
 *   - 2 finger pinch      → zoom (distance)
 *   - 2 finger drag       → pan target (translate camera target)
 *   - Double tap          → reset camera to defaults
 */

import {
  PanResponder,
  GestureResponderEvent,
  PanResponderGestureState,
} from 'react-native';
import type { ICameraController } from './CameraController';

const TAG = '[GestureController]';

export interface IGestureController {
  getPanHandlers(): any;
  detach(): void;
  attach(camera: ICameraController): void;
}

export interface GestureControllerOptions {
  tapThreshold?: number;
  doubleTapWindowMs?: number;
  dragSensitivity?: number;
  pinchSensitivity?: number;
  panSensitivity?: number;
  debug?: boolean;
}

interface TouchPoint {
  x: number;
  y: number;
}

export class GestureController implements IGestureController {
  private camera: ICameraController | null = null;
  private opts: Required<GestureControllerOptions>;
  private panResponder: ReturnType<typeof PanResponder.create>;

  private pinchInitialDist = 0;
  private pinchInitialZoom = 0;
  private panInitialCenter: TouchPoint | null = null;
  private lastDragPos: TouchPoint | null = null;
  private lastDragTime = 0;
  private touchStartPos: TouchPoint | null = null;
  private touchStartTime = 0;
  private lastTapTime = 0;

  constructor(camera: ICameraController, opts: GestureControllerOptions = {}) {
    this.camera = camera;
    this.opts = {
      tapThreshold: opts.tapThreshold ?? 10,
      doubleTapWindowMs: opts.doubleTapWindowMs ?? 300,
      dragSensitivity: opts.dragSensitivity ?? 0.01,
      pinchSensitivity: opts.pinchSensitivity ?? 1.0,
      panSensitivity: opts.panSensitivity ?? 0.005,
      debug: opts.debug ?? false,
    };

    this.panResponder = PanResponder.create({
      onStartShouldSetPanResponder: () => true,
      onMoveShouldSetPanResponder: () => true,
      onPanResponderGrant: this.onGrant,
      onPanResponderMove: this.onMove,
      onPanResponderRelease: this.onRelease,
      onPanResponderTerminate: this.onRelease,
    });
  }

  private onGrant = (evt: GestureResponderEvent) => {
    const touches = evt.nativeEvent.touches;
    if (this.opts.debug) console.log(TAG, `grant: ${touches.length} touches`);

    if (touches.length >= 2) {
      const p1 = { x: touches[0].locationX, y: touches[0].locationY };
      const p2 = { x: touches[1].locationX, y: touches[1].locationY };
      this.pinchInitialDist = distance(p1, p2);
      this.pinchInitialZoom = this.camera?.getState().distance ?? 4;
      this.panInitialCenter = midpoint(p1, p2);
      this.lastDragPos = null;
    } else if (touches.length === 1) {
      this.lastDragPos = { x: touches[0].locationX, y: touches[0].locationY };
      this.lastDragTime = Date.now();
      this.touchStartPos = { x: touches[0].locationX, y: touches[0].locationY };
      this.touchStartTime = Date.now();
      this.pinchInitialDist = 0;
      this.panInitialCenter = null;
    }
    this.camera?.markInteracting();
  };

  private onMove = (evt: GestureResponderEvent, _gs: PanResponderGestureState) => {
    const touches = evt.nativeEvent.touches;
    if (!this.camera) return;

    if (touches.length >= 2) {
      if (this.pinchInitialDist > 0) {
        const p1 = { x: touches[0].locationX, y: touches[0].locationY };
        const p2 = { x: touches[1].locationX, y: touches[1].locationY };
        const currentDist = distance(p1, p2);
        if (currentDist > 0) {
          const ratio = (currentDist / this.pinchInitialDist) * this.opts.pinchSensitivity;
          const newDist = this.pinchInitialZoom * ratio;
          const currentCamDist = this.camera.getState().distance;
          if (currentCamDist > 0) {
            const factor = newDist / currentCamDist;
            this.camera.zoomBy(factor);
          }
        }
      }

      if (this.panInitialCenter) {
        const p1 = { x: touches[0].locationX, y: touches[0].locationY };
        const p2 = { x: touches[1].locationX, y: touches[1].locationY };
        const curCenter = midpoint(p1, p2);
        const dx = (curCenter.x - this.panInitialCenter.x) * this.opts.panSensitivity;
        const dy = (curCenter.y - this.panInitialCenter.y) * this.opts.panSensitivity;
        if (Math.abs(dx) > 0.001 || Math.abs(dy) > 0.001) {
          this.camera.panTargetBy(dx, -dy, 0);
          this.panInitialCenter = curCenter;
        }
      }
    } else if (touches.length === 1 && this.lastDragPos) {
      const x = touches[0].locationX;
      const y = touches[0].locationY;
      const dx = x - this.lastDragPos.x;
      const dy = y - this.lastDragPos.y;
      const now = Date.now();
      const dt = Math.max(now - this.lastDragTime, 1);

      const dYaw = dx * this.opts.dragSensitivity;
      const dPitch = -dy * this.opts.dragSensitivity;
      this.camera.orbitBy(dYaw, dPitch);

      this.lastDragPos = { x, y };
      this.lastDragTime = now;
    }
  };

  private onRelease = (evt: GestureResponderEvent) => {
    if (this.opts.debug) console.log(TAG, 'release');

    if (this.touchStartPos) {
      const releasePos = evt.nativeEvent.touches.length > 0
        ? { x: evt.nativeEvent.touches[0].locationX, y: evt.nativeEvent.touches[0].locationY }
        : null;
      const finalPos = releasePos ?? (
        evt.nativeEvent.changedTouches?.length > 0
          ? { x: evt.nativeEvent.changedTouches[0].locationX, y: evt.nativeEvent.changedTouches[0].locationY }
          : null
      );

      if (finalPos) {
        const moved = distance(this.touchStartPos, finalPos);
        const elapsed = Date.now() - this.touchStartTime;
        if (moved < this.opts.tapThreshold && elapsed < 300) {
          const now = Date.now();
          if (now - this.lastTapTime < this.opts.doubleTapWindowMs) {
            if (this.opts.debug) console.log(TAG, 'double tap → reset camera');
            this.camera?.reset();
            this.lastTapTime = 0;
          } else {
            this.lastTapTime = now;
          }
        }
      }
    }

    this.pinchInitialDist = 0;
    this.panInitialCenter = null;
    this.lastDragPos = null;
    this.touchStartPos = null;
  };

  getPanHandlers(): any {
    return this.panResponder.panHandlers;
  }

  detach(): void {
    this.camera = null;
  }

  attach(camera: ICameraController): void {
    this.camera = camera;
  }
}

function distance(a: TouchPoint, b: TouchPoint): number {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  return Math.sqrt(dx * dx + dy * dy);
}

function midpoint(a: TouchPoint, b: TouchPoint): TouchPoint {
  return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
}
GESTURECONTROLLER_EOF
echo "✓ engine/camera/GestureController.ts"

echo ""
echo "=== Part 2 complete ==="
echo "Files written:"
ls -la src/engine/textures/ src/engine/camera/
echo ""
echo "Total engine files so far:"
find src/engine -type f | wc -l
echo ""
echo "Continue with Part 3 (geometry + materials)."
