import "../textures/RNPolyfill";



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
const PHASES: LoadPhase[] = ['queued', 'downloading', 'validating', 'parsing', 'optimizing', 'caching', 'ready'];

export interface AssetManagerOptions { cache?: ICacheManager; validator?: IAssetValidator; textureLoader?: ITextureLoader; tempDir?: string; }
export interface IAssetManager {
  load(descriptor: AssetDescriptor, opts?: LoadOptions): Promise<LoadedAsset>;
  onProgress(listener: (p: LoadProgress) => void): () => void;
  getActiveLoads(): LoadProgress[];
  release(loaded: LoadedAsset): void;
}
export interface LoadOptions { lod?: LODLevel; allowDownload?: boolean; tempDir?: string; }

export class AssetManager implements IAssetManager {
  private cache: ICacheManager;
  private validator: IAssetValidator;
  private textureLoader: ITextureLoader;
  private tempDir: string;
  private gltfLoader: GLTFLoader;
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

    if (!descriptor || !descriptor.url) {
      throw new Error(`AssetManager.load: descriptor.url is required`);
    }

    const emit = (phase: LoadPhase, phaseProgress: number, extra?: Partial<LoadProgress>) => {
      const phaseIndex = PHASES.indexOf(phase);
      const overallProgress = phaseIndex / (PHASES.length - 1);
      const p: LoadProgress = { descriptor, phase, phaseProgress, overallProgress, startedAt, elapsedMs: Date.now() - startedAt, ...extra };
      this.activeLoads.set(descriptor.id, p);
      for (const l of this.progressListeners) { try { l(p); } catch (e) { console.warn(TAG, 'listener threw:', e); } }
    };

    emit('queued', 0);

    try {
      const cached = await this.cache.get(descriptor);
      let localPath: string;
      if (cached) {
        localPath = cached.localPath;
        console.log(TAG, `cache hit: ${descriptor.id} v${descriptor.version}`);
      } else {
        if (!allowDownload) throw new Error(`Asset ${descriptor.id} not in cache and allowDownload=false`);
        emit('downloading', 0);
        const downloadPath = `${FileSystem.cacheDirectory}${descriptor.id}_download.glb`;
        const downloadResult = await FileSystem.downloadAsync(descriptor.url, downloadPath);
        if (downloadResult.status < 200 || downloadResult.status >= 300) throw new Error(`Download failed: HTTP ${downloadResult.status}`);
        if (!downloadResult.uri) throw new Error(`Download succeeded but uri is missing`);
        localPath = downloadResult.uri;
        emit('downloading', 1);
      }

      const fileBase64 = await FileSystem.readAsStringAsync(localPath, { encoding: 'base64' });
      const glbBuffer = this.base64ToArrayBuffer(fileBase64);

      emit('validating', 0.5);
      const validation = this.validator.validate(glbBuffer);
      if (!validation.valid) throw new Error(`Validation failed:\n  ${validation.errors.join('\n  ')}`);
      emit('validating', 1);

      emit('parsing', 0.2);
      const extracted = await this.textureLoader.extractFromGLB(glbBuffer, `${tempDir}${descriptor.id}/`);

      emit('parsing', 0.5);
      const gltf = await new Promise<any>((resolve, reject) => {
        const patchedGlb = this.rebuildGLB(extracted.patchedJson, glbBuffer);
        this.gltfLoader.parse(patchedGlb, '', resolve, (err: any) => reject(new Error(`GLTFLoader.parse failed: ${err?.message || err}`)));
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
      if (!cached) {
        try { await this.cache.put(descriptor, localPath); }
        catch (e) { console.warn(TAG, `cache.put failed (non-fatal):`, e); }
      }
      emit('caching', 1);

      const stats = this.extractStats(model, validation.stats);
      const skeleton = this.extractSkeleton(gltf);
      const loaded: LoadedAsset = {
        descriptor, scene: model, bbox, stats, skeleton,
        activeLOD: opts.lod ?? 'high', localPath, loadTimeMs: Date.now() - startedAt,
      };
      this.loadedAssets.set(descriptor.id, loaded);
      emit('ready', 1);
      this.activeLoads.delete(descriptor.id);
      console.log(TAG, `loaded ${descriptor.id} v${descriptor.version} — meshes=${stats.meshCount} tris=${stats.triangleCount} time=${loaded.loadTimeMs}ms`);
      return loaded;
    } catch (err: any) {
      const msg = err?.message || String(err);
      console.error(TAG, `load failed for ${descriptor.id}: ${msg}`);
      throw err;
    }
  }

  onProgress(listener: (p: LoadProgress) => void): () => void { this.progressListeners.add(listener); return () => this.progressListeners.delete(listener); }
  getActiveLoads(): LoadProgress[] { return Array.from(this.activeLoads.values()); }

  release(loaded: LoadedAsset): void {
    if (!loaded) return;
    loaded.scene.traverse((obj: any) => {
      if (obj.isMesh) {
        obj.geometry?.dispose?.();
        if (Array.isArray(obj.material)) obj.material.forEach((m: any) => m.dispose?.());
        else obj.material?.dispose?.();
      }
    });
    this.loadedAssets.delete(loaded.descriptor.id);
  }

  private rebuildGLB(patchedJson: any, originalBuffer: ArrayBuffer): ArrayBuffer {
    if (!patchedJson) return originalBuffer;
    const jsonBytes = new TextEncoder().encode(JSON.stringify(patchedJson));
    const jsonPaddedLen = Math.ceil(jsonBytes.length / 4) * 4;
    const jsonPadded = new Uint8Array(jsonPaddedLen).fill(0x20);
    jsonPadded.set(jsonBytes);

    const origBytes = new Uint8Array(originalBuffer);
    const dv = new DataView(originalBuffer);
    let offset = 12, binOffset = 0, binLength = 0;
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
    let meshCount = 0, triangleCount = 0, vertexCount = 0;
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
    const textureBytes = validationStats?.binChunkBytes ? validationStats.binChunkBytes * 0.5 : 0;
    return {
      meshCount, triangleCount: Math.round(triangleCount), vertexCount,
      materialCount: materials.size, textureCount: validationStats?.textureCount ?? 0,
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
      while (cur) { path.unshift(cur.name); cur = cur.parent as THREE.Bone | null; }
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
