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
