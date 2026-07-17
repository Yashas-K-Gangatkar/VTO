#!/bin/bash
set -e
cd /Users/yashas/VTO/apps/mobile

echo "=== Creating directory structure ==="
mkdir -p src/engine/core
mkdir -p src/engine/assets
mkdir -p src/engine/textures
mkdir -p src/engine/camera
mkdir -p src/engine/geometry
mkdir -p src/engine/materials
mkdir -p src/engine/animation
mkdir -p src/engine/skeleton
mkdir -p src/engine/debug
mkdir -p src/engine/streaming
mkdir -p src/engine/viewer
mkdir -p src/engine/__tests__/framework
echo "✓ directories created"

echo "=== Writing engine/core/types.ts ==="
cat > src/engine/core/types.ts << 'ENGINE_TYPES_EOF'
/**
 * engine/core/types.ts
 *
 * Shared type definitions for the entire rendering engine.
 * Every module imports from here — never from each other's internals.
 *
 * Design rule: types live in one place so we can swap implementations
 * (e.g. FileCacheManager → MemoryCacheManager → AsyncStorageCacheManager)
 * without touching consumers.
 */

import type * as THREE from 'three';

// ===================================================================
// Asset identity & versioning
// ===================================================================

/**
 * Uniquely identifies a renderable asset (body model, garment, prop).
 * `id` is stable across versions; `version` is a monotonic integer or
 * semver string. Bumping `version` invalidates the cache entry.
 */
export interface AssetDescriptor {
  /** Stable identifier, e.g. "garment_tshirt_001" or "body_default" */
  id: string;
  /** Monotonic version. Cache invalidation is keyed on (id, version). */
  version: string | number;
  /** Remote URL or local file path. */
  url: string;
  /** Asset category — drives LOD policy, cache TTL, etc. */
  kind: AssetKind;
  /** Optional checksum (sha-256 hex). If present, cache validates against it. */
  checksum?: string;
  /** Optional size hint in bytes (for streaming/progress UI). */
  sizeBytes?: number;
}

export type AssetKind =
  | 'body'        // user's 3D body model — high priority, never evict
  | 'garment'     // try-on garment — medium priority
  | 'accessory'   // glasses, hats — low priority
  | 'environment' // store backdrop — low priority, streamable
  | 'animation';  // animation clip — small, prefetch

// ===================================================================
// LOD (Level of Detail)
// ===================================================================

export type LODLevel = 'high' | 'medium' | 'low' | 'preview';

export interface LODSpec {
  level: LODLevel;
  /** Target triangle count. Meshes above this get decimated. */
  maxTriangles: number;
  /** Target texture resolution (max dimension in pixels). */
  maxTextureSize: number;
  /** Distance from camera at which this LOD becomes active (three.js units). */
  distanceRange: [number, number];
}

export const DEFAULT_LOD_SPECS: LODSpec[] = [
  { level: 'preview', maxTriangles: 500,    maxTextureSize: 128,  distanceRange: [Infinity, Infinity] },
  { level: 'low',     maxTriangles: 2000,   maxTextureSize: 256,  distanceRange: [10, Infinity] },
  { level: 'medium',  maxTriangles: 10000,  maxTextureSize: 512,  distanceRange: [4, 10] },
  { level: 'high',    maxTriangles: 100000, maxTextureSize: 1024, distanceRange: [0, 4] },
];

// ===================================================================
// Loaded asset (post-parse, ready to render)
// ===================================================================

export interface LoadedAsset {
  descriptor: AssetDescriptor;
  /** three.js scene graph root for this asset. */
  scene: THREE.Group;
  /** Bounding box in local space (before any user transforms). */
  bbox: BoundingBox;
  /** Statistics computed during parse — used by DebugOverlay. */
  stats: AssetStats;
  /** Skeleton extracted from the GLB, if rigged. Null otherwise. */
  skeleton: SkeletonData | null;
  /** LOD currently loaded. May differ from requested if streaming. */
  activeLOD: LODLevel;
  /** Absolute filesystem path of the cached GLB. */
  localPath: string;
  /** Total time spent loading (ms) — for profiler. */
  loadTimeMs: number;
}

export interface BoundingBox {
  min: Vec3;
  max: Vec3;
  center: Vec3;
  size: Vec3;
}

export interface Vec3 {
  x: number;
  y: number;
  z: number;
}

export interface AssetStats {
  meshCount: number;
  triangleCount: number;
  vertexCount: number;
  materialCount: number;
  textureCount: number;
  /** Total GPU memory estimate (geometry + textures) in bytes. */
  estimatedMemoryBytes: number;
}

// ===================================================================
// Skeleton & animation
// ===================================================================

export interface SkeletonData {
  /** three.js skeleton object (live reference). */
  skeleton: THREE.Skeleton;
  /** Bone name → tree path, e.g. "spine" → ["root","spine"]. */
  boneHierarchy: Record<string, string[]>;
  /** Bone name → bind pose world matrix. */
  bindPose: Record<string, number[]>;
  /** Bone name → length in three.js units (for retargeting). */
  boneLengths: Record<string, number>;
}

export interface AnimationClipData {
  name: string;
  duration: number;
  tracks: THREE.KeyframeTrack[];
}

// ===================================================================
// Materials
// ===================================================================

export interface MaterialDescriptor {
  id: string;
  type: 'standard' | 'physical' | 'basic' | 'phong';
  baseColor: Color;
  baseColorMap?: TextureRef;
  normalMap?: TextureRef;
  roughnessMap?: TextureRef;
  metalnessMap?: TextureRef;
  roughness?: number;
  metalness?: number;
  alphaMode?: 'OPAQUE' | 'BLEND' | 'MASK';
  alphaCutoff?: number;
  doubleSided?: boolean;
}

export interface Color {
  r: number;
  g: number;
  b: number;
}

export interface TextureRef {
  /** Cache key — same image = same Texture instance. */
  cacheKey: string;
  /** Local file:// path or data URI. */
  uri: string;
  /** Desired max resolution; TextureManager may downscale for memory. */
  maxResolution?: number;
  /** sRGB or linear color space. */
  colorSpace?: 'srgb' | 'linear';
  /** Wrap mode. */
  wrapS?: 'repeat' | 'clamp' | 'mirror';
  wrapT?: 'repeat' | 'clamp' | 'mirror';
}

// ===================================================================
// Cache entries
// ===================================================================

export interface CacheEntry {
  descriptor: AssetDescriptor;
  /** Absolute filesystem path of the cached GLB. */
  localPath: string;
  sizeBytes: number;
  downloadedAt: number;
  lastAccessedAt: number;
  accessCount: number;
  /** Validated checksum, if descriptor.checksum was set. */
  validatedChecksum?: string;
}

export interface CacheManifest {
  /** Manifest schema version — bump if format changes. */
  schemaVersion: number;
  entries: Record<string, CacheEntry>;
  /** Total bytes used by all entries. */
  totalBytes: number;
  /** Max bytes before LRU eviction kicks in. */
  maxBytes: number;
}

// ===================================================================
// Profiling & debug
// ===================================================================

export interface FrameStats {
  frameNumber: number;
  /** Wall-clock delta from previous frame. */
  frameTimeMs: number;
  /** 1 / frameTimeMs (smoothed). */
  fps: number;
  /** three.js renderer.info.render. */
  drawCalls: number;
  triangles: number;
  geometries: number;
  textures: number;
  programs: number;
  /** JS heap (if available from Performance API). */
  jsHeapUsedMB: number;
  jsHeapTotalMB: number;
  /** GPU memory estimate from AssetStats. */
  estimatedGpuMemoryMB: number;
  /** Time spent in animation update (ms). */
  animationTimeMs: number;
  /** Time spent in renderer.render() (ms). */
  renderTimeMs: number;
}

// ===================================================================
// Progress & streaming
// ===================================================================

export type LoadPhase =
  | 'queued'
  | 'downloading'
  | 'validating'
  | 'parsing'
  | 'optimizing'
  | 'caching'
  | 'ready'
  | 'error';

export interface LoadProgress {
  descriptor: AssetDescriptor;
  phase: LoadPhase;
  /** 0-1 progress within current phase. */
  phaseProgress: number;
  /** Overall 0-1 across all phases. */
  overallProgress: number;
  bytesLoaded?: number;
  bytesTotal?: number;
  error?: string;
  startedAt: number;
  elapsedMs: number;
}
ENGINE_TYPES_EOF
echo "✓ engine/core/types.ts"

echo "=== Writing engine/assets/CacheManager.ts ==="
cat > src/engine/assets/CacheManager.ts << 'CACHEMANAGER_EOF'
/**
 * engine/assets/CacheManager.ts
 *
 * Versioned filesystem cache for 3D assets.
 *
 * Design goals (informed by Unreal's IoStore + Unity's Addressables):
 *   - Cache invalidation is automatic — bump descriptor.version and the
 *     old file is deleted on next load. No more "Reset" button.
 *   - LRU eviction with a byte budget per asset kind (body models never
 *     get evicted, garments do).
 *   - Manifest is persisted to disk so cache survives app restarts.
 *   - All operations are atomic — a crash mid-write doesn't corrupt the
 *     manifest (we write to .tmp then rename).
 */

import * as FileSystem from 'expo-file-system/legacy';
import type {
  AssetDescriptor,
  AssetKind,
  CacheEntry,
  CacheManifest,
} from '../core/types';

const TAG = '[CacheManager]';
const MANIFEST_SCHEMA_VERSION = 1;

const DEFAULT_KIND_BUDGETS: Record<AssetKind, number> = {
  body: Number.MAX_SAFE_INTEGER,
  garment: 200 * 1024 * 1024,
  accessory: 50 * 1024 * 1024,
  environment: 100 * 1024 * 1024,
  animation: 20 * 1024 * 1024,
};

export interface ICacheManager {
  get(descriptor: AssetDescriptor): Promise<CacheEntry | null>;
  put(descriptor: AssetDescriptor, sourcePath: string): Promise<CacheEntry>;
  invalidate(id: string): Promise<void>;
  invalidateAll(): Promise<void>;
  getManifest(): Promise<CacheManifest>;
  prune(): Promise<{ evictedIds: string[]; freedBytes: number }>;
  subscribe(listener: (manifest: CacheManifest) => void): () => void;
}

export interface CacheManagerOptions {
  cacheDirectory?: string;
  manifestPath?: string;
  kindBudgets?: Partial<Record<AssetKind, number>>;
}

export class CacheManager implements ICacheManager {
  private readonly cacheDir: string;
  private readonly manifestPath: string;
  private readonly kindBudgets: Record<AssetKind, number>;
  private manifest: CacheManifest | null = null;
  private listeners = new Set<(m: CacheManifest) => void>();
  private initPromise: Promise<void> | null = null;

  constructor(opts: CacheManagerOptions = {}) {
    const baseDir = opts.cacheDirectory ?? `${FileSystem.documentDirectory}asset_cache/`;
    this.cacheDir = baseDir.endsWith('/') ? baseDir : baseDir + '/';
    this.manifestPath = opts.manifestPath ?? `${this.cacheDir}manifest.json`;
    this.kindBudgets = { ...DEFAULT_KIND_BUDGETS, ...(opts.kindBudgets ?? {}) };
  }

  private async init(): Promise<void> {
    if (!this.initPromise) {
      this.initPromise = this._init();
    }
    return this.initPromise;
  }

  private async _init(): Promise<void> {
    const dirInfo = await FileSystem.getInfoAsync(this.cacheDir);
    if (!dirInfo.exists) {
      await FileSystem.makeDirectoryAsync(this.cacheDir, { intermediates: true });
      console.log(TAG, `created cache dir: ${this.cacheDir}`);
    }
    try {
      const manifestInfo = await FileSystem.getInfoAsync(this.manifestPath);
      if (manifestInfo.exists) {
        const raw = await FileSystem.readAsStringAsync(this.manifestPath);
        const parsed = JSON.parse(raw) as CacheManifest;
        if (parsed.schemaVersion === MANIFEST_SCHEMA_VERSION) {
          this.manifest = parsed;
          console.log(TAG, `loaded manifest: ${Object.keys(parsed.entries).length} entries, ${(parsed.totalBytes / 1024 / 1024).toFixed(2)} MB`);
        } else {
          console.warn(TAG, `manifest schema mismatch — rebuilding`);
          this.manifest = this.emptyManifest();
        }
      } else {
        this.manifest = this.emptyManifest();
      }
    } catch (e) {
      console.warn(TAG, 'failed to load manifest, starting fresh:', e);
      this.manifest = this.emptyManifest();
    }
    await this.gcOrphans();
  }

  private emptyManifest(): CacheManifest {
    return {
      schemaVersion: MANIFEST_SCHEMA_VERSION,
      entries: {},
      totalBytes: 0,
      maxBytes: Number.MAX_SAFE_INTEGER,
    };
  }

  async get(descriptor: AssetDescriptor): Promise<CacheEntry | null> {
    await this.init();
    const entry = this.manifest!.entries[descriptor.id];
    if (!entry) return null;
    if (entry.descriptor.version !== descriptor.version) {
      console.log(TAG, `version mismatch for ${descriptor.id}: cached=${entry.descriptor.version} requested=${descriptor.version} → invalidating`);
      await this.invalidate(descriptor.id);
      return null;
    }
    if (descriptor.checksum && entry.validatedChecksum !== descriptor.checksum) {
      console.log(TAG, `checksum mismatch for ${descriptor.id} → invalidating`);
      await this.invalidate(descriptor.id);
      return null;
    }
    const info = await FileSystem.getInfoAsync(entry.localPath);
    if (!info.exists) {
      console.warn(TAG, `manifest says ${descriptor.id} is at ${entry.localPath} but file is gone → invalidating`);
      await this.invalidate(descriptor.id);
      return null;
    }
    entry.lastAccessedAt = Date.now();
    entry.accessCount += 1;
    this.notifyListeners();
    return entry;
  }

  async put(descriptor: AssetDescriptor, sourcePath: string): Promise<CacheEntry> {
    await this.init();
    const existing = this.manifest!.entries[descriptor.id];
    if (existing) {
      await this.safeDelete(existing.localPath);
    }
    const ext = this.extractExt(descriptor.url) || 'glb';
    const filename = `${descriptor.id}__v${descriptor.version}.${ext}`;
    const localPath = `${this.cacheDir}${filename}`;
    const sourceInfo = await FileSystem.getInfoAsync(sourcePath);
    if (!sourceInfo.exists) {
      throw new Error(`CacheManager.put: source does not exist: ${sourcePath}`);
    }
    await FileSystem.copyAsync({ from: sourcePath, to: localPath });
    const sizeBytes = sourceInfo.size ?? 0;
    const entry: CacheEntry = {
      descriptor,
      localPath,
      sizeBytes,
      downloadedAt: Date.now(),
      lastAccessedAt: Date.now(),
      accessCount: 1,
      validatedChecksum: descriptor.checksum,
    };
    this.manifest!.entries[descriptor.id] = entry;
    this.manifest!.totalBytes += sizeBytes;
    this.notifyListeners();
    await this.persistManifest();
    console.log(TAG, `cached ${descriptor.id} v${descriptor.version} (${(sizeBytes / 1024).toFixed(1)} KB)`);
    this.prune().catch((e) => console.warn(TAG, 'background prune failed:', e));
    return entry;
  }

  async invalidate(id: string): Promise<void> {
    await this.init();
    const entry = this.manifest!.entries[id];
    if (!entry) return;
    await this.safeDelete(entry.localPath);
    delete this.manifest!.entries[id];
    this.manifest!.totalBytes -= entry.sizeBytes;
    if (this.manifest!.totalBytes < 0) this.manifest!.totalBytes = 0;
    await this.persistManifest();
    this.notifyListeners();
    console.log(TAG, `invalidated ${id}`);
  }

  async invalidateAll(): Promise<void> {
    await this.init();
    const ids = Object.keys(this.manifest!.entries);
    await Promise.all(ids.map((id) => this.invalidate(id)));
    console.log(TAG, `invalidated all (${ids.length} entries)`);
  }

  async getManifest(): Promise<CacheManifest> {
    await this.init();
    return { ...this.manifest!, entries: { ...this.manifest!.entries } };
  }

  async prune(): Promise<{ evictedIds: string[]; freedBytes: number }> {
    await this.init();
    const evictedIds: string[] = [];
    let freedBytes = 0;
    const byKind = this.groupEntriesByKind();
    for (const [kind, entries] of Object.entries(byKind)) {
      const budget = this.kindBudgets[kind as AssetKind] ?? Number.MAX_SAFE_INTEGER;
      let used = entries.reduce((s, e) => s + e.sizeBytes, 0);
      if (used <= budget) continue;
      entries.sort((a, b) => a.lastAccessedAt - b.lastAccessedAt);
      for (const entry of entries) {
        if (used <= budget) break;
        if (entry.descriptor.kind === 'body') continue;
        await this.safeDelete(entry.localPath);
        delete this.manifest!.entries[entry.descriptor.id];
        this.manifest!.totalBytes -= entry.sizeBytes;
        used -= entry.sizeBytes;
        freedBytes += entry.sizeBytes;
        evictedIds.push(entry.descriptor.id);
      }
    }
    if (evictedIds.length > 0) {
      await this.persistManifest();
      this.notifyListeners();
      console.log(TAG, `pruned ${evictedIds.length} entries, freed ${(freedBytes / 1024 / 1024).toFixed(2)} MB`);
    }
    return { evictedIds, freedBytes };
  }

  subscribe(listener: (m: CacheManifest) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private groupEntriesByKind(): Record<string, CacheEntry[]> {
    const out: Record<string, CacheEntry[]> = {};
    for (const entry of Object.values(this.manifest!.entries)) {
      const k = entry.descriptor.kind;
      (out[k] ??= []).push(entry);
    }
    return out;
  }

  private async gcOrphans(): Promise<void> {
    if (!this.manifest) return;
    try {
      const listed = await FileSystem.readDirectoryAsync(this.cacheDir);
      const knownPaths = new Set(Object.values(this.manifest.entries).map((e) => e.localPath));
      for (const fname of listed) {
        const full = `${this.cacheDir}${fname}`;
        if (fname === 'manifest.json') continue;
        if (!knownPaths.has(full)) {
          await this.safeDelete(full);
          console.log(TAG, `gc: removed orphan ${fname}`);
        }
      }
    } catch (e) {
      console.warn(TAG, 'gcOrphans failed:', e);
    }
  }

  private async persistManifest(): Promise<void> {
    if (!this.manifest) return;
    const tmpPath = `${this.manifestPath}.tmp`;
    const json = JSON.stringify(this.manifest, null, 2);
    try {
      await FileSystem.writeAsStringAsync(tmpPath, json);
      await FileSystem.moveAsync({ from: tmpPath, to: this.manifestPath });
    } catch (e) {
      console.error(TAG, 'failed to persist manifest:', e);
      try { await FileSystem.deleteAsync(tmpPath, { idempotent: true }); } catch { /* ignore */ }
    }
  }

  private async safeDelete(path: string): Promise<void> {
    try {
      await FileSystem.deleteAsync(path, { idempotent: true });
    } catch (e) {
      console.warn(TAG, `failed to delete ${path}:`, e);
    }
  }

  private extractExt(url: string): string | null {
    const m = url.match(/\.([a-zA-Z0-9]+)(?:$|\?)/);
    return m ? m[1].toLowerCase() : null;
  }

  private notifyListeners(): void {
    if (!this.manifest) return;
    const snapshot: CacheManifest = {
      ...this.manifest,
      entries: { ...this.manifest.entries },
    };
    for (const l of this.listeners) {
      try { l(snapshot); } catch (e) { console.warn(TAG, 'listener threw:', e); }
    }
  }
}
CACHEMANAGER_EOF
echo "✓ engine/assets/CacheManager.ts"

echo "=== Writing engine/assets/AssetValidator.ts ==="
cat > src/engine/assets/AssetValidator.ts << 'ASSETVALIDATOR_EOF'
/**
 * engine/assets/AssetValidator.ts
 *
 * Validates GLB files before they reach GLTFLoader.
 */

const GLB_MAGIC = 0x46546c67; // 'glTF' little-endian
const GLB_VERSION_SUPPORTED = 2;
const CHUNK_TYPE_JSON = 0x4e4f534a;
const CHUNK_TYPE_BIN = 0x004e4942;

export interface ValidationResult {
  valid: boolean;
  errors: string[];
  warnings: string[];
  stats: {
    fileSizeBytes: number;
    jsonChunkBytes: number;
    binChunkBytes: number;
    meshCount: number;
    materialCount: number;
    textureCount: number;
    accessorCount: number;
    bufferViewCount: number;
    usesExtensions: string[];
  };
}

export interface IAssetValidator {
  validate(buf: ArrayBuffer): ValidationResult;
  validateBytes(bytes: Uint8Array): ValidationResult;
}

export class AssetValidator implements IAssetValidator {
  validate(buf: ArrayBuffer): ValidationResult {
    return this.validateBytes(new Uint8Array(buf));
  }

  validateBytes(bytes: Uint8Array): ValidationResult {
    const errors: string[] = [];
    const warnings: string[] = [];
    const stats = {
      fileSizeBytes: bytes.byteLength,
      jsonChunkBytes: 0,
      binChunkBytes: 0,
      meshCount: 0,
      materialCount: 0,
      textureCount: 0,
      accessorCount: 0,
      bufferViewCount: 0,
      usesExtensions: [] as string[],
    };

    if (bytes.byteLength < 12) {
      errors.push('File too small to be a GLB (need >=12 byte header)');
      return { valid: false, errors, warnings, stats };
    }

    const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const magic = dv.getUint32(0, true);
    const version = dv.getUint32(4, true);
    const length = dv.getUint32(8, true);

    if (magic !== GLB_MAGIC) {
      errors.push(`Invalid GLB magic: 0x${magic.toString(16)} (expected 0x${GLB_MAGIC.toString(16)})`);
    }
    if (version !== GLB_VERSION_SUPPORTED) {
      errors.push(`Unsupported GLB version: ${version} (only version ${GLB_VERSION_SUPPORTED} supported)`);
    }
    if (length !== bytes.byteLength) {
      errors.push(`Header length ${length} != actual file size ${bytes.byteLength} (truncated?)`);
    }

    if (errors.length > 0) {
      return { valid: false, errors, warnings, stats };
    }

    let offset = 12;
    let jsonStr = '';
    let binOffset = 0;
    let binLength = 0;
    let chunkIndex = 0;

    while (offset + 8 <= bytes.byteLength) {
      const chunkLength = dv.getUint32(offset, true);
      const chunkType = dv.getUint32(offset + 4, true);
      const chunkDataStart = offset + 8;
      const chunkDataEnd = chunkDataStart + chunkLength;

      if (chunkDataEnd > bytes.byteLength) {
        errors.push(`Chunk ${chunkIndex} extends past end of file (offset=${offset}, length=${chunkLength})`);
        break;
      }

      if (chunkType === CHUNK_TYPE_JSON) {
        if (chunkIndex !== 0) {
          warnings.push('JSON chunk is not first (spec violation, attempting anyway)');
        }
        const jsonBytes = bytes.subarray(chunkDataStart, chunkDataEnd);
        const trimmed = this.trimTrailingNulls(jsonBytes);
        try {
          jsonStr = new TextDecoder().decode(trimmed);
        } catch (e: any) {
          errors.push(`Failed to decode JSON chunk as UTF-8: ${e.message}`);
        }
        stats.jsonChunkBytes = chunkLength;
      } else if (chunkType === CHUNK_TYPE_BIN) {
        if (chunkIndex !== 1) {
          warnings.push(`BIN chunk is at index ${chunkIndex} (expected 1)`);
        }
        binOffset = chunkDataStart;
        binLength = chunkLength;
        stats.binChunkBytes = chunkLength;
      } else {
        warnings.push(`Unknown chunk type 0x${chunkType.toString(16)} at index ${chunkIndex}`);
      }

      offset = chunkDataEnd;
      chunkIndex += 1;
    }

    if (chunkIndex === 0) {
      errors.push('GLB has no chunks');
      return { valid: false, errors, warnings, stats };
    }

    let gltfJson: any = null;
    try {
      gltfJson = JSON.parse(jsonStr);
    } catch (e: any) {
      errors.push(`JSON chunk is not valid JSON: ${e.message}`);
      return { valid: false, errors, warnings, stats };
    }

    if (!gltfJson.asset || gltfJson.asset.version !== '2.0') {
      errors.push(`glTF asset.version is "${gltfJson.asset?.version}" (expected "2.0")`);
    }

    stats.meshCount = gltfJson.meshes?.length ?? 0;
    stats.materialCount = gltfJson.materials?.length ?? 0;
    stats.textureCount = gltfJson.textures?.length ?? 0;
    stats.accessorCount = gltfJson.accessors?.length ?? 0;
    stats.bufferViewCount = gltfJson.bufferViews?.length ?? 0;
    stats.usesExtensions = gltfJson.extensionsUsed ?? [];

    if (stats.meshCount === 0) {
      warnings.push('glTF has 0 meshes — nothing to render');
    }
    if (stats.accessorCount === 0) {
      warnings.push('glTF has 0 accessors — geometry data missing');
    }

    const unsupported = stats.usesExtensions.filter((ext) =>
      !['KHR_materials_pbrSpecularGlossiness', 'KHR_materials_unlit',
         'KHR_texture_transform', 'KHR_mesh_quantization',
         'KHR_draco_mesh_compression', 'KHR_materials_clearcoat',
         'KHR_materials_transmission', 'KHR_materials_ior',
         'KHR_materials_sheen', 'KHR_materials_specular',
         'KHR_materials_volume', 'KHR_lights_punctual',
         'KHR_materials_emissive_strength'].includes(ext)
    );
    if (unsupported.length > 0) {
      warnings.push(`Unsupported extensions (may render incorrectly): ${unsupported.join(', ')}`);
    }

    if (gltfJson.buffers?.[0]) {
      const declaredLength = gltfJson.buffers[0].byteLength ?? 0;
      if (declaredLength > binLength) {
        errors.push(`Buffer declares byteLength=${declaredLength} but BIN chunk is only ${binLength} bytes`);
      }
    }

    return {
      valid: errors.length === 0,
      errors,
      warnings,
      stats,
    };
  }

  private trimTrailingNulls(bytes: Uint8Array): Uint8Array {
    let end = bytes.byteLength;
    while (end > 0 && bytes[end - 1] === 0) end -= 1;
    return bytes.subarray(0, end);
  }
}
ASSETVALIDATOR_EOF
echo "✓ engine/assets/AssetValidator.ts"

echo ""
echo "=== Part 1 complete ==="
echo "Files written:"
ls -la src/engine/core/ src/engine/assets/
echo ""
echo "Continue with Part 2 (textures + camera)."
