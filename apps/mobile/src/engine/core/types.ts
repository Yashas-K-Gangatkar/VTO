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
