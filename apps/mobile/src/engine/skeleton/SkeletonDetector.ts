/**
 * engine/skeleton/SkeletonDetector.ts
 *
 * Extracts a SkeletonData from a loaded THREE.Object3D.
 */

import * as THREE from 'three';
import type { SkeletonData } from '../core/types';

const TAG = '[SkeletonDetector]';

const COMMON_PREFIXES = ['mixamorig:', 'mixamorig', 'Armature|', 'Root|', 'rig|'];

export interface ISkeletonDetector {
  detect(root: THREE.Object3D): SkeletonData | null;
  findSkinnedMesh(root: THREE.Object3D): THREE.SkinnedMesh | null;
  normalizeBoneName(name: string): string;
}

export class SkeletonDetector implements ISkeletonDetector {
  detect(root: THREE.Object3D): SkeletonData | null {
    const skinned = this.findSkinnedMesh(root);
    if (!skinned || !skinned.skeleton) {
      const bones = this.findBoneHierarchy(root);
      if (!bones || bones.length === 0) return null;
      return this.buildFromBones(bones);
    }
    return this.buildFromSkeleton(skinned.skeleton);
  }

  findSkinnedMesh(root: THREE.Object3D): THREE.SkinnedMesh | null {
    let found: THREE.SkinnedMesh | null = null;
    root.traverse((obj: any) => {
      if (obj.isSkinnedMesh && !found) found = obj as THREE.SkinnedMesh;
    });
    return found;
  }

  normalizeBoneName(name: string): string {
    let n = name;
    for (const prefix of COMMON_PREFIXES) {
      if (n.startsWith(prefix)) {
        n = n.slice(prefix.length);
        break;
      }
    }
    return n;
  }

  private findBoneHierarchy(root: THREE.Object3D): THREE.Bone[] {
    const bones: THREE.Bone[] = [];
    root.traverse((obj: any) => {
      if (obj.isBone) bones.push(obj as THREE.Bone);
    });
    return bones;
  }

  private buildFromSkeleton(skeleton: THREE.Skeleton): SkeletonData {
    const boneHierarchy: Record<string, string[]> = {};
    const bindPose: Record<string, number[]> = {};
    const boneLengths: Record<string, number> = {};

    for (const bone of skeleton.bones) {
      const name = this.normalizeBoneName(bone.name) || bone.name;
      boneHierarchy[name] = this.buildPath(bone);
      bindPose[name] = bone.matrixWorld.elements.slice();

      const childBone = bone.children.find((c) => (c as any).isBone) as THREE.Bone | undefined;
      boneLengths[name] = childBone
        ? bone.position.distanceTo(childBone.position)
        : 0;
    }

    return { skeleton, boneHierarchy, bindPose, boneLengths };
  }

  private buildFromBones(bones: THREE.Bone[]): SkeletonData {
    const skeleton = new THREE.Skeleton(bones);
    return this.buildFromSkeleton(skeleton);
  }

  private buildPath(bone: THREE.Bone): string[] {
    const path: string[] = [];
    let cur: THREE.Object3D | null = bone;
    while (cur && (cur as any).isBone !== undefined) {
      path.unshift(this.normalizeBoneName(cur.name) || cur.name);
      cur = cur.parent;
    }
    return path;
  }
}
