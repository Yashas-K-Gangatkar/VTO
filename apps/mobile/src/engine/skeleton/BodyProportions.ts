/**
 * engine/skeleton/BodyProportions.ts
 *
 * Extracts body measurements from a 3D body model.
 */

import * as THREE from 'three';
import type { SkeletonData } from '../core/types';

const TAG = '[BodyProportions]';

export interface BodyMeasurements {
  height: number;
  shoulderWidth: number;
  hipWidth: number;
  chestCircumference: number;
  waistCircumference: number;
  armLength: number;
  legLength: number;
  torsoLength: number;
  headCircumference: number;
}

export interface IBodyProportions {
  measure(skeleton: SkeletonData, mesh: THREE.Object3D): BodyMeasurements;
}

export class BodyProportions implements IBodyProportions {
  measure(skeleton: SkeletonData, mesh: THREE.Object3D): BodyMeasurements {
    const bones = skeleton.skeleton.bones;
    const boneByName = new Map<string, THREE.Bone>();
    for (const bone of bones) {
      boneByName.set(bone.name.toLowerCase(), bone);
      boneByName.set(this.stripPrefix(bone.name).toLowerCase(), bone);
    }

    const find = (...names: string[]): THREE.Bone | null => {
      for (const n of names) {
        const b = boneByName.get(n.toLowerCase());
        if (b) return b;
      }
      return null;
    };

    const head = find('head', 'Head');
    const neck = find('neck', 'Neck');
    const hips = find('hips', 'Hips', 'pelvis', 'Pelvis');
    const leftShoulder = find('leftshoulder', 'leftarm', 'LeftArm', 'leftshoulder_001');
    const rightShoulder = find('rightshoulder', 'rightarm', 'RightArm', 'rightshoulder_001');
    const leftUpLeg = find('leftupleg', 'leftthigh', 'LeftUpLeg', 'leftleg');
    const rightUpLeg = find('rightupleg', 'rightthigh', 'RightUpLeg', 'rightleg');
    const leftHand = find('lefthand', 'LeftHand');
    const rightHand = find('righthand', 'RightHand');
    const leftFoot = find('leftfoot', 'LeftFoot');
    const rightFoot = find('rightfoot', 'RightFoot');

    const pos = (b: THREE.Bone | null): THREE.Vector3 => {
      if (!b) return new THREE.Vector3();
      const p = new THREE.Vector3();
      b.getWorldPosition(p);
      return p;
    };

    const headPos = pos(head);
    const hipsPos = pos(hips);
    const feetPos = leftFoot && rightFoot
      ? new THREE.Vector3().lerpVectors(pos(leftFoot), pos(rightFoot), 0.5)
      : hipsPos.clone().setY(hipsPos.y - 1);
    const height = headPos.distanceTo(feetPos) + (head ? 0.15 : 0);

    const shoulderWidth = leftShoulder && rightShoulder
      ? pos(leftShoulder).distanceTo(pos(rightShoulder))
      : 0;
    const hipWidth = leftUpLeg && rightUpLeg
      ? pos(leftUpLeg).distanceTo(pos(rightUpLeg))
      : 0;

    const armLength = leftShoulder && leftHand
      ? pos(leftShoulder).distanceTo(pos(leftHand))
      : 0;

    const legLength = leftUpLeg && leftFoot
      ? pos(leftUpLeg).distanceTo(pos(leftFoot))
      : 0;

    const torsoLength = (neck ?? leftShoulder) && hips
      ? pos(neck ?? leftShoulder).distanceTo(hipsPos)
      : 0;

    const chestCircumference = shoulderWidth * Math.PI * 0.85;
    const waistCircumference = hipWidth * Math.PI * 0.90;
    const headCircumference = head ? 0.55 : 0;

    const measurements: BodyMeasurements = {
      height, shoulderWidth, hipWidth, chestCircumference,
      waistCircumference, armLength, legLength, torsoLength, headCircumference,
    };

    console.log(TAG, 'measurements:', measurements);
    return measurements;
  }

  private stripPrefix(name: string): string {
    const prefixes = ['mixamorig:', 'mixamorig', 'Armature|', 'Root|', 'rig|'];
    let n = name;
    for (const prefix of prefixes) {
      if (n.startsWith(prefix)) {
        n = n.slice(prefix.length);
        break;
      }
    }
    return n;
  }
}
