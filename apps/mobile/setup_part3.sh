#!/bin/bash
set -e
cd /Users/yashas/VTO/apps/mobile

echo "=== Writing engine/geometry/MeshOptimizer.ts ==="
cat > src/engine/geometry/MeshOptimizer.ts << 'MESHOPTIMIZER_EOF'
/**
 * engine/geometry/MeshOptimizer.ts
 *
 * Reduces mesh complexity in-place using greedy edge collapse.
 *
 * This is a SIMPLIFIED QEM implementation. For production swap in
 * meshoptimizer library (https://github.com/zeux/meshoptimizer).
 */

import * as THREE from 'three';

const TAG = '[MeshOptimizer]';

export interface OptimizationOptions {
  targetTriangles: number;
  preserveBoundaries: boolean;
  recomputeNormals: boolean;
  aggressiveness: number;
}

export const DEFAULT_OPTS: OptimizationOptions = {
  targetTriangles: 5000,
  preserveBoundaries: true,
  recomputeNormals: true,
  aggressiveness: 0.5,
};

export interface OptimizationResult {
  originalTriangles: number;
  originalVertices: number;
  optimizedTriangles: number;
  optimizedVertices: number;
  reductionRatio: number;
  durationMs: number;
}

export class MeshOptimizer {
  optimize(geometry: THREE.BufferGeometry, opts: OptimizationOptions = DEFAULT_OPTS): OptimizationResult {
    const start = performance.now();
    const origTris = this.countTriangles(geometry);
    const origVerts = geometry.attributes.position.count;

    if (origTris <= opts.targetTriangles) {
      this.optimizeVertexCache(geometry);
      return {
        originalTriangles: origTris,
        originalVertices: origVerts,
        optimizedTriangles: origTris,
        optimizedVertices: origVerts,
        reductionRatio: 1.0,
        durationMs: performance.now() - start,
      };
    }

    const result = this.decimate(geometry, opts.targetTriangles, opts);

    if (opts.recomputeNormals) {
      geometry.computeVertexNormals();
    }
    geometry.computeBoundingSphere();
    geometry.computeBoundingBox();

    const optTris = this.countTriangles(geometry);
    const optVerts = geometry.attributes.position.count;

    return {
      originalTriangles: origTris,
      originalVertices: origVerts,
      optimizedTriangles: optTris,
      optimizedVertices: optVerts,
      reductionRatio: optTris / origTris,
      durationMs: performance.now() - start,
    };
  }

  optimizeSkinnedMesh(geometry: THREE.BufferGeometry, _opts: OptimizationOptions): OptimizationResult {
    const start = performance.now();
    const tris = this.countTriangles(geometry);
    const verts = geometry.attributes.position.count;
    this.optimizeVertexCache(geometry);
    return {
      originalTriangles: tris,
      originalVertices: verts,
      optimizedTriangles: tris,
      optimizedVertices: verts,
      reductionRatio: 1.0,
      durationMs: performance.now() - start,
    };
  }

  private countTriangles(geometry: THREE.BufferGeometry): number {
    const pos = geometry.attributes.position;
    if (geometry.index) return geometry.index.count / 3;
    return pos.count / 3;
  }

  private decimate(geometry: THREE.BufferGeometry, targetTriangles: number, opts: OptimizationOptions): void {
    let wasIndexed = false;
    if (geometry.index) {
      geometry.toNonIndexed();
      wasIndexed = true;
    }

    const pos = geometry.attributes.position;
    const positions = pos.array as Float32Array;
    let triangleCount = positions.length / 9;

    const vertices: number[][] = [];
    for (let i = 0; i < positions.length / 3; i++) vertices.push([]);
    for (let t = 0; t < triangleCount; t++) {
      for (let i = 0; i < 3; i++) {
        const vIdx = t * 3 + i;
        vertices[vIdx].push(t);
      }
    }

    let collapseCount = 0;
    const maxCollapses = Math.floor((triangleCount - targetTriangles) / 2);

    while (triangleCount > targetTriangles && collapseCount < maxCollapses) {
      let bestT = -1;
      let bestI = -1;
      let bestLen = Infinity;

      for (let t = 0; t < triangleCount; t++) {
        const base = t * 9;
        if (positions[base] === 0 && positions[base + 1] === 0 && positions[base + 2] === 0) continue;

        for (let i = 0; i < 3; i++) {
          const i1 = base + i * 3;
          const i2 = base + ((i + 1) % 3) * 3;
          const dx = positions[i1] - positions[i2];
          const dy = positions[i1 + 1] - positions[i2 + 1];
          const dz = positions[i1 + 2] - positions[i2 + 2];
          const len = dx * dx + dy * dy + dz * dz;
          if (len < bestLen) {
            bestLen = len;
            bestT = t;
            bestI = i;
          }
        }
      }

      if (bestT < 0) break;

      const base = bestT * 9;
      const v1Base = base + bestI * 3;
      const v2Base = base + ((bestI + 1) % 3) * 3;

      positions[v1Base] = (positions[v1Base] + positions[v2Base]) / 2;
      positions[v1Base + 1] = (positions[v1Base + 1] + positions[v2Base + 1]) / 2;
      positions[v1Base + 2] = (positions[v1Base + 2] + positions[v2Base + 2]) / 2;

      positions[base] = 0; positions[base + 1] = 0; positions[base + 2] = 0;
      positions[base + 3] = 0; positions[base + 4] = 0; positions[base + 5] = 0;
      positions[base + 6] = 0; positions[base + 7] = 0; positions[base + 8] = 0;

      triangleCount--;
      collapseCount++;
    }

    this.compactGeometry(geometry, triangleCount);

    if (wasIndexed) {
      this.reindexGeometry(geometry);
    }

    pos.needsUpdate = true;
  }

  private compactGeometry(geometry: THREE.BufferGeometry, expectedTriangles: number): void {
    const pos = geometry.attributes.position;
    const src = pos.array as Float32Array;
    const dst = new Float32Array(expectedTriangles * 9);

    let writeIdx = 0;
    for (let t = 0; t < src.length / 9; t++) {
      const base = t * 9;
      if (src[base] === 0 && src[base + 1] === 0 && src[base + 2] === 0) continue;
      for (let i = 0; i < 9; i++) dst[writeIdx + i] = src[base + i];
      writeIdx += 9;
    }

    geometry.setAttribute('position', new THREE.BufferAttribute(dst, 3));

    for (const name of ['normal', 'uv', 'color']) {
      const attr = geometry.attributes[name];
      if (!attr) continue;
      const srcAttr = attr.array as Float32Array;
      const itemSize = attr.itemSize;
      const dstAttr = new Float32Array(expectedTriangles * 3 * itemSize);
      let w = 0;
      for (let t = 0; t < src.length / 9; t++) {
        const base = t * 9;
        if (src[base] === 0 && src[base + 1] === 0 && src[base + 2] === 0) continue;
        for (let i = 0; i < 3 * itemSize; i++) {
          dstAttr[w++] = srcAttr[t * 3 * itemSize + i];
        }
      }
      geometry.setAttribute(name, new THREE.BufferAttribute(dstAttr, itemSize));
    }
  }

  private reindexGeometry(geometry: THREE.BufferGeometry): void {
    const pos = geometry.attributes.position;
    const positions = pos.array as Float32Array;
    const vertexCount = positions.length / 3;

    const vertexMap = new Map<string, number>();
    const newIndex: number[] = [];
    const uniquePositions: number[] = [];

    for (let i = 0; i < vertexCount; i++) {
      const x = positions[i * 3];
      const y = positions[i * 3 + 1];
      const z = positions[i * 3 + 2];
      const key = `${x.toFixed(6)},${y.toFixed(6)},${z.toFixed(6)}`;
      let idx = vertexMap.get(key);
      if (idx === undefined) {
        idx = uniquePositions.length / 3;
        uniquePositions.push(x, y, z);
        vertexMap.set(key, idx);
      }
      newIndex.push(idx);
    }

    geometry.setAttribute('position', new THREE.BufferAttribute(new Float32Array(uniquePositions), 3));
    geometry.setIndex(newIndex);
  }

  private optimizeVertexCache(geometry: THREE.BufferGeometry): void {
    // Future: implement Tipsify vertex cache optimization.
    // For now, this is a no-op.
  }
}
MESHOPTIMIZER_EOF
echo "✓ engine/geometry/MeshOptimizer.ts"

echo "=== Writing engine/geometry/LODSystem.ts ==="
cat > src/engine/geometry/LODSystem.ts << 'LODSYSTEM_EOF'
/**
 * engine/geometry/LODSystem.ts
 *
 * Automatic Level-of-Detail management.
 */

import * as THREE from 'three';
import type { LODLevel, LODSpec, LoadedAsset } from '../core/types';
import { DEFAULT_LOD_SPECS } from '../core/types';

const TAG = '[LODSystem]';

export interface LODVariant {
  level: LODLevel;
  asset: LoadedAsset;
  isActive: boolean;
}

export interface LODGroup {
  id: string;
  container: THREE.Group;
  variants: Map<LODLevel, LODVariant>;
  currentLevel: LODLevel;
  currentDistance: number;
  target?: THREE.Vector3;
  onSwap?: (from: LODLevel, to: LODLevel) => void;
}

export interface ILODSystem {
  register(id: string, level: LODLevel, asset: LoadedAsset, opts?: { target?: THREE.Vector3; onSwap?: (from: LODLevel, to: LODLevel) => void }): LODGroup;
  unregister(id: string): void;
  update(cameraPosition: THREE.Vector3, dtSec: number): void;
  getGroups(): LODGroup[];
  getSpecs(): LODSpec[];
  setSpecs(specs: LODSpec[]): void;
  forceLOD(id: string, level: LODLevel): void;
  getStats(): LODStats;
}

export interface LODStats {
  groupCount: number;
  totalVariants: number;
  swapsThisFrame: number;
  swapsTotal: number;
  histogram: Record<LODLevel, number>;
}

export class LODSystem implements ILODSystem {
  private groups = new Map<string, LODGroup>();
  private specs: LODSpec[];
  private swapsTotal = 0;
  private swapsThisFrame = 0;
  private hysteresisPercent = 0.1;

  constructor(specs: LODSpec[] = DEFAULT_LOD_SPECS) {
    this.specs = [...specs].sort((a, b) => a.distanceRange[0] - b.distanceRange[0]);
  }

  register(
    id: string,
    level: LODLevel,
    asset: LoadedAsset,
    opts: { target?: THREE.Vector3; onSwap?: (from: LODLevel, to: LODLevel) => void } = {}
  ): LODGroup {
    let group = this.groups.get(id);
    if (!group) {
      group = {
        id,
        container: new THREE.Group(),
        variants: new Map(),
        currentLevel: level,
        currentDistance: 0,
        target: opts.target,
        onSwap: opts.onSwap,
      };
      this.groups.set(id, group);
    }

    const variant: LODVariant = { level, asset, isActive: false };
    group.variants.set(level, variant);

    if (group.variants.size === 1 || group.currentLevel === level) {
      this.activateVariant(group, level);
    }

    return group;
  }

  unregister(id: string): void {
    const group = this.groups.get(id);
    if (!group) return;

    for (const variant of group.variants.values()) {
      variant.asset.scene.traverse((obj: any) => {
        if (obj.isMesh) {
          obj.geometry?.dispose?.();
          if (Array.isArray(obj.material)) obj.material.forEach((m: any) => m.dispose?.());
          else obj.material?.dispose?.();
        }
      });
    }

    if (group.container.parent) {
      group.container.parent.remove(group.container);
    }

    this.groups.delete(id);
  }

  update(cameraPosition: THREE.Vector3, _dtSec: number): void {
    this.swapsThisFrame = 0;

    for (const group of this.groups.values()) {
      const target = group.target ?? group.container.position;
      group.currentDistance = cameraPosition.distanceTo(target);

      const desiredLevel = this.pickLOD(group.currentDistance, group.currentLevel);
      if (desiredLevel !== group.currentLevel) {
        if (group.variants.has(desiredLevel)) {
          const prev = group.currentLevel;
          this.activateVariant(group, desiredLevel);
          this.swapsThisFrame++;
          this.swapsTotal++;
          group.onSwap?.(prev, desiredLevel);
          group.currentLevel = desiredLevel;
        }
      }
    }
  }

  getGroups(): LODGroup[] {
    return Array.from(this.groups.values());
  }

  getSpecs(): LODSpec[] {
    return [...this.specs];
  }

  setSpecs(specs: LODSpec[]): void {
    this.specs = [...specs].sort((a, b) => a.distanceRange[0] - b.distanceRange[0]);
  }

  forceLOD(id: string, level: LODLevel): void {
    const group = this.groups.get(id);
    if (!group) return;
    if (!group.variants.has(level)) {
      console.warn(TAG, `forceLOD: ${id} has no variant at ${level}`);
      return;
    }
    const prev = group.currentLevel;
    this.activateVariant(group, level);
    group.currentLevel = level;
    group.onSwap?.(prev, level);
  }

  getStats(): LODStats {
    const histogram: Record<LODLevel, number> = { high: 0, medium: 0, low: 0, preview: 0 };
    let totalVariants = 0;
    for (const group of this.groups.values()) {
      histogram[group.currentLevel] = (histogram[group.currentLevel] ?? 0) + 1;
      totalVariants += group.variants.size;
    }
    return {
      groupCount: this.groups.size,
      totalVariants,
      swapsThisFrame: this.swapsThisFrame,
      swapsTotal: this.swapsTotal,
      histogram,
    };
  }

  private pickLOD(distance: number, current: LODLevel): LODLevel {
    let best: LODLevel = 'high';
    for (const spec of this.specs) {
      const [near, far] = spec.distanceRange;
      if (distance >= near && distance <= far) {
        if (spec.level === current) {
          return spec.level;
        }
        const range = far - near;
        const margin = range * this.hysteresisPercent;
        if (distance >= near + margin && distance <= far - margin) {
          best = spec.level;
        }
      }
    }
    return best;
  }

  private activateVariant(group: LODGroup, level: LODLevel): void {
    for (const [lvl, variant] of group.variants) {
      variant.isActive = (lvl === level);
      if (lvl === level) {
        if (!variant.asset.scene.parent) {
          group.container.add(variant.asset.scene);
        }
        variant.asset.scene.visible = true;
      } else {
        if (variant.asset.scene.parent === group.container) {
          variant.asset.scene.visible = false;
        }
      }
    }
  }
}
LODSYSTEM_EOF
echo "✓ engine/geometry/LODSystem.ts"

echo "=== Writing engine/geometry/BoundingBox.ts ==="
cat > src/engine/geometry/BoundingBox.ts << 'BOUNDINGBOX_EOF'
/**
 * engine/geometry/BoundingBox.ts
 *
 * Bounding box utilities — computation, transform, intersection, fitting.
 */

import * as THREE from 'three';
import type { BoundingBox as BBox, Vec3 } from '../core/types';

export class BoundingBoxUtils {
  static fromObject(obj: THREE.Object3D): BBox {
    const box = new THREE.Box3().setFromObject(obj);
    return BoundingBoxUtils.fromThreeBox(box);
  }

  static fromThreeBox(box: THREE.Box3): BBox {
    const size = box.getSize(new THREE.Vector3());
    const center = box.getCenter(new THREE.Vector3());
    return {
      min: { x: box.min.x, y: box.min.y, z: box.min.z },
      max: { x: box.max.x, y: box.max.y, z: box.max.z },
      center: { x: center.x, y: center.y, z: center.z },
      size: { x: size.x, y: size.y, z: size.z },
    };
  }

  static toThreeBox(b: BBox): THREE.Box3 {
    return new THREE.Box3(
      new THREE.Vector3(b.min.x, b.min.y, b.min.z),
      new THREE.Vector3(b.max.x, b.max.y, b.max.z)
    );
  }

  static maxDim(b: BBox): number {
    return Math.max(b.size.x, b.size.y, b.size.z);
  }

  static volume(b: BBox): number {
    return b.size.x * b.size.y * b.size.z;
  }

  static contains(b: BBox, p: Vec3): boolean {
    return (
      p.x >= b.min.x && p.x <= b.max.x &&
      p.y >= b.min.y && p.y <= b.max.y &&
      p.z >= b.min.z && p.z <= b.max.z
    );
  }

  static intersects(a: BBox, b: BBox): boolean {
    return !(
      a.max.x < b.min.x || a.min.x > b.max.x ||
      a.max.y < b.min.y || a.min.y > b.max.y ||
      a.max.z < b.min.z || a.min.z > b.max.z
    );
  }

  static fit(source: BBox, target: BBox): { scale: number; offset: Vec3 } {
    const sMax = BoundingBoxUtils.maxDim(source);
    const tMax = BoundingBoxUtils.maxDim(target);
    if (sMax < 1e-6) return { scale: 1, offset: { x: 0, y: 0, z: 0 } };
    const scale = tMax / sMax;
    return {
      scale,
      offset: {
        x: target.center.x - source.center.x * scale,
        y: target.center.y - source.center.y * scale,
        z: target.center.z - source.center.z * scale,
      },
    };
  }

  static toWireframe(b: BBox, color: number = 0x00ff00): THREE.Box3Helper {
    const box = BoundingBoxUtils.toThreeBox(b);
    return new THREE.Box3Helper(box, new THREE.Color(color));
  }

  static lerp(a: BBox, b: BBox, t: number): BBox {
    const lerpVec = (v1: Vec3, v2: Vec3, t: number): Vec3 => ({
      x: v1.x + (v2.x - v1.x) * t,
      y: v1.y + (v2.y - v1.y) * t,
      z: v1.z + (v2.z - v1.z) * t,
    });
    const min = lerpVec(a.min, b.min, t);
    const max = lerpVec(a.max, b.max, t);
    const center = lerpVec(a.center, b.center, t);
    const size = lerpVec(a.size, b.size, t);
    return { min, max, center, size };
  }
}
BOUNDINGBOX_EOF
echo "✓ engine/geometry/BoundingBox.ts"

echo "=== Writing engine/materials/MaterialCache.ts ==="
cat > src/engine/materials/MaterialCache.ts << 'MATERIALCACHE_EOF'
/**
 * engine/materials/MaterialCache.ts
 *
 * Reference-counted material instance cache.
 */

import * as THREE from 'three';
import type { MaterialDescriptor } from '../core/types';

const TAG = '[MaterialCache]';

interface CachedMaterial {
  material: THREE.Material;
  refCount: number;
  descriptor: MaterialDescriptor;
  createdAt: number;
  estimatedBytes: number;
}

export interface IMaterialCache {
  acquire(descriptor: MaterialDescriptor): THREE.Material;
  release(material: THREE.Material): void;
  getMemoryUsage(): { bytes: number; count: number };
  disposeAll(): void;
  getStats(): MaterialCacheStats;
}

export interface MaterialCacheStats {
  count: number;
  totalRefs: number;
  estimatedBytes: number;
  hits: number;
  misses: number;
}

export class MaterialCache implements IMaterialCache {
  private cache = new Map<string, CachedMaterial>();
  private reverseLookup = new Map<THREE.Material, string>();
  private hits = 0;
  private misses = 0;

  acquire(descriptor: MaterialDescriptor): THREE.Material {
    const key = this.descriptorKey(descriptor);
    const cached = this.cache.get(key);
    if (cached) {
      cached.refCount += 1;
      this.hits += 1;
      return cached.material;
    }

    this.misses += 1;
    const material = this.createMaterial(descriptor);
    const estimatedBytes = this.estimateMaterialBytes(descriptor);
    const entry: CachedMaterial = {
      material,
      refCount: 1,
      descriptor,
      createdAt: Date.now(),
      estimatedBytes,
    };
    this.cache.set(key, entry);
    this.reverseLookup.set(material, key);
    return material;
  }

  release(material: THREE.Material): void {
    const key = this.reverseLookup.get(material);
    if (!key) {
      console.warn(TAG, 'release: material not in cache');
      return;
    }
    const entry = this.cache.get(key);
    if (!entry) return;
    entry.refCount -= 1;
    if (entry.refCount <= 0) {
      entry.material.dispose();
      this.cache.delete(key);
      this.reverseLookup.delete(material);
    }
  }

  getMemoryUsage(): { bytes: number; count: number } {
    let bytes = 0;
    for (const entry of this.cache.values()) bytes += entry.estimatedBytes;
    return { bytes, count: this.cache.size };
  }

  disposeAll(): void {
    for (const entry of this.cache.values()) {
      entry.material.dispose();
    }
    this.cache.clear();
    this.reverseLookup.clear();
  }

  getStats(): MaterialCacheStats {
    let totalRefs = 0;
    let bytes = 0;
    for (const entry of this.cache.values()) {
      totalRefs += entry.refCount;
      bytes += entry.estimatedBytes;
    }
    return {
      count: this.cache.size,
      totalRefs,
      estimatedBytes: bytes,
      hits: this.hits,
      misses: this.misses,
    };
  }

  private descriptorKey(d: MaterialDescriptor): string {
    const parts: string[] = [
      d.type,
      `${d.baseColor.r.toFixed(3)},${d.baseColor.g.toFixed(3)},${d.baseColor.b.toFixed(3)}`,
      d.roughness?.toFixed(3) ?? 'n',
      d.metalness?.toFixed(3) ?? 'n',
      d.alphaMode ?? 'o',
      d.alphaCutoff?.toFixed(3) ?? 'n',
      d.doubleSided ? 'ds' : 'ss',
      d.baseColorMap?.cacheKey ?? 'n',
      d.normalMap?.cacheKey ?? 'n',
      d.roughnessMap?.cacheKey ?? 'n',
      d.metalnessMap?.cacheKey ?? 'n',
    ];
    return parts.join('|');
  }

  private createMaterial(d: MaterialDescriptor): THREE.Material {
    let mat: THREE.Material;
    const color = new THREE.Color(d.baseColor.r, d.baseColor.g, d.baseColor.b);

    switch (d.type) {
      case 'standard':
        mat = new THREE.MeshStandardMaterial({
          color,
          roughness: d.roughness ?? 0.5,
          metalness: d.metalness ?? 0.0,
        });
        break;
      case 'physical':
        mat = new THREE.MeshPhysicalMaterial({
          color,
          roughness: d.roughness ?? 0.5,
          metalness: d.metalness ?? 0.0,
          clearcoat: 0.0,
          clearcoatRoughness: 0.0,
          transmission: 0.0,
          thickness: 0.0,
          ior: 1.5,
        });
        break;
      case 'phong':
        mat = new THREE.MeshPhongMaterial({ color, shininess: 30 });
        break;
      case 'basic':
      default:
        mat = new THREE.MeshBasicMaterial({ color });
        break;
    }

    if (d.alphaMode === 'BLEND') {
      mat.transparent = true;
      mat.depthWrite = false;
    } else if (d.alphaMode === 'MASK') {
      mat.transparent = false;
      mat.alphaTest = d.alphaCutoff ?? 0.5;
    }

    mat.side = d.doubleSided ? THREE.DoubleSide : THREE.FrontSide;
    return mat;
  }

  private estimateMaterialBytes(d: MaterialDescriptor): number {
    let bytes = 1024;
    if (d.baseColorMap) bytes += 100;
    if (d.normalMap) bytes += 100;
    if (d.roughnessMap) bytes += 100;
    if (d.metalnessMap) bytes += 100;
    return bytes;
  }
}
MATERIALCACHE_EOF
echo "✓ engine/materials/MaterialCache.ts"

echo "=== Writing engine/materials/MaterialFactory.ts ==="
cat > src/engine/materials/MaterialFactory.ts << 'MATERIALFACTORY_EOF'
/**
 * engine/materials/MaterialFactory.ts
 *
 * Creates MaterialDescriptor objects from various sources:
 *   - GLTF material JSON (pbrMetallicRoughness, KHR extensions)
 *   - Preset names ("cotton_red", "denim_blue", "silk_black")
 *   - Raw parameters (color, roughness, etc.)
 */

import * as THREE from 'three';
import type { MaterialDescriptor, Color, TextureRef } from '../core/types';

const TAG = '[MaterialFactory]';

export interface MaterialPreset {
  name: string;
  descriptor: MaterialDescriptor;
}

export const FABRIC_PRESETS: Record<string, MaterialPreset> = {
  cotton_white: {
    name: 'cotton_white',
    descriptor: {
      id: 'cotton_white',
      type: 'standard',
      baseColor: { r: 0.95, g: 0.95, b: 0.92 },
      roughness: 0.85,
      metalness: 0.0,
      alphaMode: 'OPAQUE',
      doubleSided: false,
    },
  },
  cotton_red: {
    name: 'cotton_red',
    descriptor: {
      id: 'cotton_red',
      type: 'standard',
      baseColor: { r: 0.78, g: 0.12, b: 0.12 },
      roughness: 0.85,
      metalness: 0.0,
      alphaMode: 'OPAQUE',
      doubleSided: false,
    },
  },
  denim_blue: {
    name: 'denim_blue',
    descriptor: {
      id: 'denim_blue',
      type: 'standard',
      baseColor: { r: 0.20, g: 0.30, b: 0.55 },
      roughness: 0.75,
      metalness: 0.0,
      alphaMode: 'OPAQUE',
      doubleSided: false,
    },
  },
  silk_black: {
    name: 'silk_black',
    descriptor: {
      id: 'silk_black',
      type: 'physical',
      baseColor: { r: 0.05, g: 0.05, b: 0.05 },
      roughness: 0.25,
      metalness: 0.0,
      alphaMode: 'OPAQUE',
      doubleSided: true,
    },
  },
  leather_brown: {
    name: 'leather_brown',
    descriptor: {
      id: 'leather_brown',
      type: 'physical',
      baseColor: { r: 0.25, g: 0.15, b: 0.08 },
      roughness: 0.45,
      metalness: 0.0,
      alphaMode: 'OPAQUE',
      doubleSided: false,
    },
  },
  chiffon_white: {
    name: 'chiffon_white',
    descriptor: {
      id: 'chiffon_white',
      type: 'physical',
      baseColor: { r: 0.95, g: 0.95, b: 0.95 },
      roughness: 0.35,
      metalness: 0.0,
      alphaMode: 'BLEND',
      doubleSided: true,
    },
  },
};

export class MaterialFactory {
  static fromPreset(name: string): MaterialDescriptor | null {
    const preset = FABRIC_PRESETS[name];
    if (!preset) {
      console.warn(TAG, `unknown preset: ${name}`);
      return null;
    }
    return JSON.parse(JSON.stringify(preset.descriptor));
  }

  static fromParams(params: {
    id: string;
    type?: 'standard' | 'physical' | 'basic' | 'phong';
    color?: Color;
    roughness?: number;
    metalness?: number;
    alphaMode?: 'OPAQUE' | 'BLEND' | 'MASK';
    alphaCutoff?: number;
    doubleSided?: boolean;
    baseColorMap?: TextureRef;
    normalMap?: TextureRef;
    roughnessMap?: TextureRef;
    metalnessMap?: TextureRef;
  }): MaterialDescriptor {
    return {
      id: params.id,
      type: params.type ?? 'standard',
      baseColor: params.color ?? { r: 0.8, g: 0.8, b: 0.8 },
      roughness: params.roughness,
      metalness: params.metalness,
      alphaMode: params.alphaMode,
      alphaCutoff: params.alphaCutoff,
      doubleSided: params.doubleSided,
      baseColorMap: params.baseColorMap,
      normalMap: params.normalMap,
      roughnessMap: params.roughnessMap,
      metalnessMap: params.metalnessMap,
    };
  }

  static fromGLTF(
    gltfMaterial: any,
    textureRefResolver: (gltfTextureIndex: number, slot: TextureSlot) => TextureRef | null
  ): MaterialDescriptor {
    const id = `gltf_${Math.random().toString(36).slice(2, 10)}`;
    const isUnlit = !!(gltfMaterial.extensions?.KHR_materials_unlit);
    const isSpecGloss = !!gltfMaterial.extensions?.KHR_materials_pbrSpecularGlossiness;

    const pbr = gltfMaterial.pbrMetallicRoughness ?? {};
    const baseColorFactor = pbr.baseColorFactor ?? [1, 1, 1, 1];

    let type: MaterialDescriptor['type'];
    if (isUnlit) type = 'basic';
    else if (isSpecGloss) type = 'standard';
    else type = 'standard';

    const baseColor: Color = {
      r: baseColorFactor[0] ?? 1,
      g: baseColorFactor[1] ?? 1,
      b: baseColorFactor[2] ?? 1,
    };

    let roughness: number | undefined = pbr.roughnessFactor;
    let metalness: number | undefined = pbr.metallicFactor;

    if (isSpecGloss) {
      const sg = gltfMaterial.extensions.KHR_materials_pbrSpecularGlossiness;
      const spec = sg.specularFactor ?? [1, 1, 1];
      const avgSpec = (spec[0] + spec[1] + spec[2]) / 3;
      roughness = 1 - avgSpec;
      metalness = 0;
    }

    const baseColorMap = pbr.baseColorTexture
      ? textureRefResolver(pbr.baseColorTexture.index, 'baseColor')
      : null;
    const normalMap = gltfMaterial.normalTexture
      ? textureRefResolver(gltfMaterial.normalTexture.index, 'normal')
      : null;
    const metallicRoughnessMap = pbr.metallicRoughnessTexture
      ? textureRefResolver(pbr.metallicRoughnessTexture.index, 'metallicRoughness')
      : null;
    const roughnessMap = metallicRoughnessMap;
    const metalnessMap = metallicRoughnessMap;

    return {
      id,
      type,
      baseColor,
      roughness,
      metalness,
      alphaMode: gltfMaterial.alphaMode ?? 'OPAQUE',
      alphaCutoff: gltfMaterial.alphaCutoff ?? 0.5,
      doubleSided: gltfMaterial.doubleSided ?? false,
      baseColorMap,
      normalMap,
      roughnessMap,
      metalnessMap,
    };
  }

  static threeColorToColor(c: THREE.Color): Color {
    return { r: c.r, g: c.g, b: c.b };
  }

  static colorToThreeColor(c: Color): THREE.Color {
    return new THREE.Color(c.r, c.g, c.b);
  }

  static listPresets(): string[] {
    return Object.keys(FABRIC_PRESETS);
  }
}

export type TextureSlot =
  | 'baseColor'
  | 'normal'
  | 'metallicRoughness'
  | 'roughness'
  | 'metalness'
  | 'emissive'
  | 'occlusion';
MATERIALFACTORY_EOF
echo "✓ engine/materials/MaterialFactory.ts"

echo "=== Writing engine/materials/MaterialSystem.ts ==="
cat > src/engine/materials/MaterialSystem.ts << 'MATERIALSYSTEM_EOF'
/**
 * engine/materials/MaterialSystem.ts
 *
 * Top-level material coordinator.
 */

import * as THREE from 'three';
import type { MaterialDescriptor, TextureRef, Color } from '../core/types';
import { MaterialCache, type IMaterialCache, type MaterialCacheStats } from './MaterialCache';
import { MaterialFactory } from './MaterialFactory';
import { TextureManager } from '../textures/TextureManager';
import type { ITextureManager } from '../textures/TextureManager';

const TAG = '[MaterialSystem]';

export interface IMaterialSystem {
  acquireMaterial(descriptor: MaterialDescriptor): Promise<THREE.Material>;
  releaseMaterial(material: THREE.Material): Promise<void>;
  swapTexture(material: THREE.Material, slot: TextureSlot, newTexture: TextureRef | null): Promise<void>;
  createColorVariant(source: THREE.Material, color: Color): Promise<THREE.Material>;
  getStats(): { materials: MaterialCacheStats; textures: { bytes: number; count: number; maxBytes: number } };
  disposeAll(): Promise<void>;
}

export type TextureSlot =
  | 'baseColor'
  | 'normal'
  | 'roughness'
  | 'metalness';

export interface MaterialSystemOptions {
  cache?: IMaterialCache;
  textureManager?: ITextureManager;
}

export class MaterialSystem implements IMaterialSystem {
  private readonly cache: IMaterialCache;
  private readonly textures: ITextureManager;
  private materialTextureRefs = new Map<THREE.Material, TextureRef[]>();

  constructor(opts: MaterialSystemOptions = {}) {
    this.cache = opts.cache ?? new MaterialCache();
    this.textures = opts.textureManager ?? new TextureManager();
  }

  async acquireMaterial(descriptor: MaterialDescriptor): Promise<THREE.Material> {
    const material = this.cache.acquire(descriptor);

    if (this.materialTextureRefs.has(material)) {
      return material;
    }

    const refs: TextureRef[] = [];
    try {
      if (descriptor.baseColorMap) {
        const tex = await this.textures.acquire(descriptor.baseColorMap);
        if (material instanceof THREE.MeshStandardMaterial ||
            material instanceof THREE.MeshPhysicalMaterial ||
            material instanceof THREE.MeshBasicMaterial) {
          material.map = tex;
          material.needsUpdate = true;
        }
        refs.push(descriptor.baseColorMap);
      }
      if (descriptor.normalMap) {
        const tex = await this.textures.acquire(descriptor.normalMap);
        if (material instanceof THREE.MeshStandardMaterial ||
            material instanceof THREE.MeshPhysicalMaterial) {
          material.normalMap = tex;
          material.needsUpdate = true;
        }
        refs.push(descriptor.normalMap);
      }
      if (descriptor.roughnessMap) {
        const tex = await this.textures.acquire(descriptor.roughnessMap);
        if (material instanceof THREE.MeshStandardMaterial ||
            material instanceof THREE.MeshPhysicalMaterial) {
          material.roughnessMap = tex;
          material.needsUpdate = true;
        }
        refs.push(descriptor.roughnessMap);
      }
      if (descriptor.metalnessMap) {
        const tex = await this.textures.acquire(descriptor.metalnessMap);
        if (material instanceof THREE.MeshStandardMaterial ||
            material instanceof THREE.MeshPhysicalMaterial) {
          material.metalnessMap = tex;
          material.needsUpdate = true;
        }
        refs.push(descriptor.metalnessMap);
      }
      this.materialTextureRefs.set(material, refs);
    } catch (e) {
      console.warn(TAG, 'failed to load textures for material — using untextured:', e);
      this.materialTextureRefs.set(material, refs);
    }

    return material;
  }

  async releaseMaterial(material: THREE.Material): Promise<void> {
    const refs = this.materialTextureRefs.get(material);
    if (refs) {
      for (const ref of refs) {
        this.textures.release(ref);
      }
      this.materialTextureRefs.delete(material);
    }
    this.cache.release(material);
  }

  async swapTexture(material: THREE.Material, slot: TextureSlot, newTexture: TextureRef | null): Promise<void> {
    const refs = this.materialTextureRefs.get(material) ?? [];
    const oldRef = refs.find((r) => r.cacheKey.includes(slot));

    if (oldRef) {
      this.textures.release(oldRef);
      const idx = refs.indexOf(oldRef);
      refs.splice(idx, 1);
    }

    if (newTexture) {
      const tex = await this.textures.acquire(newTexture);
      this.attachTexture(material, slot, tex);
      refs.push(newTexture);
    } else {
      this.attachTexture(material, slot, null);
    }

    this.materialTextureRefs.set(material, refs);
    material.needsUpdate = true;
  }

  async createColorVariant(source: THREE.Material, color: Color): Promise<THREE.Material> {
    const sourceDescriptor = this.findDescriptor(source);
    if (!sourceDescriptor) {
      throw new Error('createColorVariant: source material not in cache');
    }
    const variantDescriptor: MaterialDescriptor = {
      ...sourceDescriptor,
      id: `${sourceDescriptor.id}_variant_${Math.random().toString(36).slice(2, 6)}`,
      baseColor: color,
    };
    return this.acquireMaterial(variantDescriptor);
  }

  getStats(): { materials: MaterialCacheStats; textures: { bytes: number; count: number; maxBytes: number } } {
    return {
      materials: this.cache.getStats(),
      textures: this.textures.getMemoryUsage(),
    };
  }

  async disposeAll(): Promise<void> {
    for (const refs of this.materialTextureRefs.values()) {
      for (const ref of refs) {
        this.textures.release(ref);
      }
    }
    this.materialTextureRefs.clear();
    this.cache.disposeAll();
  }

  private attachTexture(material: THREE.Material, slot: TextureSlot, tex: THREE.Texture | null): void {
    if (material instanceof THREE.MeshStandardMaterial ||
        material instanceof THREE.MeshPhysicalMaterial) {
      switch (slot) {
        case 'baseColor': material.map = tex; break;
        case 'normal': material.normalMap = tex; break;
        case 'roughness': material.roughnessMap = tex; break;
        case 'metalness': material.metalnessMap = tex; break;
      }
    } else if (material instanceof THREE.MeshBasicMaterial && slot === 'baseColor') {
      material.map = tex;
    }
  }

  private findDescriptor(material: THREE.Material): MaterialDescriptor | null {
    return null;
  }
}

export { MaterialFactory, FABRIC_PRESETS } from './MaterialFactory';
MATERIALSYSTEM_EOF
echo "✓ engine/materials/MaterialSystem.ts"

echo ""
echo "=== Part 3 complete ==="
echo "Files written:"
ls -la src/engine/geometry/ src/engine/materials/
echo ""
echo "Total engine files so far:"
find src/engine -type f | wc -l
echo ""
echo "Continue with Part 4 (animation + skeleton + debug + streaming)."
