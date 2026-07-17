#!/bin/bash
set -e
cd /Users/yashas/VTO/apps/mobile

echo "=== Part 5: AssetManager + Engine + EngineViewer + index ==="

cat > src/engine/assets/AssetManager.ts << 'ASSETMANAGER_EOF'
/**
 * engine/assets/AssetManager.ts
 *
 * The single entry point for loading 3D assets.
 * Pipeline: Download → Validate → Repair → Optimize → Cache → Parse → Return
 */

import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader';
import * as FileSystem from 'expo-file-system/legacy';

import type {
  AssetDescriptor, LoadedAsset, AssetStats, BoundingBox, SkeletonData,
  LoadProgress, LoadPhase, LODLevel,
} from '../core/types';
import { CacheManager, type ICacheManager } from './CacheManager';
import { AssetValidator, type IAssetValidator } from './AssetValidator';
import { TextureLoader, type ITextureLoader } from '../textures/TextureLoader';

const TAG = '[AssetManager]';

const PHASES: LoadPhase[] = [
  'queued', 'downloading', 'validating', 'parsing', 'optimizing', 'caching', 'ready',
];

export interface AssetManagerOptions {
  cache?: ICacheManager;
  validator?: IAssetValidator;
  textureLoader?: ITextureLoader;
  tempDir?: string;
}

export interface IAssetManager {
  load(descriptor: AssetDescriptor, opts?: LoadOptions): Promise<LoadedAsset>;
  onProgress(listener: (p: LoadProgress) => void): () => void;
  getActiveLoads(): LoadProgress[];
  release(loaded: LoadedAsset): void;
}

export interface LoadOptions {
  lod?: LODLevel;
  allowDownload?: boolean;
  tempDir?: string;
}

export class AssetManager implements IAssetManager {
  private readonly cache: ICacheManager;
  private readonly validator: IAssetValidator;
  private readonly textureLoader: ITextureLoader;
  private readonly tempDir: string;
  private readonly gltfLoader: GLTFLoader;
  private progressListeners = new Set<(p: LoadProgress) => void>();
  private activeLoads = new Map<string, LoadProgress>();
  private loadedAssets = new Map<string, LoadedAsset>();

  constructor(opts: AssetManagerOptions = {}) {
    this.cache = opts.cache ?? new CacheManager();
    this.validator = opts.validator ?? new AssetValidator();
    this.textureLoader = opts.textureLoader ?? new TextureLoader();
    this.tempDir = opts.tempDir ?? `${FileSystem.cacheDirectory}engine_textures/`;
    this.gltfLoader = new GLTFLoader();
  }

  async load(descriptor: AssetDescriptor, opts: LoadOptions = {}): Promise<LoadedAsset> {
    const allowDownload = opts.allowDownload ?? true;
    const tempDir = opts.tempDir ?? this.tempDir;
    const startedAt = Date.now();

    const emit = (phase: LoadPhase, phaseProgress: number, extra?: Partial<LoadProgress>) => {
      const phaseIndex = PHASES.indexOf(phase);
      const overallProgress = phaseIndex / (PHASES.length - 1);
      const p: LoadProgress = {
        descriptor, phase, phaseProgress, overallProgress,
        startedAt, elapsedMs: Date.now() - startedAt, ...extra,
      };
      this.activeLoads.set(descriptor.id, p);
      for (const l of this.progressListeners) {
        try { l(p); } catch (e) { console.warn(TAG, 'progress listener threw:', e); }
      }
    };

    emit('queued', 0);

    const cached = await this.cache.get(descriptor);
    let localPath: string;
    if (cached) {
      localPath = cached.localPath;
      console.log(TAG, `cache hit: ${descriptor.id} v${descriptor.version}`);
    } else {
      if (!allowDownload) {
        throw new Error(`Asset ${descriptor.id} not in cache and allowDownload=false`);
      }
      emit('downloading', 0);
      const downloadPath = `${FileSystem.cacheDirectory}${descriptor.id}_download.glb`;
      const downloadResult = await FileSystem.downloadAsync(descriptor.url, downloadPath);
      if (downloadResult.status < 200 || downloadResult.status >= 300) {
        throw new Error(`Download failed: HTTP ${downloadResult.status}`);
      }
      localPath = downloadResult.uri;
      emit('downloading', 1);
    }

    const fileBase64 = await FileSystem.readAsStringAsync(localPath, { encoding: 'base64' });
    const glbBuffer = this.base64ToArrayBuffer(fileBase64);

    emit('validating', 0.5);
    const validation = this.validator.validate(glbBuffer);
    if (!validation.valid) {
      throw new Error(`Asset validation failed for ${descriptor.id}:\n  ${validation.errors.join('\n  ')}`);
    }
    if (validation.warnings.length > 0) {
      console.warn(TAG, `validation warnings for ${descriptor.id}:\n  ${validation.warnings.join('\n  ')}`);
    }
    emit('validating', 1);

    emit('parsing', 0.2);
    const extracted = await this.textureLoader.extractFromGLB(glbBuffer, `${tempDir}${descriptor.id}/`);

    emit('parsing', 0.5);
    const gltf = await new Promise<any>((resolve, reject) => {
      const patchedGlb = this.rebuildGLB(extracted.patchedJson, glbBuffer);
      this.gltfLoader.parse(
        patchedGlb, '',
        resolve,
        (err) => reject(new Error(`GLTFLoader.parse failed: ${err?.message || err}`))
      );
    });
    emit('parsing', 1);

    emit('optimizing', 0.5);
    const model = gltf.scene as THREE.Group;
    const bbox = this.computeBoundingBox(model);
    const maxDim = Math.max(bbox.size.x, bbox.size.y, bbox.size.z);
    if (isFinite(maxDim) && maxDim > 1e-6) {
      const scale = 2 / maxDim;
      model.scale.setScalar(scale);
      model.position.x = -bbox.center.x * scale;
      model.position.y = -bbox.center.y * scale + 0.5;
      model.position.z = -bbox.center.z * scale;
    }
    emit('optimizing', 1);

    emit('caching', 0.5);
    if (!cached) await this.cache.put(descriptor, localPath);
    emit('caching', 1);

    const stats = this.extractStats(model, validation.stats);
    const skeleton = this.extractSkeleton(gltf);
    const loaded: LoadedAsset = {
      descriptor, scene: model, bbox, stats, skeleton,
      activeLOD: opts.lod ?? 'high', localPath,
      loadTimeMs: Date.now() - startedAt,
    };

    this.loadedAssets.set(descriptor.id, loaded);
    emit('ready', 1);
    this.activeLoads.delete(descriptor.id);

    console.log(TAG, `loaded ${descriptor.id} v${descriptor.version} — meshes=${stats.meshCount} tris=${stats.triangleCount} textures=${stats.textureCount} mem=${(stats.estimatedMemoryBytes / 1024 / 1024).toFixed(2)}MB time=${loaded.loadTimeMs}ms`);

    return loaded;
  }

  onProgress(listener: (p: LoadProgress) => void): () => void {
    this.progressListeners.add(listener);
    return () => this.progressListeners.delete(listener);
  }

  getActiveLoads(): LoadProgress[] {
    return Array.from(this.activeLoads.values());
  }

  release(loaded: LoadedAsset): void {
    loaded.scene.traverse((obj: any) => {
      if (obj.isMesh) {
        obj.geometry?.dispose?.();
        if (Array.isArray(obj.material)) obj.material.forEach((m: any) => m.dispose?.());
        else obj.material?.dispose?.();
      }
    });
    this.loadedAssets.delete(loaded.descriptor.id);
    console.log(TAG, `released ${loaded.descriptor.id}`);
  }

  private rebuildGLB(patchedJson: any, originalBuffer: ArrayBuffer): ArrayBuffer {
    if (!patchedJson) return originalBuffer;
    const jsonBytes = new TextEncoder().encode(JSON.stringify(patchedJson));
    const jsonPaddedLen = Math.ceil(jsonBytes.length / 4) * 4;
    const jsonPadded = new Uint8Array(jsonPaddedLen);
    jsonPadded.set(jsonBytes);

    const origBytes = new Uint8Array(originalBuffer);
    const dv = new DataView(originalBuffer);
    let offset = 12;
    let binOffset = 0;
    let binLength = 0;
    while (offset + 8 <= origBytes.length) {
      const chunkLength = dv.getUint32(offset, true);
      const chunkType = dv.getUint32(offset + 4, true);
      if (chunkType === 0x004e4942) {
        binOffset = offset + 8;
        binLength = chunkLength;
      }
      offset = offset + 8 + chunkLength;
    }

    const binPaddedLen = Math.ceil(binLength / 4) * 4;
    const totalLength = 12 + 8 + jsonPaddedLen + (binLength > 0 ? 8 + binPaddedLen : 0);
    const out = new ArrayBuffer(totalLength);
    const outBytes = new Uint8Array(out);
    const outDv = new DataView(out);

    outDv.setUint32(0, 0x46546c67, true);
    outDv.setUint32(4, 2, true);
    outDv.setUint32(8, totalLength, true);

    let w = 12;
    outDv.setUint32(w, jsonPaddedLen, true);
    outDv.setUint32(w + 4, 0x4e4f534a, true);
    outBytes.set(jsonPadded, w + 8);
    w += 8 + jsonPaddedLen;

    if (binLength > 0) {
      outDv.setUint32(w, binPaddedLen, true);
      outDv.setUint32(w + 4, 0x004e4942, true);
      outBytes.set(origBytes.subarray(binOffset, binOffset + binLength), w + 8);
      w += 8 + binLength;
      while (w < totalLength) { outBytes[w] = 0; w++; }
    }
    return out;
  }

  private computeBoundingBox(model: THREE.Group): BoundingBox {
    const box = new THREE.Box3().setFromObject(model);
    const size = box.getSize(new THREE.Vector3());
    const center = box.getCenter(new THREE.Vector3());
    return {
      min: { x: box.min.x, y: box.min.y, z: box.min.z },
      max: { x: box.max.x, y: box.max.y, z: box.max.z },
      center: { x: center.x, y: center.y, z: center.z },
      size: { x: size.x, y: size.y, z: size.z },
    };
  }

  private extractStats(model: THREE.Group, validationStats: any): AssetStats {
    let meshCount = 0;
    let triangleCount = 0;
    let vertexCount = 0;
    const materials = new Set<any>();

    model.traverse((obj: any) => {
      if (obj.isMesh) {
        meshCount++;
        const geom = obj.geometry;
        if (geom?.index) triangleCount += geom.index.count / 3;
        else if (geom?.attributes?.position) triangleCount += geom.attributes.position.count / 3;
        if (geom?.attributes?.position) vertexCount += geom.attributes.position.count;
        if (Array.isArray(obj.material)) obj.material.forEach((m: any) => materials.add(m));
        else if (obj.material) materials.add(obj.material);
      }
    });

    const geometryBytes = vertexCount * 32;
    const textureBytes = validationStats.binChunkBytes * 0.5;
    return {
      meshCount,
      triangleCount: Math.round(triangleCount),
      vertexCount,
      materialCount: materials.size,
      textureCount: validationStats.textureCount ?? 0,
      estimatedMemoryBytes: geometryBytes + textureBytes,
    };
  }

  private extractSkeleton(gltf: any): SkeletonData | null {
    if (!gltf.skins?.length) return null;
    const skin = gltf.skins[0];
    if (!skin.skeleton || !skin.joints?.length) return null;

    const skeleton = skin.skeleton as THREE.Skeleton;
    const boneHierarchy: Record<string, string[]> = {};
    const bindPose: Record<string, number[]> = {};
    const boneLengths: Record<string, number> = {};

    for (const bone of skeleton.bones) {
      const path: string[] = [];
      let cur: THREE.Bone | null = bone;
      while (cur) {
        path.unshift(cur.name);
        cur = cur.parent as THREE.Bone | null;
      }
      boneHierarchy[bone.name] = path;
      bindPose[bone.name] = bone.matrixWorld.elements.slice();
      const childBone = bone.children.find((c) => (c as any).isBone) as THREE.Bone | undefined;
      boneLengths[bone.name] = childBone ? bone.position.distanceTo(childBone.position) : 0;
    }

    return { skeleton, boneHierarchy, bindPose, boneLengths };
  }

  private base64ToArrayBuffer(base64: string): ArrayBuffer {
    try {
      // @ts-ignore
      if (typeof Buffer !== 'undefined') {
        // @ts-ignore
        const buf = Buffer.from(base64, 'base64');
        return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
      }
    } catch { /* fall through */ }
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes.buffer;
  }
}
ASSETMANAGER_EOF
echo "✓ engine/assets/AssetManager.ts"

cat > src/engine/core/Engine.ts << 'ENGINE_EOF'
/**
 * engine/core/Engine.ts
 *
 * The orchestrator. Owns and coordinates all engine subsystems.
 */

import * as THREE from 'three';
import { Renderer } from 'expo-three';
import { PixelRatio } from 'react-native';

import type { AssetDescriptor, LoadedAsset, BodyMeasurements } from './types';
import { AssetManager, type IAssetManager } from '../assets/AssetManager';
import { CacheManager, type ICacheManager } from '../assets/CacheManager';
import { AssetValidator, type IAssetValidator } from '../assets/AssetValidator';
import { TextureLoader, type ITextureLoader } from '../textures/TextureLoader';
import { TextureManager, type ITextureManager } from '../textures/TextureManager';
import { MaterialSystem, type IMaterialSystem } from '../materials/MaterialSystem';
import { LODSystem, type ILODSystem } from '../geometry/LODSystem';
import { MeshOptimizer } from '../geometry/MeshOptimizer';
import { CameraController, type ICameraController } from '../camera/CameraController';
import { GestureController, type IGestureController } from '../camera/GestureController';
import { CameraConstraints, DEFAULT_VTO_CONSTRAINTS } from '../camera/CameraConstraints';
import { AnimationController, type IAnimationController } from '../animation/AnimationController';
import { SkeletonRetargeter } from '../animation/SkeletonRetargeter';
import { SkeletonDetector } from '../skeleton/SkeletonDetector';
import { BodyProportions } from '../skeleton/BodyProportions';
import { GarmentFitter, type IGarmentFitter, type FitOptions, DEFAULT_FIT_OPTS } from '../skeleton/GarmentFitter';
import { AssetStreamer, type IAssetStreamer } from '../streaming/AssetStreamer';
import { PerformanceProfiler, type IPerformanceProfiler } from '../debug/PerformanceProfiler';

const TAG = '[Engine]';

export interface EngineOptions {
  cache?: ICacheManager;
  validator?: IAssetValidator;
  textureLoader?: ITextureLoader;
  textureManager?: ITextureManager;
  materialSystem?: IMaterialSystem;
  lodSystem?: ILODSystem;
  cameraController?: ICameraController;
  gestureController?: IGestureController;
  animationController?: IAnimationController;
  garmentFitter?: IGarmentFitter;
  assetStreamer?: IAssetStreamer;
  profiler?: IPerformanceProfiler;
  cameraConstraints?: CameraConstraints;
  showFallbackGrid?: boolean;
  backgroundColor?: number;
}

export interface LoadBodyResult {
  asset: LoadedAsset;
  measurements: BodyMeasurements | null;
}

export class Engine {
  readonly cache: ICacheManager;
  readonly validator: IAssetValidator;
  readonly textures: ITextureManager;
  readonly textureLoader: ITextureLoader;
  readonly materials: IMaterialSystem;
  readonly lod: ILODSystem;
  readonly meshOptimizer: MeshOptimizer;
  readonly camera: ICameraController;
  readonly gestures: IGestureController;
  readonly animation: IAnimationController;
  readonly retargeter: SkeletonRetargeter;
  readonly skeletonDetector: SkeletonDetector;
  readonly bodyProportions: BodyProportions;
  readonly garmentFitter: IGarmentFitter;
  readonly streamer: IAssetStreamer;
  readonly profiler: IPerformanceProfiler;
  readonly assets: IAssetManager;

  private gl: WebGLRenderingContext | null = null;
  private renderer: Renderer | null = null;
  private scene: THREE.Scene | null = null;
  private threeCamera: THREE.PerspectiveCamera | null = null;

  private body: LoadedAsset | null = null;
  private bodyMeasurements: BodyMeasurements | null = null;
  private garments = new Map<string, LoadedAsset>();

  private animationFrameRef: number | null = null;
  private lastFrameTime = 0;
  private running = false;

  private readonly showFallbackGrid: boolean;
  private readonly backgroundColor: number;

  constructor(opts: EngineOptions = {}) {
    this.cache = opts.cache ?? new CacheManager();
    this.validator = opts.validator ?? new AssetValidator();
    this.textureLoader = opts.textureLoader ?? new TextureLoader();
    this.textures = opts.textureManager ?? new TextureManager();
    this.materials = opts.materialSystem ?? new MaterialSystem({ textureManager: this.textures });
    this.lod = opts.lodSystem ?? new LODSystem();
    this.meshOptimizer = new MeshOptimizer();
    this.camera = opts.cameraController ?? new CameraController({
      constraints: opts.cameraConstraints ?? DEFAULT_VTO_CONSTRAINTS,
    });
    this.gestures = opts.gestureController ?? new GestureController(this.camera);
    this.animation = opts.animationController ?? new AnimationController({ target: new THREE.Object3D() });
    this.retargeter = new SkeletonRetargeter();
    this.skeletonDetector = new SkeletonDetector();
    this.bodyProportions = new BodyProportions();
    this.garmentFitter = opts.garmentFitter ?? new GarmentFitter(this.retargeter);
    this.profiler = opts.profiler ?? new PerformanceProfiler();
    this.assets = new AssetManager({
      cache: this.cache, validator: this.validator, textureLoader: this.textureLoader,
    });
    this.streamer = opts.assetStreamer ?? new AssetStreamer(this.assets, this.lod);

    this.showFallbackGrid = opts.showFallbackGrid ?? true;
    this.backgroundColor = opts.backgroundColor ?? 0x1a1a1a;
    console.log(TAG, 'engine initialized');
  }

  attachGL(gl: WebGLRenderingContext): void {
    if (this.gl) {
      console.warn(TAG, 'attachGL called twice — ignoring');
      return;
    }
    this.gl = gl;
    const { drawingBufferWidth: rawW, drawingBufferHeight: rawH } = gl;
    const width = Math.max(rawW || 1, 1);
    const height = Math.max(rawH || 1, 1);
    console.log(TAG, `GL attached: ${width}x${height}`);

    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(this.backgroundColor);

    if (this.showFallbackGrid) {
      const grid = new THREE.GridHelper(4, 8, 0x444466, 0x222233);
      (grid.material as THREE.Material).transparent = true;
      (grid.material as THREE.Material).opacity = 0.35;
      grid.position.y = -1;
      this.scene.add(grid);
      const axes = new THREE.AxesHelper(1.5);
      this.scene.add(axes);
    }

    this.threeCamera = new THREE.PerspectiveCamera(50, width / height, 0.1, 1000);
    this.threeCamera.position.set(0, 1, 4);
    this.threeCamera.lookAt(0, 0.5, 0);

    this.renderer = new Renderer({ gl });
    this.renderer.setSize(width, height);
    try { this.renderer.setPixelRatio(PixelRatio.get()); }
    catch (e) { console.warn(TAG, 'PixelRatio.get() failed:', e); this.renderer.setPixelRatio(1); }

    this.scene.add(new THREE.AmbientLight(0xffffff, 0.6));
    const dir1 = new THREE.DirectionalLight(0xffffff, 1.2);
    dir1.position.set(2, 4, 3);
    this.scene.add(dir1);
    const dir2 = new THREE.DirectionalLight(0xffffff, 0.4);
    dir2.position.set(-2, 2, -1);
    this.scene.add(dir2);
  }

  start(): void {
    if (this.running) return;
    if (!this.gl || !this.renderer || !this.scene || !this.threeCamera) {
      throw new Error('Engine.start: call attachGL first');
    }
    this.running = true;
    this.lastFrameTime = performance.now();
    this.loop();
    console.log(TAG, 'engine started');
  }

  stop(): void {
    this.running = false;
    if (this.animationFrameRef !== null) {
      cancelAnimationFrame(this.animationFrameRef);
      this.animationFrameRef = null;
    }
    console.log(TAG, 'engine stopped');
  }

  dispose(): void {
    this.stop();
    if (this.body) {
      this.scene?.remove(this.body.scene);
      this.assets.release(this.body);
      this.body = null;
    }
    for (const garment of this.garments.values()) this.assets.release(garment);
    this.garments.clear();
    this.materials.disposeAll();
    this.animation.dispose();
    this.lod.getGroups().forEach((g) => this.lod.unregister(g.id));
    console.log(TAG, 'engine disposed');
  }

  isReady(): boolean {
    return this.gl !== null && this.scene !== null;
  }

  async loadBody(descriptor: AssetDescriptor): Promise<LoadBodyResult> {
    if (!this.scene) throw new Error('Engine.loadBody: call attachGL first');
    if (this.body) {
      this.scene.remove(this.body.scene);
      this.assets.release(this.body);
      this.body = null;
      this.bodyMeasurements = null;
    }

    const asset = await this.assets.load(descriptor, { lod: 'high' });
    this.body = asset;
    this.scene.add(asset.scene);
    this.animation.setTarget(asset.scene);

    const skeleton = this.skeletonDetector.detect(asset.scene);
    if (skeleton) {
      asset.skeleton = skeleton;
      this.bodyMeasurements = this.bodyProportions.measure(skeleton, asset.scene);
    }

    for (const garment of this.garments.values()) {
      this.fitGarment(garment.descriptor);
    }

    console.log(TAG, `body loaded: ${descriptor.id}`);
    return { asset, measurements: this.bodyMeasurements };
  }

  async loadGarment(descriptor: AssetDescriptor, fitOpts: FitOptions = DEFAULT_FIT_OPTS): Promise<LoadedAsset> {
    if (!this.scene) throw new Error('Engine.loadGarment: call attachGL first');
    if (!this.body) throw new Error('Engine.loadGarment: load a body first');

    const existing = this.garments.get(descriptor.id);
    if (existing) {
      this.scene.remove(existing.scene);
      this.assets.release(existing);
      this.garments.delete(descriptor.id);
    }

    const asset = await this.assets.load(descriptor, { lod: 'high' });
    this.garments.set(descriptor.id, asset);
    this.scene.add(asset.scene);

    this.garmentFitter.fit(asset, this.body, this.bodyMeasurements ?? this.fallbackMeasurements(), fitOpts);

    console.log(TAG, `garment loaded: ${descriptor.id}`);
    return asset;
  }

  fitGarment(descriptor: AssetDescriptor, opts: FitOptions = DEFAULT_FIT_OPTS): void {
    const garment = this.garments.get(descriptor.id);
    if (!garment || !this.body) return;
    this.garmentFitter.fit(garment, this.body, this.bodyMeasurements ?? this.fallbackMeasurements(), opts);
  }

  removeGarment(id: string): void {
    const garment = this.garments.get(id);
    if (!garment) return;
    this.scene?.remove(garment.scene);
    this.assets.release(garment);
    this.garments.delete(id);
  }

  clearGarments(): void {
    for (const id of Array.from(this.garments.keys())) this.removeGarment(id);
  }

  getTHREECamera(): THREE.PerspectiveCamera | null { return this.threeCamera; }
  getTHREEScene(): THREE.Scene | null { return this.scene; }
  resetCamera(): void { this.camera.reset(); }

  private loop = (): void => {
    if (!this.running) return;
    this.animationFrameRef = requestAnimationFrame(this.loop);
    const now = performance.now();
    const dtSec = Math.min((now - this.lastFrameTime) / 1000, 0.1);
    this.lastFrameTime = now;
    if (!this.gl || !this.renderer || !this.scene || !this.threeCamera) return;

    this.profiler.beginFrame();
    this.animation.update(dtSec);
    const animationMs = this.animation.getLastUpdateMs();
    const cameraPos = this.threeCamera.position;
    this.lod.update(cameraPos, dtSec);
    this.camera.update(dtSec);
    this.camera.apply(this.threeCamera);
    this.profiler.beginRender();
    this.renderer.render(this.scene, this.threeCamera);
    // @ts-ignore
    this.gl.endFrameEXP();
    const gpuBytes = this.body?.stats.estimatedMemoryBytes ?? 0;
    for (const g of this.garments.values()) gpuBytes += g.stats.estimatedMemoryBytes;
    this.profiler.endFrame(this.renderer as any, { animationTimeMs: animationMs, gpuMemoryBytes: gpuBytes });
  };

  private fallbackMeasurements(): BodyMeasurements {
    return {
      height: 1.7, shoulderWidth: 0.4, hipWidth: 0.35,
      chestCircumference: 0.9, waistCircumference: 0.8,
      armLength: 0.6, legLength: 0.8, torsoLength: 0.5, headCircumference: 0.55,
    };
  }
}
ENGINE_EOF
echo "✓ engine/core/Engine.ts"

cat > src/engine/viewer/EngineViewer.tsx << 'ENGINEVIEWER_EOF'
/**
 * engine/viewer/EngineViewer.tsx
 *
 * React Native wrapper around the Engine.
 */

import React, { useState, useEffect, useRef, useCallback } from 'react';
import { View, StyleSheet, ActivityIndicator, Text } from 'react-native';
import { GLView } from 'expo-gl';

import { Engine, type EngineOptions } from '../core/Engine';
import { DebugOverlay } from '../debug/DebugOverlay';
import type { AssetDescriptor } from '../core/types';

const TAG = '[EngineViewer]';

export interface EngineViewerProps {
  bodyModelUri: string | null;
  bodyModelVersion?: string | number;
  garmentUri?: string | null;
  garmentVersion?: string | number;
  debug?: boolean;
  engineOptions?: EngineOptions;
  onBodyReady?: () => void;
  onGarmentReady?: () => void;
  onError?: (err: Error) => void;
}

export function EngineViewer(props: EngineViewerProps) {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [statusText, setStatusText] = useState('Initializing engine...');

  const engineRef = useRef<Engine | null>(null);
  const bodyLoadedRef = useRef(false);

  const onContextCreate = useCallback(async (gl: WebGLRenderingContext) => {
    console.log(TAG, 'onContextCreate fired');
    try {
      if (!engineRef.current) {
        engineRef.current = new Engine(props.engineOptions);
        console.log(TAG, 'engine created');
      }
      const engine = engineRef.current;
      engine.attachGL(gl);
      engine.start();
      setStatusText('Engine ready');

      if (props.bodyModelUri) {
        await loadBody(engine, props.bodyModelUri, props.bodyModelVersion ?? 1);
        bodyLoadedRef.current = true;
        setStatusText('Ready');
        setLoading(false);
        props.onBodyReady?.();
      } else {
        setLoading(false);
      }
    } catch (err: any) {
      console.error(TAG, 'setup error:', err);
      setError(err?.message || String(err));
      setStatusText(`Error: ${err?.message || err}`);
      setLoading(false);
      props.onError?.(err);
    }
  }, [props.bodyModelUri, props.bodyModelVersion, props.engineOptions]);

  useEffect(() => {
    if (!engineRef.current || !engineRef.current.isReady()) return;
    if (!props.bodyModelUri) return;
    if (bodyLoadedRef.current) return;

    const engine = engineRef.current;
    setLoading(true);
    setStatusText('Loading body...');
    loadBody(engine, props.bodyModelUri, props.bodyModelVersion ?? 1)
      .then(() => {
        bodyLoadedRef.current = true;
        setStatusText('Ready');
        setLoading(false);
        props.onBodyReady?.();
      })
      .catch((err) => {
        console.error(TAG, 'body load failed:', err);
        setError(err?.message || String(err));
        setStatusText(`Error: ${err?.message || err}`);
        setLoading(false);
        props.onError?.(err);
      });
  }, [props.bodyModelUri, props.bodyModelVersion]);

  useEffect(() => {
    const engine = engineRef.current;
    if (!engine || !bodyLoadedRef.current) return;

    if (props.garmentUri) {
      setLoading(true);
      setStatusText('Loading garment...');
      const desc: AssetDescriptor = {
        id: 'current_garment',
        version: props.garmentVersion ?? 1,
        url: props.garmentUri,
        kind: 'garment',
      };
      engine.loadGarment(desc)
        .then(() => {
          setStatusText('Ready');
          setLoading(false);
          props.onGarmentReady?.();
        })
        .catch((err: any) => {
          console.error(TAG, 'garment load failed:', err);
          setStatusText(`Garment error: ${err?.message || err}`);
          setLoading(false);
        });
    } else {
      engine.clearGarments();
      setStatusText('Ready');
    }
  }, [props.garmentUri, props.garmentVersion]);

  useEffect(() => {
    return () => {
      if (engineRef.current) {
        engineRef.current.dispose();
        engineRef.current = null;
      }
    };
  }, []);

  if (!props.bodyModelUri) {
    return (
      <View style={styles.placeholder}>
        <Text style={styles.placeholderText}>No 3D model loaded</Text>
      </View>
    );
  }

  const engine = engineRef.current;

  return (
    <View style={styles.container}>
      <GLView
        style={styles.glView}
        onContextCreate={onContextCreate}
        {...(engine ? engine.gestures.getPanHandlers() : {})}
      />
      <View style={styles.statusChip}>
        <Text style={styles.statusText}>{statusText}</Text>
      </View>
      <View style={styles.hintChip} pointerEvents="none">
        <Text style={styles.hintText}>Drag to rotate | Pinch to zoom | Double-tap to reset</Text>
      </View>
      {loading && (
        <View style={styles.loadingOverlay} pointerEvents="none">
          <ActivityIndicator size="large" color="#6C63FF" />
          <Text style={styles.loadingText}>Loading 3D Model...</Text>
        </View>
      )}
      {error && (
        <View style={styles.errorOverlay}>
          <Text style={styles.errorTitle}>3D Load Failed</Text>
          <Text style={styles.errorText}>{error}</Text>
        </View>
      )}
      {props.debug && engine && engine.profiler && (
        <DebugOverlay
          profiler={engine.profiler}
          assetManager={engine.assets}
          lodSystem={engine.lod}
          materialSystem={engine.materials}
          cameraController={engine.camera}
        />
      )}
    </View>
  );
}

async function loadBody(engine: Engine, uri: string, version: string | number): Promise<void> {
  const desc: AssetDescriptor = { id: 'body_default', version, url: uri, kind: 'body' };
  await engine.loadBody(desc);
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#1a1a1a', borderRadius: 16, overflow: 'hidden' },
  glView: { flex: 1, width: '100%' },
  statusChip: { position: 'absolute', top: 8, left: 8, backgroundColor: 'rgba(0,0,0,0.6)', paddingHorizontal: 8, paddingVertical: 4, borderRadius: 8, zIndex: 5 },
  statusText: { color: '#AAA', fontSize: 10, fontWeight: '500' },
  hintChip: { position: 'absolute', bottom: 12, left: 0, right: 0, alignItems: 'center', zIndex: 5 },
  hintText: { color: 'rgba(170, 170, 170, 0.7)', fontSize: 10, fontWeight: '500', backgroundColor: 'rgba(0,0,0,0.4)', paddingHorizontal: 10, paddingVertical: 4, borderRadius: 10, overflow: 'hidden' },
  loadingOverlay: { ...StyleSheet.absoluteFillObject, justifyContent: 'center', alignItems: 'center', backgroundColor: 'rgba(0,0,0,0.3)', zIndex: 10 },
  loadingText: { color: '#FFF', marginTop: 10, fontSize: 14 },
  errorOverlay: { ...StyleSheet.absoluteFillObject, justifyContent: 'center', alignItems: 'center', backgroundColor: 'rgba(0,0,0,0.85)', padding: 24, zIndex: 20 },
  errorTitle: { color: '#FF6B6B', fontSize: 16, fontWeight: '700', marginBottom: 8 },
  errorText: { color: '#FFF', fontSize: 12, textAlign: 'center', lineHeight: 18 },
  placeholder: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#1a1a1a', borderRadius: 16 },
  placeholderText: { color: '#666', fontSize: 14 },
});
ENGINEVIEWER_EOF
echo "✓ engine/viewer/EngineViewer.tsx"

cat > src/engine/index.ts << 'INDEX_EOF'
/**
 * engine/index.ts
 *
 * Public API of the rendering engine.
 */

export * from './core/types';
export { AssetManager, type IAssetManager, type LoadOptions } from './assets/AssetManager';
export { CacheManager, type ICacheManager, type CacheManagerOptions } from './assets/CacheManager';
export { AssetValidator, type IAssetValidator, type ValidationResult } from './assets/AssetValidator';
export { TextureLoader, type ITextureLoader, type ExtractedTextures } from './textures/TextureLoader';
export { TextureManager, type ITextureManager, type TextureManagerOptions } from './textures/TextureManager';
export {
  CameraController, type ICameraController, type CameraState, type CameraControllerOptions,
} from './camera/CameraController';
export { GestureController, type IGestureController, type GestureControllerOptions } from './camera/GestureController';
export {
  CameraConstraints, DEFAULT_VTO_CONSTRAINTS, AVATAR_CUSTOMIZER_CONSTRAINTS,
  WALKTHROUGH_CONSTRAINTS, clamp, lerp, damp,
} from './camera/CameraConstraints';
export {
  LODSystem, type ILODSystem, type LODGroup, type LODVariant, type LODStats,
} from './geometry/LODSystem';
export {
  MeshOptimizer, type OptimizationOptions, type OptimizationResult, DEFAULT_OPTS as DEFAULT_MESH_OPTS,
} from './geometry/MeshOptimizer';
export { BoundingBoxUtils } from './geometry/BoundingBox';
export {
  MaterialSystem, type IMaterialSystem, type MaterialSystemOptions, type TextureSlot as MaterialTextureSlot,
} from './materials/MaterialSystem';
export { MaterialCache, type IMaterialCache, type MaterialCacheStats } from './materials/MaterialCache';
export { MaterialFactory, FABRIC_PRESETS, type MaterialPreset, type TextureSlot } from './materials/MaterialFactory';
export {
  AnimationController, type IAnimationController, type ActiveClip, type PlayOptions, type PlayMode, type AnimationControllerOptions,
} from './animation/AnimationController';
export {
  SkeletonRetargeter, type ISkeletonRetargeter, type BoneMapping, type RetargetOptions, DEFAULT_RETARGET_OPTS,
} from './animation/SkeletonRetargeter';
export { SkeletonDetector, type ISkeletonDetector } from './skeleton/SkeletonDetector';
export { BodyProportions, type IBodyProportions, type BodyMeasurements } from './skeleton/BodyProportions';
export {
  GarmentFitter, type IGarmentFitter, type FitOptions, type FitResult, type FitLevel, DEFAULT_FIT_OPTS,
} from './skeleton/GarmentFitter';
export {
  PerformanceProfiler, type IPerformanceProfiler, type RollingStats,
} from './debug/PerformanceProfiler';
export { DebugOverlay, type DebugOverlayProps } from './debug/DebugOverlay';
export {
  AssetStreamer, type IAssetStreamer, type StreamResult, type StreamOptions, type StreamStatus,
} from './streaming/AssetStreamer';
export { Engine, type EngineOptions, type LoadBodyResult } from './core/Engine';
export { EngineViewer, type EngineViewerProps } from './viewer/EngineViewer';
INDEX_EOF
echo "✓ engine/index.ts"

echo ""
echo "=== Part 6: Test framework ==="

cat > src/engine/__tests__/framework/types.ts << 'FRAMEWORKTYPES_EOF'
/**
 * engine/__tests__/framework/types.ts
 */

export type TestStatus = 'pass' | 'fail' | 'skipped' | 'running' | 'pending';

export interface TestResult {
  id: string;
  name: string;
  subsystem: SubsystemName;
  status: TestStatus;
  durationMs: number;
  timestamp: number;
  assertions: AssertionResult[];
  metrics: BenchmarkMetrics;
  error?: string;
  deviceInfo: DeviceInfo;
  logs?: string[];
}

export interface AssertionResult {
  label: string;
  passed: boolean;
  expected?: string;
  actual?: string;
}

export type SubsystemName =
  | 'TextureLoader' | 'TextureManager' | 'AssetValidator' | 'CacheManager'
  | 'AssetManager' | 'CameraController' | 'GestureController' | 'LODSystem'
  | 'MeshOptimizer' | 'MaterialSystem' | 'AnimationController'
  | 'SkeletonRetargeter' | 'SkeletonDetector' | 'BodyProportions'
  | 'GarmentFitter' | 'AssetStreamer' | 'PerformanceProfiler' | 'Engine';

export interface BenchmarkMetrics {
  fpsAvg?: number; fpsMin?: number; fpsMax?: number;
  frameTimeAvgMs?: number; frameTimeMinMs?: number; frameTimeMaxMs?: number;
  renderTimeMs?: number; animationTimeMs?: number;
  jsHeapUsedMB?: number; jsHeapTotalMB?: number;
  estimatedGpuMemoryMB?: number; textureMemoryMB?: number; geometryMemoryMB?: number;
  drawCalls?: number; triangles?: number; vertices?: number;
  geometries?: number; textures?: number; programs?: number;
  loadTimeMs?: number; downloadTimeMs?: number; parseTimeMs?: number;
  validateTimeMs?: number; cacheHitTimeMs?: number; cacheMissTimeMs?: number;
  cacheHits?: number; cacheMisses?: number;
  cacheSizeBytes?: number; cacheEvictions?: number;
  gestureLatencyMs?: number; gestureDroppedFrames?: number;
  lodSwitches?: number; lodHysteresisCorrect?: boolean;
  streamPreviewReadyMs?: number; streamFullReadyMs?: number;
  animationClipsActive?: number; animationCrossFadeMs?: number;
  custom?: Record<string, number | string | boolean>;
}

export interface DeviceInfo {
  platform: 'android' | 'ios' | 'web';
  osVersion: string;
  manufacturer?: string;
  model?: string;
  expoSdkVersion: string;
  reactNativeVersion: string;
  totalMemoryMB?: number;
  devicePixelRatio?: number;
  screenDimensions?: { width: number; height: number };
}

export interface TestCase {
  id: string;
  name: string;
  subsystem: SubsystemName;
  skipReason?: string;
  run: (ctx: TestContext) => Promise<void>;
}

export interface TestContext {
  log: (msg: string) => void;
  expect: (label: string, condition: boolean, expected?: string, actual?: string) => void;
  startTimer: (name: string) => () => number;
  getDeviceInfo: () => Promise<DeviceInfo>;
  sampleMemory: () => MemorySample;
}

export interface MemorySample {
  jsHeapUsedMB: number;
  jsHeapTotalMB: number;
  timestamp: number;
}

export interface TestReport {
  generatedAt: number;
  deviceInfo: DeviceInfo;
  totalTests: number;
  passed: number;
  failed: number;
  skipped: number;
  totalDurationMs: number;
  results: TestResult[];
  bySubsystem: Record<string, { total: number; passed: number; failed: number; skipped: number }>;
  findings: string[];
  notes: string[];
}
FRAMEWORKTYPES_EOF
echo "✓ framework/types.ts"

cat > src/engine/__tests__/framework/TestHarness.ts << 'TESTHARNESS_EOF'
/**
 * engine/__tests__/framework/TestHarness.ts
 */

import { Platform, PixelRatio, Dimensions } from 'react-native';
import type {
  TestContext, TestResult, AssertionResult, BenchmarkMetrics,
  DeviceInfo, MemorySample, TestCase,
} from './types';

const TAG = '[TestHarness]';

export class TestCollector {
  logs: string[] = [];
  assertions: AssertionResult[] = [];
  metrics: BenchmarkMetrics = {};
  timers = new Map<string, number>();

  addLog(msg: string): void {
    const line = `[${new Date().toISOString()}] ${msg}`;
    this.logs.push(line);
    console.log(TAG, msg);
  }

  addAssertion(a: AssertionResult): void {
    this.assertions.push(a);
    if (!a.passed) console.warn(TAG, `EXPECT FAIL: ${a.label}${a.expected ? ` (expected ${a.expected}, got ${a.actual})` : ''}`);
  }

  setMetric<K extends keyof BenchmarkMetrics>(key: K, value: BenchmarkMetrics[K]): void {
    this.metrics[key] = value;
  }

  startTimer(name: string): () => number {
    this.timers.set(name, performance.now());
    return () => {
      const start = this.timers.get(name);
      if (start === undefined) return 0;
      const elapsed = performance.now() - start;
      this.timers.delete(name);
      this.metrics.custom = this.metrics.custom ?? {};
      this.metrics.custom[`timer_${name}_ms`] = Math.round(elapsed * 100) / 100;
      return elapsed;
    };
  }
}

export function createTestContext(): { ctx: TestContext; collector: TestCollector } {
  const collector = new TestCollector();
  const ctx: TestContext = {
    log: (msg: string) => collector.addLog(msg),
    expect: (label: string, condition: boolean, expected?: string, actual?: string) => {
      collector.addAssertion({ label, passed: condition, expected, actual });
    },
    startTimer: (name: string) => collector.startTimer(name),
    getDeviceInfo,
    sampleMemory: (): MemorySample => {
      // @ts-ignore
      const mem = (typeof performance !== 'undefined' && (performance as any).memory)
        // @ts-ignore
        ? (performance as any).memory
        : null;
      return {
        jsHeapUsedMB: mem ? mem.usedJSHeapSize / (1024 * 1024) : 0,
        jsHeapTotalMB: mem ? mem.totalJSHeapSize / (1024 * 1024) : 0,
        timestamp: Date.now(),
      };
    },
  };
  return { ctx, collector };
}

export function buildResult(
  testCase: TestCase, collector: TestCollector, startMs: number,
  deviceInfo: DeviceInfo, error?: string,
): TestResult {
  const allPassed = collector.assertions.every((a) => a.passed);
  const status: TestResult['status'] = error ? 'fail' : (allPassed ? 'pass' : 'fail');
  return {
    id: testCase.id, name: testCase.name, subsystem: testCase.subsystem,
    status, durationMs: Math.round(performance.now() - startMs),
    timestamp: Date.now(), assertions: [...collector.assertions],
    metrics: { ...collector.metrics }, error, deviceInfo, logs: [...collector.logs],
  };
}

export async function runTest(testCase: TestCase): Promise<TestResult> {
  if (testCase.skipReason) {
    return {
      id: testCase.id, name: testCase.name, subsystem: testCase.subsystem,
      status: 'skipped', durationMs: 0, timestamp: Date.now(),
      assertions: [], metrics: {}, deviceInfo: await getDeviceInfo(),
      logs: [`SKIPPED: ${testCase.skipReason}`],
    };
  }

  const { ctx, collector } = createTestContext();
  const startMs = performance.now();
  ctx.log(`> starting test: ${testCase.id}`);

  try {
    await testCase.run(ctx);
    const deviceInfo = await getDeviceInfo();
    const result = buildResult(testCase, collector, startMs, deviceInfo);
    ctx.log(`= finished: ${result.status} (${result.durationMs}ms, ${result.assertions.length} assertions)`);
    return result;
  } catch (e: any) {
    const deviceInfo = await getDeviceInfo();
    const errMsg = e?.message || String(e) || 'Unknown error';
    ctx.log(`x threw: ${errMsg}`);
    return buildResult(testCase, collector, startMs, deviceInfo, errMsg);
  }
}

export async function getDeviceInfo(): Promise<DeviceInfo> {
  let expoSdkVersion = 'unknown';
  try {
    const Constants = require('expo-constants');
    expoSdkVersion = Constants?.default?.expoConfig?.sdkVersion ?? Constants?.expoConfig?.sdkVersion ?? 'unknown';
  } catch { /* not installed */ }

  const info: DeviceInfo = {
    platform: Platform.OS as 'android' | 'ios',
    osVersion: Platform.Version?.toString() ?? 'unknown',
    expoSdkVersion,
    reactNativeVersion: getRNVersion(),
    devicePixelRatio: PixelRatio.get(),
    screenDimensions: { width: Dimensions.get('window').width, height: Dimensions.get('window').height },
  };

  if (Platform.OS === 'android') {
    info.manufacturer = (Platform as any).constants?.Manufacturer;
    info.model = (Platform as any).constants?.Model;
  }
  return info;
}

function getRNVersion(): string {
  try {
    const v = (Platform as any).constants?.reactNativeVersion;
    if (v) return `${v.major}.${v.minor}.${v.patch}`;
  } catch { /* ignore */ }
  return 'unknown';
}
TESTHARNESS_EOF
echo "✓ framework/TestHarness.ts"

cat > src/engine/__tests__/framework/TestReport.ts << 'TESTREPORT_EOF'
/**
 * engine/__tests__/framework/TestReport.ts
 */

import type { TestResult, TestReport } from './types';

export function buildReport(results: TestResult[]): TestReport {
  const totalTests = results.length;
  const passed = results.filter((r) => r.status === 'pass').length;
  const failed = results.filter((r) => r.status === 'fail').length;
  const skipped = results.filter((r) => r.status === 'skipped').length;
  const totalDurationMs = results.reduce((sum, r) => sum + r.durationMs, 0);

  const deviceInfo = results[0]?.deviceInfo ?? {
    platform: 'unknown' as any, osVersion: 'unknown',
    expoSdkVersion: 'unknown', reactNativeVersion: 'unknown',
  };

  const bySubsystem: TestReport['bySubsystem'] = {};
  for (const r of results) {
    const s = r.subsystem;
    if (!bySubsystem[s]) bySubsystem[s] = { total: 0, passed: 0, failed: 0, skipped: 0 };
    bySubsystem[s].total += 1;
    if (r.status === 'pass') bySubsystem[s].passed += 1;
    else if (r.status === 'fail') bySubsystem[s].failed += 1;
    else if (r.status === 'skipped') bySubsystem[s].skipped += 1;
  }

  const findings: string[] = [];
  for (const r of results) {
    if (r.status === 'fail') {
      findings.push(`FAIL ${r.id}: ${r.error ?? 'assertions failed'}`);
      for (const a of r.assertions) {
        if (!a.passed) findings.push(`     - ${a.label}${a.expected ? ` (expected ${a.expected}, got ${a.actual})` : ''}`);
      }
    }
  }

  const notes: string[] = [];
  for (const r of results) {
    const m = r.metrics;
    if (m.loadTimeMs && m.loadTimeMs > 3000) notes.push(`WARN ${r.id}: loadTime=${m.loadTimeMs.toFixed(0)}ms (>3s, slow)`);
    if (m.frameTimeAvgMs && m.frameTimeAvgMs > 20) notes.push(`WARN ${r.id}: frameTime=${m.frameTimeAvgMs.toFixed(1)}ms (>20ms = <50fps)`);
    if (m.drawCalls && m.drawCalls > 100) notes.push(`WARN ${r.id}: drawCalls=${m.drawCalls} (>100, high)`);
    if (r.id.includes('meshoptimizer') && m.custom?.timer_optimize_ms) {
      const t = m.custom.timer_optimize_ms as number;
      if (t > 1000) notes.push(`CRIT ${r.id}: MeshOptimizer took ${t.toFixed(0)}ms - recommend removing from runtime path`);
      else if (t > 200) notes.push(`WARN ${r.id}: MeshOptimizer took ${t.toFixed(0)}ms - slow but tolerable`);
    }
    if (r.id.includes('textureloader') && m.custom?.timer_extract_ms) {
      notes.push(`INFO ${r.id}: texture extraction took ${(m.custom.timer_extract_ms as number).toFixed(0)}ms`);
    }
    if (m.cacheHits !== undefined && m.cacheMisses !== undefined) {
      const total = m.cacheHits + m.cacheMisses;
      if (total > 0) notes.push(`INFO ${r.id}: cache hit rate ${((m.cacheHits / total) * 100).toFixed(1)}% (${m.cacheHits}/${total})`);
    }
  }

  return {
    generatedAt: Date.now(), deviceInfo, totalTests, passed, failed, skipped,
    totalDurationMs, results, bySubsystem, findings, notes,
  };
}

export function renderReport(report: TestReport): string {
  const lines: string[] = [];
  lines.push('===============================================================');
  lines.push('  VTO ENGINE - VERIFICATION SPRINT BENCHMARK REPORT');
  lines.push('===============================================================');
  lines.push('');
  lines.push(`Generated: ${new Date(report.generatedAt).toISOString()}`);
  lines.push(`Device:    ${report.deviceInfo.manufacturer ?? ''} ${report.deviceInfo.model ?? ''}`.trim());
  lines.push(`Platform:  ${report.deviceInfo.platform} ${report.deviceInfo.osVersion}`);
  lines.push(`Expo SDK:  ${report.deviceInfo.expoSdkVersion}`);
  lines.push(`RN:        ${report.deviceInfo.reactNativeVersion}`);
  lines.push(`Screen:    ${report.deviceInfo.screenDimensions?.width}x${report.deviceInfo.screenDimensions?.height} @${report.deviceInfo.devicePixelRatio}x`);
  lines.push('');
  lines.push('- SUMMARY -----------------------------------------------------');
  lines.push(`  Total:  ${report.totalTests}`);
  lines.push(`  Pass:   ${report.passed}`);
  lines.push(`  Fail:   ${report.failed}`);
  lines.push(`  Skip:   ${report.skipped}`);
  lines.push(`  Time:   ${(report.totalDurationMs / 1000).toFixed(1)}s`);
  lines.push('');

  lines.push('- BY SUBSYSTEM ------------------------------------------------');
  const subsystemNames = Object.keys(report.bySubsystem).sort();
  for (const s of subsystemNames) {
    const stats = report.bySubsystem[s];
    const passRate = stats.total > 0 ? ((stats.passed / stats.total) * 100).toFixed(0) : '0';
    lines.push(`  ${s.padEnd(25)} ${stats.passed}/${stats.total} (${passRate}%)`);
  }
  lines.push('');

  if (report.findings.length > 0) {
    lines.push('- CRITICAL FINDINGS -------------------------------------------');
    for (const f of report.findings) lines.push(`  ${f}`);
    lines.push('');
  } else {
    lines.push('- CRITICAL FINDINGS -------------------------------------------');
    lines.push('  (none)');
    lines.push('');
  }

  if (report.notes.length > 0) {
    lines.push('- PERFORMANCE NOTES -------------------------------------------');
    for (const n of report.notes) lines.push(`  ${n}`);
    lines.push('');
  }

  lines.push('- PER-TEST DETAILS --------------------------------------------');
  for (const r of report.results) {
    const icon = r.status === 'pass' ? 'OK' : r.status === 'fail' ? 'XX' : 'SKIP';
    lines.push(`  [${icon}] ${r.id.padEnd(40)} ${r.durationMs.toString().padStart(6)}ms  [${r.subsystem}]`);
    if (r.metrics.custom) {
      for (const [k, v] of Object.entries(r.metrics.custom)) {
        lines.push(`       ${k}: ${v}`);
      }
    }
  }
  lines.push('');
  lines.push('===============================================================');
  return lines.join('\n');
}

export function reportToJson(report: TestReport): string {
  return JSON.stringify(report, null, 2);
}
TESTREPORT_EOF
echo "✓ framework/TestReport.ts"

echo ""
echo "=== Part 7: Test files (10) ==="

cat > src/engine/__tests__/TextureLoader.test.ts << 'TLTEST_EOF'
/**
 * engine/__tests__/TextureLoader.test.ts
 *
 * THE MOST CRITICAL TEST. Proves the Blob bypass works on Android.
 */

import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader';
import * as FileSystem from 'expo-file-system/legacy';

import type { TestCase } from './framework/types';
import { TextureLoader } from '../textures/TextureLoader';

const TEST_ASSET_URL = 'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/BoxTextured/glTF-Binary/BoxTextured.glb';
const TEST_ASSET_ID = 'boxtextured_test';
const TEST_TEMP_DIR = `${FileSystem.cacheDirectory}test_textures/`;

export const TextureLoaderTests: TestCase[] = [
  {
    id: 'textureloader.extract',
    name: 'TextureLoader.extractFromGLB - extracts textures to file:// URIs',
    subsystem: 'TextureLoader',
    async run(ctx) {
      ctx.log('Downloading test asset: BoxTextured.glb');
      const stopDownload = ctx.startTimer('download');
      const localPath = `${FileSystem.cacheDirectory}${TEST_ASSET_ID}.glb`;
      const info = await FileSystem.getInfoAsync(localPath);
      if (!info.exists) {
        const result = await FileSystem.downloadAsync(TEST_ASSET_URL, localPath);
        if (result.status !== 200) {
          ctx.expect('download succeeded', false, 'HTTP 200', `HTTP ${result.status}`);
          return;
        }
      }
      const downloadMs = stopDownload();
      ctx.log(`Download/cache: ${downloadMs.toFixed(0)}ms`);

      ctx.log('Reading GLB as base64 -> ArrayBuffer');
      const stopRead = ctx.startTimer('read');
      const b64 = await FileSystem.readAsStringAsync(localPath, { encoding: 'base64' });
      const buf = base64ToArrayBuffer(b64);
      const readMs = stopRead();
      ctx.log(`Read: ${readMs.toFixed(0)}ms, ${buf.byteLength} bytes`);

      ctx.expect('GLB is non-empty', buf.byteLength > 100, '>100 bytes', `${buf.byteLength} bytes`);

      ctx.log('Running TextureLoader.extractFromGLB()');
      const loader = new TextureLoader();
      const stopExtract = ctx.startTimer('extract');

      let extracted;
      try {
        extracted = await loader.extractFromGLB(buf, TEST_TEMP_DIR);
      } catch (e: any) {
        ctx.expect('extractFromGLB did not throw', false, 'no error', e.message);
        return;
      }
      const extractMs = stopExtract();
      ctx.log(`Extract: ${extractMs.toFixed(0)}ms`);

      ctx.expect('extraction returned a result', extracted !== null && extracted !== undefined);
      ctx.expect('patched JSON is non-null', extracted.patchedJson !== null);

      const imageCount = Object.keys(extracted.imageUris).length;
      ctx.log(`Extracted ${imageCount} texture(s), total ${extracted.totalBytes} bytes`);
      ctx.expect('at least 1 texture extracted', imageCount >= 1, '>=1', `${imageCount}`);

      let allFileUris = true;
      for (const [idx, uri] of Object.entries(extracted.imageUris)) {
        if (!uri.startsWith('file://')) {
          allFileUris = false;
          ctx.log(`image[${idx}] URI is not file://: ${uri}`);
        }
      }
      ctx.expect('all image URIs are file://', allFileUris);

      const patchedImages = extracted.patchedJson?.images ?? [];
      let allPatchedHaveUri = true;
      for (let i = 0; i < patchedImages.length; i++) {
        const img = patchedImages[i];
        if (!img.uri) { allPatchedHaveUri = false; ctx.log(`patched images[${i}] is missing uri`); }
        if (img.bufferView !== undefined) { allPatchedHaveUri = false; ctx.log(`patched images[${i}] still has bufferView`); }
      }
      ctx.expect('patched images[] all have uri, no bufferView', allPatchedHaveUri);

      let filesExist = true;
      for (const uri of Object.values(extracted.imageUris)) {
        const path = uri.replace('file://', '');
        const finfo = await FileSystem.getInfoAsync(path);
        if (!finfo.exists) { filesExist = false; ctx.log(`temp file does not exist: ${path}`); }
      }
      ctx.expect('all temp texture files exist on disk', filesExist);

      try {
        JSON.stringify(extracted.patchedJson);
        ctx.expect('patched JSON re-serializes', true);
      } catch (e: any) {
        ctx.expect('patched JSON re-serializes', false, 'no error', e.message);
      }

      ctx.expect('extraction time <5s', extractMs < 5000, '<5000ms', `${extractMs.toFixed(0)}ms`);
    },
  },

  {
    id: 'textureloader.parse_no_blob_error',
    name: 'GLTFLoader.parse - does NOT throw "Creating blobs" error',
    subsystem: 'TextureLoader',
    async run(ctx) {
      ctx.log('Downloading test asset: BoxTextured.glb');
      const localPath = `${FileSystem.cacheDirectory}${TEST_ASSET_ID}.glb`;
      const info = await FileSystem.getInfoAsync(localPath);
      if (!info.exists) await FileSystem.downloadAsync(TEST_ASSET_URL, localPath);

      const b64 = await FileSystem.readAsStringAsync(localPath, { encoding: 'base64' });
      const buf = base64ToArrayBuffer(b64);

      ctx.log('Extracting textures (to bypass Blob)');
      const loader = new TextureLoader();
      const extracted = await loader.extractFromGLB(buf, TEST_TEMP_DIR + 'parse_test/');

      ctx.log('Rebuilding GLB with patched JSON');
      const stopRebuild = ctx.startTimer('rebuild');
      const rebuilt = rebuildGlb(extracted.patchedJson, buf);
      const rebuildMs = stopRebuild();
      ctx.log(`Rebuild: ${rebuildMs.toFixed(0)}ms, ${rebuilt.byteLength} bytes`);

      ctx.log('Calling GLTFLoader.parse() - watching for Blob error');
      const gltfLoader = new GLTFLoader();
      const stopParse = ctx.startTimer('parse');

      let blobErrorSeen = false;
      let parseError: any = null;
      let gltf: any = null;

      const originalConsoleError = console.error;
      console.error = (...args: any[]) => {
        const msg = args.join(' ');
        if (msg.includes('Creating blobs') || msg.includes("Couldn't load texture")) blobErrorSeen = true;
        originalConsoleError.apply(console, args as any);
      };

      try {
        gltf = await new Promise<any>((resolve, reject) => {
          gltfLoader.parse(rebuilt, '', resolve, reject);
        });
      } catch (e: any) {
        parseError = e;
      } finally {
        console.error = originalConsoleError;
      }

      const parseMs = stopParse();
      ctx.log(`Parse: ${parseMs.toFixed(0)}ms`);

      ctx.expect('parse did not throw', parseError === null, 'no error', parseError?.message ?? 'none');
      ctx.expect('no "Creating blobs" error in logs', !blobErrorSeen, 'false', `${blobErrorSeen}`);
      ctx.expect('gltf object was returned', gltf !== null && gltf !== undefined);
      ctx.expect('gltf.scene is a THREE.Group', gltf?.scene instanceof THREE.Group);

      if (gltf?.scene) {
        let meshCount = 0;
        gltf.scene.traverse((obj: any) => { if (obj.isMesh) meshCount++; });
        ctx.log(`Parsed scene has ${meshCount} mesh(es)`);
        ctx.expect('parsed scene has >=1 mesh', meshCount >= 1, '>=1', `${meshCount}`);
      }
    },
  },
];

function base64ToArrayBuffer(base64: string): ArrayBuffer {
  try {
    // @ts-ignore
    if (typeof Buffer !== 'undefined') {
      // @ts-ignore
      const buf = Buffer.from(base64, 'base64');
      return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
    }
  } catch { /* fall through */ }
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function rebuildGlb(patchedJson: any, originalBuffer: ArrayBuffer): ArrayBuffer {
  if (!patchedJson) return originalBuffer;
  const jsonBytes = new TextEncoder().encode(JSON.stringify(patchedJson));
  const jsonPaddedLen = Math.ceil(jsonBytes.length / 4) * 4;
  const jsonPadded = new Uint8Array(jsonPaddedLen);
  jsonPadded.set(jsonBytes);

  const origBytes = new Uint8Array(originalBuffer);
  const dv = new DataView(originalBuffer);
  let offset = 12;
  let binOffset = 0;
  let binLength = 0;
  while (offset + 8 <= origBytes.length) {
    const chunkLength = dv.getUint32(offset, true);
    const chunkType = dv.getUint32(offset + 4, true);
    if (chunkType === 0x004e4942) { binOffset = offset + 8; binLength = chunkLength; }
    offset = offset + 8 + chunkLength;
  }
  const binPaddedLen = Math.ceil(binLength / 4) * 4;
  const totalLength = 12 + 8 + jsonPaddedLen + (binLength > 0 ? 8 + binPaddedLen : 0);
  const out = new ArrayBuffer(totalLength);
  const outBytes = new Uint8Array(out);
  const outDv = new DataView(out);
  outDv.setUint32(0, 0x46546c67, true);
  outDv.setUint32(4, 2, true);
  outDv.setUint32(8, totalLength, true);
  let w = 12;
  outDv.setUint32(w, jsonPaddedLen, true);
  outDv.setUint32(w + 4, 0x4e4f534a, true);
  outBytes.set(jsonPadded, w + 8);
  w += 8 + jsonPaddedLen;
  if (binLength > 0) {
    outDv.setUint32(w, binPaddedLen, true);
    outDv.setUint32(w + 4, 0x004e4942, true);
    outBytes.set(origBytes.subarray(binOffset, binOffset + binLength), w + 8);
  }
  return out;
}
TLTEST_EOF
echo "✓ TextureLoader.test.ts"

cat > src/engine/__tests__/AssetValidator.test.ts << 'AVTEST_EOF'
/**
 * engine/__tests__/AssetValidator.test.ts
 */

import * as FileSystem from 'expo-file-system/legacy';
import type { TestCase } from './framework/types';
import { AssetValidator } from '../assets/AssetValidator';

const TEST_DIR = `${FileSystem.cacheDirectory}validator_tests/`;
const VALID_GLB_URL = 'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/Box/glTF-Binary/Box.glb';
const TEXTURED_GLB_URL = 'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/BoxTextured/glTF-Binary/BoxTextured.glb';

export const AssetValidatorTests: TestCase[] = [
  {
    id: 'validator.valid_box',
    name: 'AssetValidator - accepts valid Box.glb',
    subsystem: 'AssetValidator',
    async run(ctx) {
      const buf = await fetchTestAsset(ctx, VALID_GLB_URL, 'Box.glb');
      if (!buf) return;
      const validator = new AssetValidator();
      const stopValidate = ctx.startTimer('validate');
      const result = validator.validate(buf);
      const validateMs = stopValidate();
      ctx.log(`Validate: ${validateMs.toFixed(2)}ms`);
      ctx.expect('valid=true', result.valid === true, 'true', `${result.valid}`);
      ctx.expect('no errors', result.errors.length === 0, '0 errors', `${result.errors.length} errors`);
      ctx.expect('1 mesh detected', result.stats.meshCount === 1, '1', `${result.stats.meshCount}`);
      ctx.expect('JSON chunk non-zero', result.stats.jsonChunkBytes > 0);
      ctx.expect('validation time <50ms', validateMs < 50, '<50ms', `${validateMs.toFixed(2)}ms`);
    },
  },
  {
    id: 'validator.valid_textured',
    name: 'AssetValidator - accepts valid BoxTextured.glb',
    subsystem: 'AssetValidator',
    async run(ctx) {
      const buf = await fetchTestAsset(ctx, TEXTURED_GLB_URL, 'BoxTextured.glb');
      if (!buf) return;
      const validator = new AssetValidator();
      const result = validator.validate(buf);
      ctx.expect('valid=true', result.valid === true);
      ctx.expect('no errors', result.errors.length === 0);
      ctx.expect('1 mesh detected', result.stats.meshCount === 1);
      ctx.expect('>=1 texture detected', result.stats.textureCount >= 1, '>=1', `${result.stats.textureCount}`);
      ctx.expect('BIN chunk non-zero', result.stats.binChunkBytes > 0);
    },
  },
  {
    id: 'validator.bad_magic',
    name: 'AssetValidator - rejects file with wrong magic bytes',
    subsystem: 'AssetValidator',
    async run(ctx) {
      const fake = new ArrayBuffer(20);
      const dv = new DataView(fake);
      dv.setUint32(0, 0xDEADBEEF, true);
      dv.setUint32(4, 2, true);
      dv.setUint32(8, 20, true);
      const validator = new AssetValidator();
      const result = validator.validate(fake);
      ctx.expect('valid=false', result.valid === false);
      ctx.expect('at least 1 error', result.errors.length >= 1);
      ctx.expect('error mentions magic', result.errors.some((e) => e.toLowerCase().includes('magic')));
    },
  },
  {
    id: 'validator.truncated',
    name: 'AssetValidator - rejects truncated GLB',
    subsystem: 'AssetValidator',
    async run(ctx) {
      const buf = await fetchTestAsset(ctx, VALID_GLB_URL, 'Box.glb');
      if (!buf) return;
      const truncated = buf.slice(0, buf.byteLength - 100);
      const validator = new AssetValidator();
      const result = validator.validate(truncated);
      ctx.expect('valid=false', result.valid === false);
      ctx.expect('error mentions length or chunk', result.errors.some((e) => e.toLowerCase().includes('length') || e.toLowerCase().includes('chunk')));
    },
  },
  {
    id: 'validator.too_small',
    name: 'AssetValidator - rejects file too small to be a GLB',
    subsystem: 'AssetValidator',
    async run(ctx) {
      const tiny = new ArrayBuffer(5);
      const validator = new AssetValidator();
      const result = validator.validate(tiny);
      ctx.expect('valid=false', result.valid === false);
      ctx.expect('error mentions too small', result.errors.some((e) => e.toLowerCase().includes('small')));
    },
  },
  {
    id: 'validator.unsupported_extension',
    name: 'AssetValidator - warns on unsupported extensions',
    subsystem: 'AssetValidator',
    async run(ctx) {
      const gltfJson = {
        asset: { version: '2.0' },
        extensionsUsed: ['KHR_materials_unlit', 'FAKE_unknown_extension'],
        meshes: [{ primitives: [{ attributes: { POSITION: 0 } }] }],
        accessors: [{ bufferView: 0, componentType: 5126, count: 3, type: 'VEC3' }],
        bufferViews: [{ buffer: 0, byteOffset: 0, byteLength: 36 }],
        buffers: [{ byteLength: 36 }],
      };
      const binChunk = new ArrayBuffer(36);
      const glb = buildGlb(gltfJson, binChunk);
      const validator = new AssetValidator();
      const result = validator.validate(glb);
      ctx.expect('valid=true (warnings only)', result.valid === true);
      ctx.expect('>=1 warning about unsupported extension', result.warnings.some((w) => w.toLowerCase().includes('unsupported') || w.toLowerCase().includes('fake')));
      ctx.expect('usesExtensions includes both', result.stats.usesExtensions.length === 2);
    },
  },
];

async function fetchTestAsset(ctx: any, url: string, filename: string): Promise<ArrayBuffer | null> {
  ctx.log(`Fetching ${filename}...`);
  const localPath = `${TEST_DIR}${filename}`;
  const dirInfo = await FileSystem.getInfoAsync(TEST_DIR);
  if (!dirInfo.exists) await FileSystem.makeDirectoryAsync(TEST_DIR, { intermediates: true });
  const info = await FileSystem.getInfoAsync(localPath);
  if (!info.exists) {
    const result = await FileSystem.downloadAsync(url, localPath);
    if (result.status !== 200) {
      ctx.expect(`${filename} download succeeded`, false, 'HTTP 200', `HTTP ${result.status}`);
      return null;
    }
  }
  const b64 = await FileSystem.readAsStringAsync(localPath, { encoding: 'base64' });
  try {
    // @ts-ignore
    if (typeof Buffer !== 'undefined') {
      // @ts-ignore
      const buf = Buffer.from(b64, 'base64');
      return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
    }
  } catch { /* fall through */ }
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function buildGlb(json: any, binChunk: ArrayBuffer): ArrayBuffer {
  const jsonBytes = new TextEncoder().encode(JSON.stringify(json));
  const jsonPaddedLen = Math.ceil(jsonBytes.length / 4) * 4;
  const jsonPadded = new Uint8Array(jsonPaddedLen);
  jsonPadded.set(jsonBytes);
  const binPaddedLen = Math.ceil(binChunk.byteLength / 4) * 4;
  const totalLength = 12 + 8 + jsonPaddedLen + 8 + binPaddedLen;
  const out = new ArrayBuffer(totalLength);
  const outBytes = new Uint8Array(out);
  const outDv = new DataView(out);
  outDv.setUint32(0, 0x46546c67, true);
  outDv.setUint32(4, 2, true);
  outDv.setUint32(8, totalLength, true);
  let w = 12;
  outDv.setUint32(w, jsonPaddedLen, true);
  outDv.setUint32(w + 4, 0x4e4f534a, true);
  outBytes.set(jsonPadded, w + 8);
  w += 8 + jsonPaddedLen;
  outDv.setUint32(w, binPaddedLen, true);
  outDv.setUint32(w + 4, 0x004e4942, true);
  outBytes.set(new Uint8Array(binChunk), w + 8);
  return out;
}
AVTEST_EOF
echo "✓ AssetValidator.test.ts"

cat > src/engine/__tests__/CacheManager.test.ts << 'CMTEST_EOF'
/**
 * engine/__tests__/CacheManager.test.ts
 */

import * as FileSystem from 'expo-file-system/legacy';
import type { TestCase } from './framework/types';
import { CacheManager } from '../assets/CacheManager';

const TEST_CACHE_DIR = `${FileSystem.cacheDirectory}test_cache_${Date.now()}/`;

async function makeTestFile(path: string, content: string): Promise<void> {
  await FileSystem.writeAsStringAsync(path, content);
}

async function fileExists(path: string): Promise<boolean> {
  const info = await FileSystem.getInfoAsync(path);
  return info.exists;
}

export const CacheManagerTests: TestCase[] = [
  {
    id: 'cache.put_get',
    name: 'CacheManager - put + get roundtrip',
    subsystem: 'CacheManager',
    async run(ctx) {
      const cache = new CacheManager({ cacheDirectory: TEST_CACHE_DIR + 'test1/', manifestPath: TEST_CACHE_DIR + 'test1/manifest.json' });
      const sourcePath = `${TEST_CACHE_DIR}test1_source.txt`;
      await makeTestFile(sourcePath, 'hello world');
      const descriptor = { id: 'test_asset_1', version: 1, url: 'http://example.com/test.glb', kind: 'garment' as const };
      ctx.log('Putting asset into cache...');
      const entry = await cache.put(descriptor, sourcePath);
      ctx.expect('entry returned', entry !== null);
      ctx.expect('entry has localPath', typeof entry.localPath === 'string');
      ctx.expect('file exists at localPath', await fileExists(entry.localPath));
      ctx.expect('entry size > 0', entry.sizeBytes > 0);

      ctx.log('Getting asset from cache...');
      const stopGet = ctx.startTimer('get');
      const got = await cache.get(descriptor);
      const getMs = stopGet();
      ctx.log(`Get: ${getMs.toFixed(2)}ms`);
      ctx.expect('cache hit', got !== null);
      ctx.expect('same localPath', got?.localPath === entry.localPath);
      ctx.expect('accessCount incremented', got?.accessCount === 2, '2', `${got?.accessCount}`);
    },
  },
  {
    id: 'cache.version_invalidation',
    name: 'CacheManager - version bump invalidates old cache',
    subsystem: 'CacheManager',
    async run(ctx) {
      const cache = new CacheManager({ cacheDirectory: TEST_CACHE_DIR + 'test2/', manifestPath: TEST_CACHE_DIR + 'test2/manifest.json' });
      const sourcePath = `${TEST_CACHE_DIR}test2_source.txt`;
      await makeTestFile(sourcePath, 'version 1 content');
      const descV1 = { id: 'versioned_asset', version: 1, url: 'http://example.com/test.glb', kind: 'garment' as const };
      ctx.log('Putting v1...');
      const entryV1 = await cache.put(descV1, sourcePath);
      ctx.expect('v1 file exists', await fileExists(entryV1.localPath));

      ctx.log('Getting v1 (should hit)...');
      const gotV1 = await cache.get(descV1);
      ctx.expect('v1 cache hit', gotV1 !== null);

      ctx.log('Getting v2 (should MISS - invalidate v1)...');
      const descV2 = { ...descV1, version: 2 };
      const gotV2 = await cache.get(descV2);
      ctx.expect('v2 cache miss (returned null)', gotV2 === null);

      ctx.log('Verifying v1 file was deleted...');
      const v1StillExists = await fileExists(entryV1.localPath);
      ctx.expect('v1 file deleted after version bump', v1StillExists === false);

      ctx.log('Getting v1 again (should also miss now)...');
      const gotV1again = await cache.get(descV1);
      ctx.expect('v1 also misses after invalidation', gotV1again === null);
    },
  },
  {
    id: 'cache.checksum_invalidation',
    name: 'CacheManager - checksum mismatch invalidates',
    subsystem: 'CacheManager',
    async run(ctx) {
      const cache = new CacheManager({ cacheDirectory: TEST_CACHE_DIR + 'test3/', manifestPath: TEST_CACHE_DIR + 'test3/manifest.json' });
      const sourcePath = `${TEST_CACHE_DIR}test3_source.txt`;
      await makeTestFile(sourcePath, 'checksum test');
      const descWithChecksumA = { id: 'checksummed_asset', version: 1, url: 'http://example.com/test.glb', kind: 'garment' as const, checksum: 'aaa' };
      await cache.put(descWithChecksumA, sourcePath);
      const gotA = await cache.get(descWithChecksumA);
      ctx.expect('cache hit with matching checksum', gotA !== null);
      const descWithChecksumB = { ...descWithChecksumA, checksum: 'bbb' };
      const gotB = await cache.get(descWithChecksumB);
      ctx.expect('cache miss with different checksum', gotB === null);
    },
  },
  {
    id: 'cache.lru_eviction',
    name: 'CacheManager - LRU evicts oldest entries when budget exceeded',
    subsystem: 'CacheManager',
    async run(ctx) {
      const cache = new CacheManager({
        cacheDirectory: TEST_CACHE_DIR + 'test4/',
        manifestPath: TEST_CACHE_DIR + 'test4/manifest.json',
        kindBudgets: { garment: 100, body: Number.MAX_SAFE_INTEGER, accessory: 50, environment: 100, animation: 20 },
      });
      const sourcePath1 = `${TEST_CACHE_DIR}test4_src1.txt`;
      const sourcePath2 = `${TEST_CACHE_DIR}test4_src2.txt`;
      const sourcePath3 = `${TEST_CACHE_DIR}test4_src3.txt`;
      await makeTestFile(sourcePath1, 'a'.repeat(50));
      await makeTestFile(sourcePath2, 'b'.repeat(50));
      await makeTestFile(sourcePath3, 'c'.repeat(50));
      ctx.log('Adding 3 garment assets, each 50 bytes...');
      await cache.put({ id: 'g1', version: 1, url: 'http://e/1.glb', kind: 'garment' }, sourcePath1);
      await cache.put({ id: 'g2', version: 1, url: 'http://e/2.glb', kind: 'garment' }, sourcePath2);
      await cache.put({ id: 'g3', version: 1, url: 'http://e/3.glb', kind: 'garment' }, sourcePath3);
      const pruneResult = await cache.prune();
      ctx.log(`Prune evicted ${pruneResult.evictedIds.length} entries, freed ${pruneResult.freedBytes} bytes`);
      ctx.expect('at least 1 entry evicted', pruneResult.evictedIds.length >= 1);
      ctx.expect('total bytes <= budget (100)', (await cache.getManifest()).totalBytes <= 100, '<=100', `${(await cache.getManifest()).totalBytes}`);
      ctx.expect('g1 evicted (oldest)', pruneResult.evictedIds.includes('g1'));
      const g3Entry = await cache.get({ id: 'g3', version: 1, url: 'http://e/3.glb', kind: 'garment' });
      ctx.expect('g3 still in cache (most recent)', g3Entry !== null);
    },
  },
  {
    id: 'cache.body_never_evicted',
    name: 'CacheManager - body models are never evicted',
    subsystem: 'CacheManager',
    async run(ctx) {
      const cache = new CacheManager({
        cacheDirectory: TEST_CACHE_DIR + 'test5/',
        manifestPath: TEST_CACHE_DIR + 'test5/manifest.json',
        kindBudgets: { body: 50, garment: 50, accessory: 50, environment: 50, animation: 20 },
      });
      const sourcePath = `${TEST_CACHE_DIR}test5_body.txt`;
      await makeTestFile(sourcePath, 'x'.repeat(200));
      const entry = await cache.put({ id: 'body_main', version: 1, url: 'http://e/body.glb', kind: 'body' }, sourcePath);
      const pruneResult = await cache.prune();
      ctx.log(`Prune evicted: ${pruneResult.evictedIds.length} (expected 0 - body is protected)`);
      ctx.expect('body NOT evicted even when over budget', pruneResult.evictedIds.length === 0);
      ctx.expect('body file still on disk', await fileExists(entry.localPath));
    },
  },
  {
    id: 'cache.manifest_persists',
    name: 'CacheManager - manifest persists across instances',
    subsystem: 'CacheManager',
    async run(ctx) {
      const dir = TEST_CACHE_DIR + 'test6/';
      const manifestPath = `${dir}manifest.json`;
      const cache1 = new CacheManager({ cacheDirectory: dir, manifestPath });
      const sourcePath = `${TEST_CACHE_DIR}test6_source.txt`;
      await makeTestFile(sourcePath, 'persist test');
      ctx.log('Putting asset via cache1...');
      await cache1.put({ id: 'persistent_asset', version: 1, url: 'http://e/p.glb', kind: 'garment' }, sourcePath);
      ctx.expect('manifest.json exists on disk', await fileExists(manifestPath));
      ctx.log('Creating new CacheManager instance (simulates restart)...');
      const cache2 = new CacheManager({ cacheDirectory: dir, manifestPath });
      const manifest = await cache2.getManifest();
      ctx.expect('manifest loaded by cache2', manifest.entries['persistent_asset'] !== undefined);
      ctx.expect('entry has correct id', manifest.entries['persistent_asset']?.descriptor.id === 'persistent_asset');
    },
  },
  {
    id: 'cache.orphan_gc',
    name: 'CacheManager - orphan GC removes files with no manifest entry',
    subsystem: 'CacheManager',
    async run(ctx) {
      const dir = TEST_CACHE_DIR + 'test7/';
      const cache = new CacheManager({ cacheDirectory: dir, manifestPath: `${dir}manifest.json` });
      const sourcePath = `${dir}source.txt`;
      await makeTestFile(sourcePath, 'gc test');
      await cache.put({ id: 'tracked', version: 1, url: 'http://e/t.glb', kind: 'garment' }, sourcePath);
      const orphanPath = `${dir}orphan.glb`;
      await makeTestFile(orphanPath, 'i am an orphan');
      ctx.expect('orphan file exists before GC', await fileExists(orphanPath));
      const cache2 = new CacheManager({ cacheDirectory: dir, manifestPath: `${dir}manifest.json` });
      await cache2.getManifest();
      const orphanGone = !(await fileExists(orphanPath));
      ctx.expect('orphan file removed after GC', orphanGone);
    },
  },
];
CMTEST_EOF
echo "✓ CacheManager.test.ts"

cat > src/engine/__tests__/AssetManager.test.ts << 'AMTEST_EOF'
/**
 * engine/__tests__/AssetManager.test.ts
 */

import * as THREE from 'three';
import * as FileSystem from 'expo-file-system/legacy';
import type { TestCase } from './framework/types';
import type { LoadPhase } from '../core/types';
import { AssetManager } from '../assets/AssetManager';

const TEST_ASSETS = {
  box: { url: 'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/Box/glTF-Binary/Box.glb', id: 'test_box', expectedMeshes: 1, expectedTriangles: 12 },
  boxTextured: { url: 'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/BoxTextured/glTF-Binary/BoxTextured.glb', id: 'test_boxtextured', expectedMeshes: 1, expectedTriangles: 12, expectedTextures: 1 },
  riggedFigure: { url: 'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/RiggedFigure/glTF-Binary/RiggedFigure.glb', id: 'test_riggedfigure', expectedMeshes: 5, expectedSkeleton: true },
};

export const AssetManagerTests: TestCase[] = [
  {
    id: 'assetmanager.load_box',
    name: 'AssetManager - full pipeline for Box.glb',
    subsystem: 'AssetManager',
    async run(ctx) {
      const manager = new AssetManager({ tempDir: `${FileSystem.cacheDirectory}am_tests/box/` });
      const phases: LoadPhase[] = [];
      const unsub = manager.onProgress((p) => { if (phases[phases.length - 1] !== p.phase) phases.push(p.phase); });
      const desc = { id: TEST_ASSETS.box.id, version: 1, url: TEST_ASSETS.box.url, kind: 'garment' as const };
      ctx.log('Loading Box.glb via AssetManager...');
      const stopLoad = ctx.startTimer('load');
      let loaded;
      try {
        loaded = await manager.load(desc);
      } catch (e: any) {
        ctx.expect('load did not throw', false, 'no error', e.message);
        unsub();
        return;
      }
      const loadMs = stopLoad();
      ctx.log(`Load: ${loadMs.toFixed(0)}ms`);
      unsub();

      ctx.expect('loaded asset returned', loaded !== null);
      ctx.expect('scene is THREE.Group', loaded.scene instanceof THREE.Group);
      ctx.expect(`mesh count = ${TEST_ASSETS.box.expectedMeshes}`, loaded.stats.meshCount === TEST_ASSETS.box.expectedMeshes);
      ctx.expect(`triangle count = ${TEST_ASSETS.box.expectedTriangles}`, loaded.stats.triangleCount === TEST_ASSETS.box.expectedTriangles);
      ctx.expect('bbox is non-zero size', loaded.bbox.size.x > 0 && loaded.bbox.size.y > 0 && loaded.bbox.size.z > 0);
      ctx.expect('localPath set', typeof loaded.localPath === 'string' && loaded.localPath.length > 0);
      ctx.log(`Phases: ${phases.join(' -> ')}`);
      ctx.expect('saw downloading phase', phases.includes('downloading'));
      ctx.expect('saw validating phase', phases.includes('validating'));
      ctx.expect('saw parsing phase', phases.includes('parsing'));
      ctx.expect('saw caching phase', phases.includes('caching'));
      ctx.expect('saw ready phase', phases.includes('ready'));
      ctx.expect('load time <30s', loadMs < 30000, '<30000ms', `${loadMs.toFixed(0)}ms`);
    },
  },
  {
    id: 'assetmanager.load_textured',
    name: 'AssetManager - full pipeline for BoxTextured.glb (proves Blob bypass)',
    subsystem: 'AssetManager',
    async run(ctx) {
      const manager = new AssetManager({ tempDir: `${FileSystem.cacheDirectory}am_tests/textured/` });
      const desc = { id: TEST_ASSETS.boxTextured.id, version: 1, url: TEST_ASSETS.boxTextured.url, kind: 'garment' as const };
      ctx.log('Loading BoxTextured.glb via AssetManager...');
      const stopLoad = ctx.startTimer('load');
      let blobErrorSeen = false;
      const origError = console.error;
      console.error = (...args: any[]) => {
        const msg = args.join(' ');
        if (msg.includes('Creating blobs') || msg.includes("Couldn't load texture")) blobErrorSeen = true;
        origError.apply(console, args as any);
      };
      let loaded;
      try {
        loaded = await manager.load(desc);
      } catch (e: any) {
        ctx.expect('load did not throw', false, 'no error', e.message);
        console.error = origError;
        return;
      } finally {
        console.error = origError;
      }
      const loadMs = stopLoad();
      ctx.log(`Load: ${loadMs.toFixed(0)}ms`);
      ctx.expect('loaded asset returned', loaded !== null);
      ctx.expect(`mesh count = 1`, loaded.stats.meshCount === 1);
      ctx.expect(`texture count >= 1`, (loaded.stats.textureCount ?? 0) >= 1);
      ctx.expect('NO "Creating blobs" error', !blobErrorSeen, 'false', `${blobErrorSeen}`);
      let foundTexturedMaterial = false;
      loaded.scene.traverse((obj: any) => { if (obj.isMesh && obj.material?.map) foundTexturedMaterial = true; });
      ctx.expect('at least one mesh has a texture map', foundTexturedMaterial);
    },
  },
  {
    id: 'assetmanager.cache_hit',
    name: 'AssetManager - second load is cache hit (much faster)',
    subsystem: 'AssetManager',
    async run(ctx) {
      const manager = new AssetManager({ tempDir: `${FileSystem.cacheDirectory}am_tests/cachehit/` });
      const desc = { id: 'cachehit_test', version: 1, url: TEST_ASSETS.box.url, kind: 'garment' as const };
      ctx.log('First load (cache miss)...');
      const stopFirst = ctx.startTimer('first_load');
      await manager.load(desc);
      const firstMs = stopFirst();
      ctx.log(`First load: ${firstMs.toFixed(0)}ms`);
      ctx.log('Second load (cache hit)...');
      const stopSecond = ctx.startTimer('second_load');
      await manager.load(desc);
      const secondMs = stopSecond();
      ctx.log(`Second load: ${secondMs.toFixed(0)}ms`);
      ctx.expect('second load faster than first', secondMs < firstMs, `${firstMs.toFixed(0)}ms`, `${secondMs.toFixed(0)}ms`);
      ctx.expect('second load < 50% of first load time', secondMs < firstMs * 0.5);
    },
  },
  {
    id: 'assetmanager.load_rigged',
    name: 'AssetManager - RiggedFigure.glb (skeleton extraction)',
    subsystem: 'AssetManager',
    async run(ctx) {
      const manager = new AssetManager({ tempDir: `${FileSystem.cacheDirectory}am_tests/rigged/` });
      const desc = { id: TEST_ASSETS.riggedFigure.id, version: 1, url: TEST_ASSETS.riggedFigure.url, kind: 'body' as const };
      ctx.log('Loading RiggedFigure.glb...');
      const stopLoad = ctx.startTimer('load');
      const loaded = await manager.load(desc);
      const loadMs = stopLoad();
      ctx.log(`Load: ${loadMs.toFixed(0)}ms`);
      ctx.expect('loaded asset returned', loaded !== null);
      ctx.expect(`mesh count >= 3`, loaded.stats.meshCount >= 3, '>=3', `${loaded.stats.meshCount}`);
      ctx.expect('skeleton extracted', loaded.skeleton !== null);
      if (loaded.skeleton) {
        ctx.expect('skeleton has bones', loaded.skeleton.skeleton.bones.length > 0);
        ctx.expect('bone hierarchy populated', Object.keys(loaded.skeleton.boneHierarchy).length > 0);
        ctx.log(`Skeleton: ${loaded.skeleton.skeleton.bones.length} bones, ${Object.keys(loaded.skeleton.boneHierarchy).length} in hierarchy`);
      }
      ctx.expect('load time <30s', loadMs < 30000);
    },
  },
  {
    id: 'assetmanager.release',
    name: 'AssetManager - release disposes GPU resources',
    subsystem: 'AssetManager',
    async run(ctx) {
      const manager = new AssetManager({ tempDir: `${FileSystem.cacheDirectory}am_tests/release/` });
      const desc = { id: 'release_test', version: 1, url: TEST_ASSETS.box.url, kind: 'garment' as const };
      const loaded = await manager.load(desc);
      let geomCount = 0;
      loaded.scene.traverse((obj: any) => { if (obj.isMesh) geomCount++; });
      ctx.expect('meshes present before release', geomCount > 0);
      manager.release(loaded);
      ctx.log('Released asset');
      ctx.expect('release did not throw', true);
    },
  },
];
AMTEST_EOF
echo "✓ AssetManager.test.ts"

cat > src/engine/__tests__/MeshOptimizer.test.ts << 'MOTEST_EOF'
/**
 * engine/__tests__/MeshOptimizer.test.ts
 */

import * as THREE from 'three';
import type { TestCase } from './framework/types';
import { MeshOptimizer, DEFAULT_OPTS } from '../geometry/MeshOptimizer';

function makeIcosphereGeometry(subdivisions: number): THREE.BufferGeometry {
  return new THREE.IcosahedronGeometry(1, subdivisions);
}

function countTriangles(geom: THREE.BufferGeometry): number {
  if (geom.index) return geom.index.count / 3;
  return geom.attributes.position.count / 3;
}

export const MeshOptimizerTests: TestCase[] = [
  {
    id: 'meshoptimizer.small',
    name: 'MeshOptimizer - decimate 1k-tri mesh to 500',
    subsystem: 'MeshOptimizer',
    async run(ctx) {
      const geom = makeIcosphereGeometry(4);
      const originalTris = countTriangles(geom);
      ctx.log(`Original: ${originalTris} triangles`);
      const optimizer = new MeshOptimizer();
      const stopOpt = ctx.startTimer('optimize');
      const result = optimizer.optimize(geom, { ...DEFAULT_OPTS, targetTriangles: 500 });
      const optMs = stopOpt();
      const optimizedTris = countTriangles(geom);
      ctx.log(`Optimized: ${optimizedTris} triangles in ${optMs.toFixed(0)}ms`);
      ctx.expect('original triangle count is ~1280', Math.abs(originalTris - 1280) < 100);
      ctx.expect('optimized triangle count reduced', optimizedTris < originalTris);
      ctx.expect('optimized count is in target range', optimizedTris <= 700 && optimizedTris >= 300, '300-700', `${optimizedTris}`);
      ctx.expect('optimization time <1s', optMs < 1000, '<1000ms', `${optMs.toFixed(0)}ms`);
      ctx.expect('optimization time <500ms (preferred)', optMs < 500, '<500ms', `${optMs.toFixed(0)}ms`);
      ctx.log(`>>> MeshOptimizer cost for 1k->500 tris: ${optMs.toFixed(0)}ms`);
      ctx.log(`>>> RECOMMENDATION: ${optMs > 1000 ? 'REMOVE from runtime path - too slow' : optMs > 500 ? 'Consider removing - borderline' : 'KEEP - acceptable'}`);
    },
  },
  {
    id: 'meshoptimizer.medium',
    name: 'MeshOptimizer - decimate 5k-tri mesh to 1k',
    subsystem: 'MeshOptimizer',
    async run(ctx) {
      const geom = makeIcosphereGeometry(5);
      const originalTris = countTriangles(geom);
      ctx.log(`Original: ${originalTris} triangles`);
      const optimizer = new MeshOptimizer();
      const stopOpt = ctx.startTimer('optimize');
      const result = optimizer.optimize(geom, { ...DEFAULT_OPTS, targetTriangles: 1000 });
      const optMs = stopOpt();
      const optimizedTris = countTriangles(geom);
      ctx.log(`Optimized: ${optimizedTris} triangles in ${optMs.toFixed(0)}ms`);
      ctx.expect('optimized count reduced', optimizedTris < originalTris);
      ctx.expect('optimized count near target', optimizedTris <= 1500 && optimizedTris >= 500);
      ctx.expect('optimization time <2s', optMs < 2000, '<2000ms', `${optMs.toFixed(0)}ms`);
      ctx.log(`>>> MeshOptimizer cost for 5k->1k tris: ${optMs.toFixed(0)}ms`);
      ctx.log(`>>> RECOMMENDATION: ${optMs > 2000 ? 'REMOVE from runtime path' : optMs > 1000 ? 'Use only at load time, never mid-frame' : 'Acceptable'}`);
    },
  },
  {
    id: 'meshoptimizer.large',
    name: 'MeshOptimizer - decimate 20k-tri mesh to 2k (stress test)',
    subsystem: 'MeshOptimizer',
    async run(ctx) {
      const geom = makeIcosphereGeometry(6);
      const originalTris = countTriangles(geom);
      ctx.log(`Original: ${originalTris} triangles`);
      const optimizer = new MeshOptimizer();
      const stopOpt = ctx.startTimer('optimize');
      const result = optimizer.optimize(geom, { ...DEFAULT_OPTS, targetTriangles: 2000 });
      const optMs = stopOpt();
      const optimizedTris = countTriangles(geom);
      ctx.log(`Optimized: ${optimizedTris} triangles in ${optMs.toFixed(0)}ms`);
      ctx.expect('optimized count reduced', optimizedTris < originalTris);
      ctx.log(`>>> MeshOptimizer cost for 20k->2k tris: ${optMs.toFixed(0)}ms`);
      ctx.log(`>>> RECOMMENDATION: ${optMs > 5000 ? 'REMOVE - way too slow for runtime' : optMs > 2000 ? 'Use only offline / at first-load' : 'Acceptable for background use'}`);
    },
  },
  {
    id: 'meshoptimizer.noop_when_under_target',
    name: 'MeshOptimizer - no-op when mesh is already under target',
    subsystem: 'MeshOptimizer',
    async run(ctx) {
      const geom = makeIcosphereGeometry(2);
      const originalTris = countTriangles(geom);
      const optimizer = new MeshOptimizer();
      const stopOpt = ctx.startTimer('optimize');
      const result = optimizer.optimize(geom, { ...DEFAULT_OPTS, targetTriangles: 500 });
      const optMs = stopOpt();
      ctx.expect('no-op detected (reductionRatio = 1.0)', result.reductionRatio === 1.0);
      ctx.expect('triangle count unchanged', countTriangles(geom) === originalTris);
      ctx.expect('fast (<10ms)', optMs < 10, '<10ms', `${optMs.toFixed(2)}ms`);
    },
  },
];
MOTEST_EOF
echo "✓ MeshOptimizer.test.ts"

cat > src/engine/__tests__/CameraController.test.ts << 'CCTEST_EOF'
/**
 * engine/__tests__/CameraController.test.ts
 */

import * as THREE from 'three';
import type { TestCase } from './framework/types';
import { CameraController, DEFAULT_VTO_CONSTRAINTS } from '../camera/CameraController';
import type { CameraConstraints } from '../camera/CameraConstraints';

export const CameraControllerTests: TestCase[] = [
  {
    id: 'camera.initial_state',
    name: 'CameraController - initial state matches defaults',
    subsystem: 'CameraController',
    async run(ctx) {
      const cam = new CameraController();
      const state = cam.getState();
      ctx.expect('initial yaw = 0', Math.abs(state.yaw) < 0.001);
      ctx.expect('initial pitch = 0.2', Math.abs(state.pitch - 0.2) < 0.001);
      ctx.expect('initial distance = 4', Math.abs(state.distance - 4) < 0.001);
      ctx.expect('initial targetY = 0.5', Math.abs(state.targetY - 0.5) < 0.001);
      ctx.expect('initial fov = 50', Math.abs(state.fov - 50) < 0.001);
    },
  },
  {
    id: 'camera.orbit_by',
    name: 'CameraController - orbitBy() updates target yaw/pitch',
    subsystem: 'CameraController',
    async run(ctx) {
      const cam = new CameraController();
      cam.orbitBy(0.5, 0.3);
      for (let i = 0; i < 30; i++) await cam.update(1 / 60);
      const state = cam.getState();
      ctx.expect('yaw approx 0.5 after settling', Math.abs(state.yaw - 0.5) < 0.1, '0.5+-0.1', state.yaw.toFixed(3));
      ctx.expect('pitch approx 0.5 after settling (0.2 + 0.3)', Math.abs(state.pitch - 0.5) < 0.1, '0.5+-0.1', state.pitch.toFixed(3));
    },
  },
  {
    id: 'camera.pitch_clamped',
    name: 'CameraController - pitch is clamped to +/-75deg',
    subsystem: 'CameraController',
    async run(ctx) {
      const cam = new CameraController();
      cam.orbitBy(0, 10);
      for (let i = 0; i < 60; i++) await cam.update(1 / 60);
      const state = cam.getState();
      const maxPitch = DEFAULT_VTO_CONSTRAINTS.pitchRange[1];
      ctx.expect(`pitch <= ${maxPitch.toFixed(3)}`, state.pitch <= maxPitch + 0.001, `<=${maxPitch.toFixed(3)}`, state.pitch.toFixed(3));
      ctx.expect('pitch >= -maxPitch', state.pitch >= -maxPitch - 0.001);
    },
  },
  {
    id: 'camera.distance_clamped',
    name: 'CameraController - zoom is clamped to [1.5, 8]',
    subsystem: 'CameraController',
    async run(ctx) {
      const cam = new CameraController();
      cam.zoomBy(0.001);
      for (let i = 0; i < 30; i++) await cam.update(1 / 60);
      let state = cam.getState();
      ctx.expect('distance >= 1.5 (min)', state.distance >= 1.5 - 0.001, '>=1.5', state.distance.toFixed(3));
      cam.zoomBy(100);
      for (let i = 0; i < 30; i++) await cam.update(1 / 60);
      state = cam.getState();
      ctx.expect('distance <= 8 (max)', state.distance <= 8 + 0.001, '<=8', state.distance.toFixed(3));
    },
  },
  {
    id: 'camera.damping',
    name: 'CameraController - damping smooths current toward target',
    subsystem: 'CameraController',
    async run(ctx) {
      const cam = new CameraController();
      cam.orbitBy(1.0, 0);
      await cam.update(1 / 60);
      const state1 = cam.getState();
      ctx.expect('yaw not yet at target after 1 frame', state1.yaw < 0.5, '<0.5', state1.yaw.toFixed(3));
      ctx.expect('yaw has moved toward target', state1.yaw > 0.01, '>0.01', state1.yaw.toFixed(3));
      for (let i = 0; i < 60; i++) await cam.update(1 / 60);
      const state60 = cam.getState();
      ctx.expect('yaw approx 1.0 after 1 sec', Math.abs(state60.yaw - 1.0) < 0.05, '1.0+-0.05', state60.yaw.toFixed(3));
    },
  },
  {
    id: 'camera.focus_on',
    name: 'CameraController - focusOn() moves target',
    subsystem: 'CameraController',
    async run(ctx) {
      const cam = new CameraController();
      cam.focusOn({ x: 1, y: 2, z: 3 });
      for (let i = 0; i < 60; i++) await cam.update(1 / 60);
      const state = cam.getState();
      ctx.expect('targetX approx 1', Math.abs(state.targetX - 1) < 0.05, '1+-0.05', state.targetX.toFixed(3));
      ctx.expect('targetY approx 2', Math.abs(state.targetY - 2) < 0.05);
      ctx.expect('targetZ approx 3', Math.abs(state.targetZ - 3) < 0.05);
    },
  },
  {
    id: 'camera.focus_on_immediate',
    name: 'CameraController - focusOn(smooth=false) snaps immediately',
    subsystem: 'CameraController',
    async run(ctx) {
      const cam = new CameraController();
      cam.focusOn({ x: 5, y: 5, z: 5 }, false);
      const state = cam.getState();
      ctx.expect('targetX = 5 immediately', state.targetX === 5, '5', `${state.targetX}`);
      ctx.expect('targetY = 5 immediately', state.targetY === 5);
      ctx.expect('targetZ = 5 immediately', state.targetZ === 5);
    },
  },
  {
    id: 'camera.reset',
    name: 'CameraController - reset() restores defaults',
    subsystem: 'CameraController',
    async run(ctx) {
      const cam = new CameraController();
      cam.orbitBy(1, 1);
      cam.zoomBy(0.5);
      for (let i = 0; i < 30; i++) await cam.update(1 / 60);
      cam.reset();
      for (let i = 0; i < 60; i++) await cam.update(1 / 60);
      const state = cam.getState();
      ctx.expect('yaw back to 0', Math.abs(state.yaw) < 0.05);
      ctx.expect('pitch back to 0.2', Math.abs(state.pitch - 0.2) < 0.05);
      ctx.expect('distance back to 4', Math.abs(state.distance - 4) < 0.05);
    },
  },
  {
    id: 'camera.apply_to_three_camera',
    name: 'CameraController - apply() positions a THREE.PerspectiveCamera',
    subsystem: 'CameraController',
    async run(ctx) {
      const cam = new CameraController();
      cam.focusOn({ x: 0, y: 0, z: 0 }, false);
      cam.reset();
      for (let i = 0; i < 60; i++) await cam.update(1 / 60);
      const threeCam = new THREE.PerspectiveCamera(50, 1, 0.1, 1000);
      cam.apply(threeCam);
      const dist = Math.sqrt(threeCam.position.x ** 2 + threeCam.position.y ** 2 + threeCam.position.z ** 2);
      ctx.expect('camera is at distance 4 from origin', Math.abs(dist - 4) < 0.1, '4+-0.1', dist.toFixed(3));
      ctx.expect('camera is finite position', isFinite(threeCam.position.x) && isFinite(threeCam.position.y) && isFinite(threeCam.position.z));
    },
  },
  {
    id: 'camera.custom_constraints',
    name: 'CameraController - custom constraints respected',
    subsystem: 'CameraController',
    async run(ctx) {
      const tightConstraints: CameraConstraints = {
        ...DEFAULT_VTO_CONSTRAINTS,
        distanceRange: [3, 5],
        pitchRange: [0, 0],
      };
      const cam = new CameraController({ constraints: tightConstraints });
      cam.orbitBy(0, 1);
      cam.zoomBy(0.1);
      for (let i = 0; i < 60; i++) await cam.update(1 / 60);
      const state = cam.getState();
      ctx.expect('pitch stayed at 0 (locked)', Math.abs(state.pitch) < 0.01, '0+-0.01', state.pitch.toFixed(3));
      ctx.expect('distance stayed >= 3', state.distance >= 3 - 0.01);
      ctx.expect('distance stayed <= 5', state.distance <= 5 + 0.01);
    },
  },
];

function isFinite(n: number): boolean {
  return typeof n === 'number' && globalThis.isFinite(n);
}
CCTEST_EOF
echo "✓ CameraController.test.ts"

cat > src/engine/__tests__/LODSystem.test.ts << 'LODTEST_EOF'
/**
 * engine/__tests__/LODSystem.test.ts
 */

import * as THREE from 'three';
import type { TestCase } from './framework/types';
import { LODSystem } from '../geometry/LODSystem';
import type { LoadedAsset, AssetDescriptor, BBox } from '../core/types';

function makeFakeAsset(id: string): LoadedAsset {
  const group = new THREE.Group();
  const geom = new THREE.BoxGeometry(0.1, 0.1, 0.1);
  const mat = new THREE.MeshBasicMaterial();
  group.add(new THREE.Mesh(geom, mat));
  const bbox: BBox = {
    min: { x: -0.05, y: -0.05, z: -0.05 },
    max: { x: 0.05, y: 0.05, z: 0.05 },
    center: { x: 0, y: 0, z: 0 },
    size: { x: 0.1, y: 0.1, z: 0.1 },
  };
  const descriptor: AssetDescriptor = { id, version: 1, url: `http://test/${id}.glb`, kind: 'garment' };
  return {
    descriptor, scene: group, bbox,
    stats: { meshCount: 1, triangleCount: 12, vertexCount: 8, materialCount: 1, textureCount: 0, estimatedMemoryBytes: 384 },
    skeleton: null, activeLOD: 'high', localPath: '', loadTimeMs: 0,
  };
}

export const LODSystemTests: TestCase[] = [
  {
    id: 'lod.register_and_activate',
    name: 'LODSystem - register() activates the first variant',
    subsystem: 'LODSystem',
    async run(ctx) {
      const lod = new LODSystem();
      const asset = makeFakeAsset('test1');
      const group = lod.register('test1', 'high', asset);
      ctx.expect('LODGroup created', group !== null);
      ctx.expect('container is a THREE.Group', group.container instanceof THREE.Group);
      ctx.expect('currentLevel is "high"', group.currentLevel === 'high');
      ctx.expect('variant is active', group.variants.get('high')?.isActive === true);
      ctx.expect('variant scene added to container', group.container.children.includes(asset.scene));
    },
  },
  {
    id: 'lod.distance_switch_high_to_medium',
    name: 'LODSystem - at distance 6 -> switches to medium',
    subsystem: 'LODSystem',
    async run(ctx) {
      const lod = new LODSystem();
      lod.register('test2', 'high', makeFakeAsset('test2_high'));
      lod.register('test2', 'medium', makeFakeAsset('test2_med'));
      lod.update(new THREE.Vector3(0, 0, 0), 1 / 60);
      let group = lod.getGroups()[0];
      ctx.expect('at distance 0: high LOD', group.currentLevel === 'high', 'high', group.currentLevel);
      lod.update(new THREE.Vector3(0, 0, 6), 1 / 60);
      group = lod.getGroups()[0];
      ctx.expect('at distance 6: medium LOD', group.currentLevel === 'medium', 'medium', group.currentLevel);
    },
  },
  {
    id: 'lod.distance_switch_medium_to_low',
    name: 'LODSystem - at distance 12 -> switches to low',
    subsystem: 'LODSystem',
    async run(ctx) {
      const lod = new LODSystem();
      lod.register('test3', 'high', makeFakeAsset('test3_high'));
      lod.register('test3', 'medium', makeFakeAsset('test3_med'));
      lod.register('test3', 'low', makeFakeAsset('test3_low'));
      lod.update(new THREE.Vector3(0, 0, 12), 1 / 60);
      const group = lod.getGroups()[0];
      ctx.expect('at distance 12: low LOD', group.currentLevel === 'low', 'low', group.currentLevel);
    },
  },
  {
    id: 'lod.hysteresis',
    name: 'LODSystem - hysteresis prevents rapid flipping at boundary',
    subsystem: 'LODSystem',
    async run(ctx) {
      const lod = new LODSystem();
      lod.register('test4', 'high', makeFakeAsset('test4_high'));
      lod.register('test4', 'medium', makeFakeAsset('test4_med'));
      lod.update(new THREE.Vector3(0, 0, 3), 1 / 60);
      let group = lod.getGroups()[0];
      ctx.expect('at distance 3: high LOD', group.currentLevel === 'high');
      lod.update(new THREE.Vector3(0, 0, 4.05), 1 / 60);
      group = lod.getGroups()[0];
      ctx.expect('at distance 4.05 (hysteresis zone): still high', group.currentLevel === 'high', 'high', group.currentLevel);
      lod.update(new THREE.Vector3(0, 0, 4.7), 1 / 60);
      group = lod.getGroups()[0];
      ctx.expect('at distance 4.7 (past hysteresis): medium', group.currentLevel === 'medium', 'medium', group.currentLevel);
    },
  },
  {
    id: 'lod.force_lod',
    name: 'LODSystem - forceLOD() overrides distance-based selection',
    subsystem: 'LODSystem',
    async run(ctx) {
      const lod = new LODSystem();
      lod.register('test5', 'high', makeFakeAsset('test5_high'));
      lod.register('test5', 'medium', makeFakeAsset('test5_med'));
      lod.update(new THREE.Vector3(0, 0, 1), 1 / 60);
      lod.forceLOD('test5', 'medium');
      const group = lod.getGroups()[0];
      ctx.expect('forceLOD medium at distance 1', group.currentLevel === 'medium');
    },
  },
  {
    id: 'lod.unregister',
    name: 'LODSystem - unregister() removes the group',
    subsystem: 'LODSystem',
    async run(ctx) {
      const lod = new LODSystem();
      lod.register('test6', 'high', makeFakeAsset('test6_high'));
      ctx.expect('group registered', lod.getGroups().length === 1);
      lod.unregister('test6');
      ctx.expect('group unregistered', lod.getGroups().length === 0);
    },
  },
  {
    id: 'lod.stats_histogram',
    name: 'LODSystem - getStats() returns correct histogram',
    subsystem: 'LODSystem',
    async run(ctx) {
      const lod = new LODSystem();
      lod.register('g1', 'high', makeFakeAsset('g1_high'));
      lod.register('g2', 'high', makeFakeAsset('g2_high'));
      lod.register('g3', 'high', makeFakeAsset('g3_high'));
      lod.register('g1', 'medium', makeFakeAsset('g1_med'));
      lod.register('g2', 'medium', makeFakeAsset('g2_med'));
      lod.register('g3', 'medium', makeFakeAsset('g3_med'));
      lod.register('g1', 'low', makeFakeAsset('g1_low'));
      lod.register('g2', 'low', makeFakeAsset('g2_low'));
      lod.register('g3', 'low', makeFakeAsset('g3_low'));
      lod.update(new THREE.Vector3(0, 0, 6), 1 / 60);
      const stats = lod.getStats();
      ctx.expect('groupCount = 3', stats.groupCount === 3);
      ctx.expect('all 3 at medium', stats.histogram.medium === 3, '3', `${stats.histogram.medium}`);
      ctx.expect('totalVariants = 9', stats.totalVariants === 9);
    },
  },
];
LODTEST_EOF
echo "✓ LODSystem.test.ts"

cat > src/engine/__tests__/PerformanceProfiler.test.ts << 'PPTEST_EOF'
/**
 * engine/__tests__/PerformanceProfiler.test.ts
 */

import type { TestCase } from './framework/types';
import { PerformanceProfiler } from '../debug/PerformanceProfiler';

function makeFakeRenderer(): any {
  return {
    info: {
      render: { calls: 5, triangles: 1000, lines: 0, points: 0 },
      memory: { geometries: 3, textures: 2 },
      programs: [{}, {}],
    },
  };
}

export const PerformanceProfilerTests: TestCase[] = [
  {
    id: 'profiler.basic_frame',
    name: 'PerformanceProfiler - endFrame returns FrameStats',
    subsystem: 'PerformanceProfiler',
    async run(ctx) {
      const prof = new PerformanceProfiler();
      const fakeRenderer = makeFakeRenderer();
      prof.beginFrame();
      await sleep(16);
      prof.endFrame(fakeRenderer, { animationTimeMs: 2, gpuMemoryBytes: 1024 * 1024 });
      const stats = prof.getLatest();
      ctx.expect('frameNumber = 1', stats.frameNumber === 1);
      ctx.expect('frameTimeMs > 0', stats.frameTimeMs > 0);
      ctx.expect('fps > 0', stats.fps > 0);
      ctx.expect('drawCalls = 5', stats.drawCalls === 5);
      ctx.expect('triangles = 1000', stats.triangles === 1000);
      ctx.expect('geometries = 3', stats.geometries === 3);
      ctx.expect('textures = 2', stats.textures === 2);
      ctx.expect('programs = 2', stats.programs === 2);
      ctx.expect('animationTimeMs = 2', stats.animationTimeMs === 2);
      ctx.expect('estimatedGpuMemoryMB approx 1', Math.abs(stats.estimatedGpuMemoryMB - 1) < 0.01);
    },
  },
  {
    id: 'profiler.rolling_stats',
    name: 'PerformanceProfiler - getRollingStats() averages over 60 frames',
    subsystem: 'PerformanceProfiler',
    async run(ctx) {
      const prof = new PerformanceProfiler();
      const fakeRenderer = makeFakeRenderer();
      for (let i = 0; i < 10; i++) {
        prof.beginFrame();
        await sleep(10);
        prof.endFrame(fakeRenderer);
      }
      const rolling = prof.getRollingStats();
      ctx.expect('sampleCount = 10', rolling.sampleCount === 10);
      ctx.expect('fpsAvg > 0', rolling.fpsAvg > 0);
      ctx.expect('frameTimeAvgMs > 0', rolling.frameTimeAvgMs > 0);
      ctx.expect('frameTimeMinMs <= frameTimeMaxMs', rolling.frameTimeMinMs <= rolling.frameTimeMaxMs);
      ctx.expect('drawCallsAvg = 5', rolling.drawCallsAvg === 5);
      ctx.expect('trianglesAvg = 1000', rolling.trianglesAvg === 1000);
    },
  },
  {
    id: 'profiler.fps_calculation',
    name: 'PerformanceProfiler - FPS = 1000 / frameTimeMs',
    subsystem: 'PerformanceProfiler',
    async run(ctx) {
      const prof = new PerformanceProfiler();
      const fakeRenderer = makeFakeRenderer();
      prof.beginFrame();
      await sleep(16);
      prof.endFrame(fakeRenderer);
      const stats = prof.getLatest();
      const expectedFps = 1000 / stats.frameTimeMs;
      ctx.expect('fps approx 1000 / frameTimeMs', Math.abs(stats.fps - expectedFps) < 1, `${expectedFps.toFixed(1)}`, stats.fps.toFixed(1));
    },
  },
  {
    id: 'profiler.subscriber',
    name: 'PerformanceProfiler - subscribe() called every N frames',
    subsystem: 'PerformanceProfiler',
    async run(ctx) {
      const prof = new PerformanceProfiler();
      const fakeRenderer = makeFakeRenderer();
      let callCount = 0;
      const unsub = prof.subscribe(() => { callCount++; }, 5);
      for (let i = 0; i < 12; i++) {
        prof.beginFrame();
        prof.endFrame(fakeRenderer);
      }
      ctx.expect('subscriber called 2 times (every 5 frames, 12 total)', callCount === 2, '2', `${callCount}`);
      unsub();
      for (let i = 0; i < 10; i++) {
        prof.beginFrame();
        prof.endFrame(fakeRenderer);
      }
      ctx.expect('subscriber not called after unsub', callCount === 2);
    },
  },
  {
    id: 'profiler.reset',
    name: 'PerformanceProfiler - reset() clears history',
    subsystem: 'PerformanceProfiler',
    async run(ctx) {
      const prof = new PerformanceProfiler();
      const fakeRenderer = makeFakeRenderer();
      for (let i = 0; i < 5; i++) {
        prof.beginFrame();
        prof.endFrame(fakeRenderer);
      }
      ctx.expect('frameCount = 5 before reset', prof.getLatest().frameNumber === 5);
      prof.reset();
      ctx.expect('frameCount = 0 after reset', prof.getLatest().frameNumber === 0);
      ctx.expect('rolling sampleCount = 0', prof.getRollingStats().sampleCount === 0);
    },
  },
];

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}
PPTEST_EOF
echo "✓ PerformanceProfiler.test.ts"

cat > src/engine/__tests__/TextureManager.test.ts << 'TMTEST_EOF'
/**
 * engine/__tests__/TextureManager.test.ts
 */

import * as THREE from 'three';
import type { TestCase } from './framework/types';
import { TextureManager } from '../textures/TextureManager';
import type { TextureRef } from '../core/types';

const TINY_PNG_DATA_URI = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';

function makeTextureRef(cacheKey: string): TextureRef {
  return { cacheKey, uri: TINY_PNG_DATA_URI, maxResolution: 64, colorSpace: 'srgb', wrapS: 'clamp', wrapT: 'clamp' };
}

export const TextureManagerTests: TestCase[] = [
  {
    id: 'texturemgr.acquire_release',
    name: 'TextureManager - acquire + release frees texture at refcount 0',
    subsystem: 'TextureManager',
    async run(ctx) {
      const mgr = new TextureManager({ maxTotalBytes: 100 * 1024 * 1024 });
      const ref = makeTextureRef('test1');
      ctx.log('Acquiring texture...');
      const tex1 = await mgr.acquire(ref);
      ctx.expect('texture returned', tex1 instanceof THREE.Texture);
      const mem1 = mgr.getMemoryUsage();
      ctx.expect('memory usage > 0 after acquire', mem1.bytes > 0);
      ctx.expect('count = 1', mem1.count === 1);
      ctx.log('Releasing...');
      mgr.release(ref);
      const mem2 = mgr.getMemoryUsage();
      ctx.expect('count = 0 after release', mem2.count === 0);
    },
  },
  {
    id: 'texturemgr.refcount_shared',
    name: 'TextureManager - multiple acquires share same texture instance',
    subsystem: 'TextureManager',
    async run(ctx) {
      const mgr = new TextureManager();
      const ref = makeTextureRef('shared_test');
      const tex1 = await mgr.acquire(ref);
      const tex2 = await mgr.acquire(ref);
      const tex3 = await mgr.acquire(ref);
      ctx.expect('all 3 acquires return SAME instance', tex1 === tex2 && tex2 === tex3);
      mgr.release(ref);
      mgr.release(ref);
      ctx.expect('count = 1 after 2 releases (3 acquires)', mgr.getMemoryUsage().count === 1);
      mgr.release(ref);
      ctx.expect('count = 0 after 3rd release', mgr.getMemoryUsage().count === 0);
    },
  },
  {
    id: 'texturemgr.dedupe_concurrent',
    name: 'TextureManager - concurrent acquires for same key are deduped',
    subsystem: 'TextureManager',
    async run(ctx) {
      const mgr = new TextureManager();
      const ref = makeTextureRef('concurrent_test');
      const promises = [mgr.acquire(ref), mgr.acquire(ref), mgr.acquire(ref), mgr.acquire(ref), mgr.acquire(ref)];
      const textures = await Promise.all(promises);
      ctx.expect('all 5 resolved', textures.length === 5);
      ctx.expect('all 5 are the same instance', textures.every((t) => t === textures[0]));
      ctx.expect('count = 1 (deduped)', mgr.getMemoryUsage().count === 1);
      for (let i = 0; i < 5; i++) mgr.release(ref);
    },
  },
  {
    id: 'texturemgr.dispose_all',
    name: 'TextureManager - disposeAll() clears everything',
    subsystem: 'TextureManager',
    async run(ctx) {
      const mgr = new TextureManager();
      await mgr.acquire(makeTextureRef('a'));
      await mgr.acquire(makeTextureRef('b'));
      await mgr.acquire(makeTextureRef('c'));
      ctx.expect('count = 3 after 3 acquires', mgr.getMemoryUsage().count === 3);
      mgr.disposeAll();
      ctx.expect('count = 0 after disposeAll', mgr.getMemoryUsage().count === 0);
    },
  },
];
TMTEST_EOF
echo "✓ TextureManager.test.ts"

cat > src/engine/__tests__/SkeletonDetector.test.ts << 'SDTEST_EOF'
/**
 * engine/__tests__/SkeletonDetector.test.ts
 */

import * as THREE from 'three';
import type { TestCase } from './framework/types';
import { SkeletonDetector } from '../skeleton/SkeletonDetector';

function makeFakeRiggedFigure(): THREE.Object3D {
  const root = new THREE.Object3D();
  const armature = new THREE.Group();
  armature.name = 'Armature';
  root.add(armature);

  const hips = new THREE.Bone();
  hips.name = 'Hips';
  hips.position.set(0, 1, 0);
  armature.add(hips);

  const spine = new THREE.Bone();
  spine.name = 'Spine';
  spine.position.set(0, 0.3, 0);
  hips.add(spine);

  const neck = new THREE.Bone();
  neck.name = 'Neck';
  neck.position.set(0, 0.3, 0);
  spine.add(neck);

  const head = new THREE.Bone();
  head.name = 'Head';
  head.position.set(0, 0.15, 0);
  neck.add(head);

  const leftArm = new THREE.Bone();
  leftArm.name = 'LeftArm';
  leftArm.position.set(0.2, 0, 0);
  neck.add(leftArm);

  const rightArm = new THREE.Bone();
  rightArm.name = 'RightArm';
  rightArm.position.set(-0.2, 0, 0);
  neck.add(rightArm);

  const leftLeg = new THREE.Bone();
  leftLeg.name = 'LeftUpLeg';
  leftLeg.position.set(0.1, -0.5, 0);
  hips.add(leftLeg);

  const rightLeg = new THREE.Bone();
  rightLeg.name = 'RightUpLeg';
  rightLeg.position.set(-0.1, -0.5, 0);
  hips.add(rightLeg);

  const bones = [hips, spine, neck, head, leftArm, rightArm, leftLeg, rightLeg];
  const skeleton = new THREE.Skeleton(bones);
  armature.add(new THREE.SkeletonHelper(hips));

  const geom = new THREE.BoxGeometry(0.1, 0.1, 0.1);
  const mat = new THREE.MeshStandardMaterial();
  const skinned = new THREE.SkinnedMesh(geom, mat);
  skinned.add(hips);
  skinned.bind(skeleton);
  armature.add(skinned);

  return root;
}

export const SkeletonDetectorTests: TestCase[] = [
  {
    id: 'skeleton.detect_from_skinned_mesh',
    name: 'SkeletonDetector - extracts skeleton from SkinnedMesh',
    subsystem: 'SkeletonDetector',
    async run(ctx) {
      const detector = new SkeletonDetector();
      const root = makeFakeRiggedFigure();
      const skeleton = detector.detect(root);
      ctx.expect('skeleton returned (not null)', skeleton !== null);
      if (!skeleton) return;
      ctx.expect('THREE.Skeleton object present', skeleton.skeleton instanceof THREE.Skeleton);
      ctx.expect('8 bones detected', skeleton.skeleton.bones.length === 8, '8', `${skeleton.skeleton.bones.length}`);
      ctx.expect('8 entries in boneHierarchy', Object.keys(skeleton.boneHierarchy).length === 8);
      ctx.expect('8 entries in bindPose', Object.keys(skeleton.bindPose).length === 8);
      ctx.expect('8 entries in boneLengths', Object.keys(skeleton.boneLengths).length === 8);
    },
  },
  {
    id: 'skeleton.find_skinned_mesh',
    name: 'SkeletonDetector - findSkinnedMesh() locates the first SkinnedMesh',
    subsystem: 'SkeletonDetector',
    async run(ctx) {
      const detector = new SkeletonDetector();
      const root = makeFakeRiggedFigure();
      const skinned = detector.findSkinnedMesh(root);
      ctx.expect('SkinnedMesh found', skinned !== null);
      ctx.expect('is a THREE.SkinnedMesh', skinned instanceof THREE.SkinnedMesh);
    },
  },
  {
    id: 'skeleton.normalize_name',
    name: 'SkeletonDetector - normalizeBoneName() strips Mixamo prefixes',
    subsystem: 'SkeletonDetector',
    async run(ctx) {
      const detector = new SkeletonDetector();
      ctx.expect('"mixamorig:Head" -> "Head"', detector.normalizeBoneName('mixamorig:Head') === 'Head');
      ctx.expect('"Armature|Spine" -> "Spine"', detector.normalizeBoneName('Armature|Spine') === 'Spine');
      ctx.expect('"Hips" -> "Hips" (no prefix)', detector.normalizeBoneName('Hips') === 'Hips');
    },
  },
  {
    id: 'skeleton.no_skeleton_returns_null',
    name: 'SkeletonDetector - returns null when no skeleton present',
    subsystem: 'SkeletonDetector',
    async run(ctx) {
      const detector = new SkeletonDetector();
      const root = new THREE.Object3D();
      const mesh = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1), new THREE.MeshBasicMaterial());
      root.add(mesh);
      const skeleton = detector.detect(root);
      ctx.expect('returns null (no skinned mesh, no bones)', skeleton === null);
    },
  },
];
SDTEST_EOF
echo "✓ SkeletonDetector.test.ts"

echo ""
echo "=== Part 7b: TestRegistry + TestRunner UI ==="

cat > src/engine/__tests__/framework/TestRegistry.ts << 'TESTREGISTRY_EOF'
/**
 * engine/__tests__/framework/TestRegistry.ts
 */

import type { TestCase, SubsystemName } from './types';
import { TextureLoaderTests } from '../TextureLoader.test';
import { AssetValidatorTests } from '../AssetValidator.test';
import { CacheManagerTests } from '../CacheManager.test';
import { AssetManagerTests } from '../AssetManager.test';
import { MeshOptimizerTests } from '../MeshOptimizer.test';
import { CameraControllerTests } from '../CameraController.test';
import { LODSystemTests } from '../LODSystem.test';
import { PerformanceProfilerTests } from '../PerformanceProfiler.test';
import { TextureManagerTests } from '../TextureManager.test';
import { SkeletonDetectorTests } from '../SkeletonDetector.test';

const ALL_TESTS: TestCase[] = [
  ...TextureLoaderTests,
  ...AssetValidatorTests,
  ...CacheManagerTests,
  ...AssetManagerTests,
  ...MeshOptimizerTests,
  ...CameraControllerTests,
  ...LODSystemTests,
  ...PerformanceProfilerTests,
  ...TextureManagerTests,
  ...SkeletonDetectorTests,
];

export function getAllTests(): TestCase[] { return ALL_TESTS; }
export function getTestsBySubsystem(subsystem: SubsystemName): TestCase[] {
  return ALL_TESTS.filter((t) => t.subsystem === subsystem);
}
export function getTestById(id: string): TestCase | undefined {
  return ALL_TESTS.find((t) => t.id === id);
}
export function listSubsystems(): SubsystemName[] {
  const set = new Set<SubsystemName>(ALL_TESTS.map((t) => t.subsystem));
  return Array.from(set).sort();
}
TESTREGISTRY_EOF
echo "✓ framework/TestRegistry.ts"

cat > src/engine/__tests__/framework/TestRunner.tsx << 'TESTRUNNER_EOF'
/**
 * engine/__tests__/framework/TestRunner.tsx
 *
 * On-device UI for running tests and viewing results.
 */

import React, { useState, useRef, useCallback } from 'react';
import {
  View, Text, TouchableOpacity, StyleSheet, ScrollView,
  ActivityIndicator, Share, Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import type { TestResult, TestReport, SubsystemName } from './types';
import { runTest } from './TestHarness';
import { buildReport, renderReport, reportToJson } from './TestReport';
import { getAllTests, getTestsBySubsystem, listSubsystems } from './TestRegistry';

const TAG = '[TestRunner]';

const STATUS_ICON: Record<TestResult['status'], string> = {
  pass: 'OK', fail: 'XX', skipped: 'SKIP', running: '...', pending: '-',
};

const STATUS_COLOR: Record<TestResult['status'], string> = {
  pass: '#00FF66', fail: '#FF5252', skipped: '#888', running: '#FFB74D', pending: '#666',
};

export function TestRunnerScreen() {
  const [results, setResults] = useState<Map<string, TestResult>>(new Map());
  const [running, setRunning] = useState<Set<string>>(new Set());
  const [report, setReport] = useState<TestReport | null>(null);
  const [liveLog, setLiveLog] = useState<string[]>([]);
  const scrollRef = useRef<ScrollView>(null);

  const allTests = getAllTests();
  const subsystems = listSubsystems();

  const updateResult = useCallback((id: string, result: TestResult) => {
    setResults((prev) => {
      const next = new Map(prev);
      next.set(id, result);
      return next;
    });
    setRunning((prev) => {
      const next = new Set(prev);
      next.delete(id);
      return next;
    });
  }, []);

  const runSingleTest = useCallback(async (testId: string) => {
    const test = allTests.find((t) => t.id === testId);
    if (!test) return;
    setRunning((prev) => new Set(prev).add(testId));
    setLiveLog((prev) => [...prev, `\n=== ${test.id} ===`]);

    const origLog = console.log;
    console.log = (...args: any[]) => {
      const msg = args.map((a) => typeof a === 'string' ? a : JSON.stringify(a)).join(' ');
      if (msg.includes(test.id) || msg.includes('[TestHarness]')) {
        setLiveLog((prev) => [...prev, msg]);
      }
      origLog.apply(console, args as any);
    };

    try {
      const result = await runTest(test);
      updateResult(testId, result);
      setLiveLog((prev) => [...prev, `${STATUS_ICON[result.status]} ${test.id}: ${result.status} (${result.durationMs}ms)`]);
    } finally {
      console.log = origLog;
    }
  }, [allTests, updateResult]);

  const runSubsystem = useCallback(async (subsystem: SubsystemName) => {
    const tests = getTestsBySubsystem(subsystem);
    for (const t of tests) await runSingleTest(t.id);
  }, [runSingleTest]);

  const runAll = useCallback(async () => {
    setReport(null);
    setLiveLog([]);
    for (const t of allTests) await runSingleTest(t.id);
    setResults((prevResults) => {
      const allResults = Array.from(prevResults.values());
      const r = buildReport(allResults);
      setReport(r);
      return prevResults;
    });
  }, [allTests, runSingleTest]);

  const shareReport = useCallback(async () => {
    if (!report) return;
    const text = renderReport(report);
    try { await Share.share({ message: text, title: 'VTO Engine Benchmark Report' }); }
    catch (e) { console.warn(TAG, 'share failed:', e); }
  }, [report]);

  const copyReportJson = useCallback(() => {
    if (!report) return;
    const json = reportToJson(report);
    if (Platform.OS === 'web') {
      navigator.clipboard?.writeText(json);
    } else {
      const Clipboard = require('expo-clipboard');
      Clipboard?.default?.setStringAsync?.(json) ?? Clipboard?.setStringAsync?.(json);
    }
    setLiveLog((prev) => [...prev, 'Report JSON copied to clipboard']);
  }, [report]);

  const passedCount = Array.from(results.values()).filter((r) => r.status === 'pass').length;
  const failedCount = Array.from(results.values()).filter((r) => r.status === 'fail').length;
  const totalCount = allTests.length;

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>Engine Verification</Text>
        <View style={styles.summaryRow}>
          <Text style={styles.summaryText}>
            <Text style={{ color: '#00FF66' }}>{passedCount} OK</Text>
            {'  '}
            <Text style={{ color: '#FF5252' }}>{failedCount} XX</Text>
            {'  '}
            <Text style={{ color: '#888' }}>{totalCount - passedCount - failedCount} -</Text>
            {'  /  '}
            {totalCount} total
          </Text>
        </View>
      </View>

      <View style={styles.actionRow}>
        <TouchableOpacity
          style={[styles.button, styles.primaryButton, running.size > 0 && styles.buttonDisabled]}
          onPress={runAll}
          disabled={running.size > 0}
        >
          <Text style={styles.buttonText}>Run All Tests</Text>
        </TouchableOpacity>
        <TouchableOpacity style={[styles.button, !report && styles.buttonDisabled]} onPress={shareReport} disabled={!report}>
          <Text style={styles.buttonText}>Share Report</Text>
        </TouchableOpacity>
        <TouchableOpacity style={[styles.button, !report && styles.buttonDisabled]} onPress={copyReportJson} disabled={!report}>
          <Text style={styles.buttonText}>Copy JSON</Text>
        </TouchableOpacity>
      </View>

      <ScrollView style={styles.testList}>
        {subsystems.map((subsystem) => {
          const tests = getTestsBySubsystem(subsystem);
          const subPassed = tests.filter((t) => results.get(t.id)?.status === 'pass').length;
          const subFailed = tests.filter((t) => results.get(t.id)?.status === 'fail').length;
          return (
            <View key={subsystem} style={styles.subsystemSection}>
              <View style={styles.subsystemHeader}>
                <Text style={styles.subsystemTitle}>{subsystem}</Text>
                <Text style={styles.subsystemStats}>{subPassed} OK {subFailed} XX / {tests.length}</Text>
                <TouchableOpacity style={styles.subsystemRunBtn} onPress={() => runSubsystem(subsystem)} disabled={running.size > 0}>
                  <Text style={styles.subsystemRunText}>Run</Text>
                </TouchableOpacity>
              </View>
              {tests.map((test) => {
                const result = results.get(test.id);
                const isRunning = running.has(test.id);
                return (
                  <TouchableOpacity key={test.id} style={styles.testRow} onPress={() => runSingleTest(test.id)} disabled={isRunning}>
                    <Text style={[styles.testIcon, { color: STATUS_COLOR[result?.status ?? 'pending'] }]}>
                      {isRunning ? '...' : STATUS_ICON[result?.status ?? 'pending']}
                    </Text>
                    <View style={styles.testInfo}>
                      <Text style={styles.testName}>{test.name}</Text>
                      <Text style={styles.testId}>{test.id}</Text>
                      {result && (
                        <Text style={styles.testDuration}>
                          {result.durationMs}ms | {result.assertions.length} assertions
                          {result.metrics.custom && Object.keys(result.metrics.custom).length > 0 && (
                            <> | {Object.entries(result.metrics.custom).map(([k, v]) => `${k}=${v}`).join(', ')}</>
                          )}
                        </Text>
                      )}
                      {result?.error && <Text style={styles.testError}>! {result.error}</Text>}
                    </View>
                    {isRunning && <ActivityIndicator size="small" color="#6C63FF" />}
                  </TouchableOpacity>
                );
              })}
            </View>
          );
        })}
      </ScrollView>

      {liveLog.length > 0 && (
        <View style={styles.logPanel}>
          <View style={styles.logHeader}>
            <Text style={styles.logTitle}>Live Log ({liveLog.length} lines)</Text>
            <TouchableOpacity onPress={() => setLiveLog([])}>
              <Text style={styles.logClear}>Clear</Text>
            </TouchableOpacity>
          </View>
          <ScrollView
            ref={scrollRef}
            style={styles.logScroll}
            onContentSizeChange={(_, h) => scrollRef.current?.scrollTo({ y: h, animated: false })}
          >
            {liveLog.map((line, i) => <Text key={i} style={styles.logLine}>{line}</Text>)}
          </ScrollView>
        </View>
      )}

      {report && (
        <View style={styles.reportPanel}>
          <Text style={styles.reportTitle}>Benchmark Report</Text>
          <ScrollView style={styles.reportScroll}>
            <Text style={styles.reportText}>{renderReport(report)}</Text>
          </ScrollView>
        </View>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0F0F0F' },
  header: { padding: 16, borderBottomWidth: 1, borderBottomColor: '#222' },
  title: { color: '#FFF', fontSize: 22, fontWeight: '800' },
  summaryRow: { marginTop: 4 },
  summaryText: { color: '#CCC', fontSize: 14 },
  actionRow: { flexDirection: 'row', gap: 8, padding: 12, backgroundColor: '#111' },
  button: { flex: 1, paddingVertical: 10, paddingHorizontal: 12, backgroundColor: '#1E1E1E', borderRadius: 8, alignItems: 'center', borderWidth: 1, borderColor: '#333' },
  primaryButton: { backgroundColor: '#6C63FF', borderColor: '#6C63FF' },
  buttonText: { color: '#FFF', fontSize: 13, fontWeight: '600' },
  buttonDisabled: { backgroundColor: '#222', borderColor: '#222' },
  testList: { flex: 1, padding: 12 },
  subsystemSection: { marginBottom: 16 },
  subsystemHeader: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingVertical: 6, borderBottomWidth: 1, borderBottomColor: '#222' },
  subsystemTitle: { color: '#6C63FF', fontSize: 14, fontWeight: '700', flex: 1 },
  subsystemStats: { color: '#888', fontSize: 12 },
  subsystemRunBtn: { paddingHorizontal: 10, paddingVertical: 4, backgroundColor: '#1E1E1E', borderRadius: 6 },
  subsystemRunText: { color: '#6C63FF', fontSize: 11, fontWeight: '700' },
  testRow: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 8, paddingHorizontal: 8, backgroundColor: '#1a1a1a', borderRadius: 8, marginBottom: 4 },
  testIcon: { fontSize: 14, fontWeight: '700', width: 36, textAlign: 'center', fontFamily: 'monospace' },
  testInfo: { flex: 1 },
  testName: { color: '#FFF', fontSize: 13, fontWeight: '600' },
  testId: { color: '#666', fontSize: 10, fontFamily: 'monospace', marginTop: 1 },
  testDuration: { color: '#888', fontSize: 10, fontFamily: 'monospace', marginTop: 2 },
  testError: { color: '#FF5252', fontSize: 11, marginTop: 4 },
  logPanel: { height: 180, backgroundColor: '#000', borderTopWidth: 1, borderTopColor: '#222' },
  logHeader: { flexDirection: 'row', justifyContent: 'space-between', padding: 8, borderBottomWidth: 1, borderBottomColor: '#1a1a1a' },
  logTitle: { color: '#6C63FF', fontSize: 11, fontWeight: '700' },
  logClear: { color: '#FFB74D', fontSize: 11 },
  logScroll: { flex: 1, padding: 8 },
  logLine: { color: '#AAA', fontSize: 10, fontFamily: 'monospace', lineHeight: 14 },
  reportPanel: { height: 320, backgroundColor: '#000', borderTopWidth: 1, borderTopColor: '#6C63FF' },
  reportTitle: { color: '#6C63FF', fontSize: 12, fontWeight: '700', padding: 8 },
  reportScroll: { flex: 1, padding: 8 },
  reportText: { color: '#CCC', fontSize: 10, fontFamily: 'monospace', lineHeight: 14 },
});
TESTRUNNER_EOF
echo "✓ framework/TestRunner.tsx"

echo ""
echo "=== Part 8: ThreeDViewer wrapper + App.tsx ==="

cat > src/components/ThreeDViewer.tsx << 'THREEVIEWER_EOF'
/**
 * components/ThreeDViewer.tsx
 *
 * THIN WRAPPER around EngineViewer.
 * Preserves the existing ThreeDViewerProps API.
 */

import React from 'react';
import { EngineViewer, type EngineViewerProps } from '../engine';

export interface ThreeDViewerProps {
  modelUri: string | null;
  garmentUri?: string | null;
  autoRotate?: boolean;
  onReady?: () => void;
  debug?: boolean;
  modelVersion?: string | number;
  garmentVersion?: string | number;
}

export default function ThreeDViewer({
  modelUri,
  garmentUri,
  autoRotate: _autoRotate = true,
  onReady,
  debug = false,
  modelVersion = 1,
  garmentVersion = 1,
}: ThreeDViewerProps) {
  const engineViewerProps: EngineViewerProps = {
    bodyModelUri: modelUri,
    bodyModelVersion: modelVersion,
    garmentUri,
    garmentVersion,
    debug,
    onBodyReady: onReady,
    onGarmentReady: undefined,
    onError: (err) => console.error('[ThreeDViewer]', err),
  };
  return <EngineViewer {...engineViewerProps} />;
}
THREEVIEWER_EOF
echo "✓ components/ThreeDViewer.tsx"

cat > App.tsx << 'APP_EOF'
import React from 'react';
import { StatusBar } from 'expo-status-bar';
import { TestRunnerScreen } from './src/engine/__tests__/framework/TestRunner';

export default function App() {
  return (
    <>
      <StatusBar style="light" />
      <TestRunnerScreen />
    </>
  );
}
APP_EOF
echo "✓ App.tsx (TEST MODE)"

echo ""
echo "=========================================="
echo "=== ALL PARTS COMPLETE ==="
echo "=========================================="
echo ""
echo "Total engine files created:"
find src/engine -type f | wc -l
echo ""
echo "File tree:"
find src/engine -type f | sort
echo ""
echo "Components:"
ls -la src/components/ThreeDViewer.tsx
echo ""
echo "App.tsx:"
ls -la App.tsx
echo ""
echo "READY TO TEST: cd /Users/yashas/VTO/apps/mobile && rm -rf node_modules/.cache && npx expo start --clear"
