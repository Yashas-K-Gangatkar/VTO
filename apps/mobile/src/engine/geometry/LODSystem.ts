import * as THREE from 'three';
import type { LODLevel, LODSpec, LoadedAsset } from '../core/types';
import { DEFAULT_LOD_SPECS } from '../core/types';

const TAG = '[LODSystem]';

export interface LODVariant { level: LODLevel; asset: LoadedAsset; isActive: boolean; }
export interface LODGroup {
  id: string; container: THREE.Group; variants: Map<LODLevel, LODVariant>;
  currentLevel: LODLevel; currentDistance: number;
  target?: THREE.Vector3; onSwap?: (from: LODLevel, to: LODLevel) => void;
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
  groupCount: number; totalVariants: number; swapsThisFrame: number;
  swapsTotal: number; histogram: Record<LODLevel, number>;
}

export class LODSystem implements ILODSystem {
  private groups = new Map<string, LODGroup>();
  private specs: LODSpec[];
  private swapsTotal = 0;
  private swapsThisFrame = 0;

  constructor(specs: LODSpec[] = DEFAULT_LOD_SPECS) {
    this.specs = [...specs];
  }

  register(id: string, level: LODLevel, asset: LoadedAsset, opts: { target?: THREE.Vector3; onSwap?: (from: LODLevel, to: LODLevel) => void } = {}): LODGroup {
    let group = this.groups.get(id);
    if (!group) {
      group = { id, container: new THREE.Group(), variants: new Map(), currentLevel: level, currentDistance: 0, target: opts.target, onSwap: opts.onSwap };
      this.groups.set(id, group);
    }
    const variant: LODVariant = { level, asset, isActive: false };
    group.variants.set(level, variant);
    if (group.variants.size === 1 || group.currentLevel === level) this.activateVariant(group, level);
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
    if (group.container.parent) group.container.parent.remove(group.container);
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

  getGroups(): LODGroup[] { return Array.from(this.groups.values()); }
  getSpecs(): LODSpec[] { return [...this.specs]; }
  setSpecs(specs: LODSpec[]): void { this.specs = [...specs]; }

  forceLOD(id: string, level: LODLevel): void {
    const group = this.groups.get(id);
    if (!group) return;
    if (!group.variants.has(level)) { console.warn(TAG, `forceLOD: ${id} has no variant at ${level}`); return; }
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
    return { groupCount: this.groups.size, totalVariants, swapsThisFrame: this.swapsThisFrame, swapsTotal: this.swapsTotal, histogram };
  }

  private pickLOD(distance: number, current: LODLevel): LODLevel {
    // First: check if current level still matches (stay if possible)
    for (const spec of this.specs) {
      if (spec.level !== current) continue;
      const [near, far] = spec.distanceRange;
      const farVal = far === Infinity ? Number.MAX_SAFE_INTEGER : far;
      if (distance >= near && distance <= farVal) return spec.level;
    }
    // Second: find a new level — Infinity-far specs match any distance >= near
    let bestMatch: LODSpec | null = null;
    for (const spec of this.specs) {
      const [near, far] = spec.distanceRange;
      const farVal = far === Infinity ? Number.MAX_SAFE_INTEGER : far;
      if (distance >= near && distance <= farVal) {
        if (far === Infinity) { bestMatch = spec; break; }
        const range = farVal - near;
        const margin = range * 0.1;
        if (distance >= near + margin && distance <= farVal - margin) bestMatch = spec;
      }
    }
    return bestMatch?.level ?? current;
  }

  private activateVariant(group: LODGroup, level: LODLevel): void {
    for (const [lvl, variant] of group.variants) {
      variant.isActive = (lvl === level);
      if (lvl === level) {
        if (!variant.asset.scene.parent) group.container.add(variant.asset.scene);
        variant.asset.scene.visible = true;
      } else {
        if (variant.asset.scene.parent === group.container) variant.asset.scene.visible = false;
      }
    }
  }
}
