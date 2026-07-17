/**
 * engine/skeleton/GarmentFitter.ts
 *
 * Aligns a garment 3D model to a body 3D model.
 *
 * Fit levels:
 *   - bbox (fallback): bounding-box fit
 *   - anchor: position garment at specific body bone
 *   - retarget: full skeleton retarget
 *   - collision: future (cloth simulation)
 */

import * as THREE from 'three';
import type { LoadedAsset, SkeletonData, BodyMeasurements } from '../core/types';
import { BoundingBoxUtils } from '../geometry/BoundingBox';
import { SkeletonRetargeter, DEFAULT_RETARGET_OPTS } from '../animation/SkeletonRetargeter';

const TAG = '[GarmentFitter]';

export type FitLevel = 'bbox' | 'anchor' | 'retarget' | 'collision';

export interface FitOptions {
  level: FitLevel;
  anchorBone?: string;
  verticalOffset?: number;
  scaleMultiplier?: number;
  nonUniformScale?: boolean;
}

export const DEFAULT_FIT_OPTS: FitOptions = {
  level: 'bbox',
  verticalOffset: 0,
  scaleMultiplier: 1.0,
  nonUniformScale: false,
};

export interface FitResult {
  scale: number;
  position: THREE.Vector3;
  rotation: THREE.Euler;
  method: FitLevel;
  retargeted: boolean;
  warnings: string[];
}

export interface IGarmentFitter {
  fit(
    garment: LoadedAsset,
    body: LoadedAsset,
    bodyMeasurements: BodyMeasurements,
    opts?: FitOptions
  ): FitResult;
}

export class GarmentFitter implements IGarmentFitter {
  private retargeter: SkeletonRetargeter;

  constructor(retargeter?: SkeletonRetargeter) {
    this.retargeter = retargeter ?? new SkeletonRetargeter();
  }

  fit(
    garment: LoadedAsset,
    body: LoadedAsset,
    bodyMeasurements: BodyMeasurements,
    opts: FitOptions = DEFAULT_FIT_OPTS
  ): FitResult {
    const warnings: string[] = [];
    let method = opts.level;
    let retargeted = false;

    const bodyBbox = body.bbox;
    const garmentBbox = garment.bbox;
    const fit = BoundingBoxUtils.fit(garmentBbox, bodyBbox);
    const scale = fit.scale * (opts.scaleMultiplier ?? 1.0);

    const position = new THREE.Vector3(
      bodyBbox.center.x - garmentBbox.center.x * scale,
      bodyBbox.center.y - garmentBbox.center.y * scale + (opts.verticalOffset ?? 0),
      bodyBbox.center.z - garmentBbox.center.z * scale
    );

    const rotation = new THREE.Euler(0, 0, 0);

    if (opts.level === 'retarget' || opts.level === 'anchor') {
      if (!garment.skeleton || !body.skeleton) {
        warnings.push(`${opts.level} fit requested but skeleton missing — falling back to bbox`);
        method = 'bbox';
      } else if (opts.level === 'retarget') {
        const mapping = this.retargeter.buildMapping(
          garment.skeleton,
          body.skeleton,
          DEFAULT_RETARGET_OPTS
        );
        if (mapping.matchedCount > 0) {
          retargeted = true;
          this.applySkeletonPositions(garment, body, mapping.mapping);
        } else {
          warnings.push('retarget fit: no bones matched — keeping bbox fit');
          method = 'bbox';
        }
      } else if (opts.level === 'anchor') {
        const anchorBone = this.findBone(body.skeleton, opts.anchorBone ?? 'spine');
        if (anchorBone) {
          const worldPos = new THREE.Vector3();
          anchorBone.getWorldPosition(worldPos);
          position.copy(worldPos);
          position.y += opts.verticalOffset ?? 0;
        } else {
          warnings.push(`anchor fit: bone "${opts.anchorBone}" not found in body — using bbox center`);
        }
      }
    }

    garment.scene.scale.setScalar(scale);
    garment.scene.position.copy(position);
    garment.scene.rotation.copy(rotation);

    const result: FitResult = {
      scale, position: position.clone(), rotation: rotation.clone(),
      method, retargeted, warnings,
    };

    console.log(TAG, `fit ${garment.descriptor.id} -> ${body.descriptor.id}: method=${method} scale=${scale.toFixed(3)} retargeted=${retargeted}`);
    if (warnings.length > 0) console.warn(TAG, `fit warnings: ${warnings.join('; ')}`);

    return result;
  }

  private findBone(skeleton: SkeletonData, name: string): THREE.Bone | null {
    const bones = skeleton.skeleton.bones;
    let bone = bones.find((b) => b.name === name);
    if (bone) return bone;
    bone = bones.find((b) => b.name.toLowerCase() === name.toLowerCase());
    if (bone) return bone;
    const prefixes = ['mixamorig:', 'mixamorig', 'Armature|', 'Root|'];
    bone = bones.find((b) => {
      let n = b.name;
      for (const prefix of prefixes) {
        if (n.startsWith(prefix)) {
          n = n.slice(prefix.length);
          break;
        }
      }
      return n.toLowerCase() === name.toLowerCase();
    });
    return bone ?? null;
  }

  private applySkeletonPositions(
    garment: LoadedAsset,
    body: LoadedAsset,
    mapping: Record<string, string>
  ): void {
    if (!garment.skeleton || !body.skeleton) return;
    const garmentBones = garment.skeleton.skeleton.bones;
    const bodyBoneMap = new Map<string, THREE.Bone>();
    for (const b of body.skeleton.skeleton.bones) {
      bodyBoneMap.set(b.name, b);
    }

    for (const gBone of garmentBones) {
      const targetName = mapping[gBone.name];
      if (!targetName) continue;
      const targetBone = bodyBoneMap.get(targetName);
      if (!targetBone) continue;

      const targetWorld = new THREE.Vector3();
      targetBone.getWorldPosition(targetWorld);
      const localPos = garment.scene.worldToLocal(targetWorld.clone());
      gBone.position.copy(localPos);
    }
  }
}
