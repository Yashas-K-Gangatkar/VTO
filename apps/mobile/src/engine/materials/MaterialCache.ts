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
