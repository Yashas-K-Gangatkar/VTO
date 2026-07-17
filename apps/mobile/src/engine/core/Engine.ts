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
