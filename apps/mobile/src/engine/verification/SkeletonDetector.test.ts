/**
 * engine/__tests__/SkeletonDetector.test.ts
 */

import * as THREE from 'three';
import type { TestCase } from './framework/types';
import { SkeletonDetector } from '../skeleton/SkeletonDetector';

function makeFakeRiggedFigure(): THREE.Object3D {
  const root = new THREE.Object3D();
  const armature = new THREE.Group();
  armature.name = 'Armature';
  root.add(armature);

  const hips = new THREE.Bone();
  hips.name = 'Hips';
  hips.position.set(0, 1, 0);
  armature.add(hips);

  const spine = new THREE.Bone();
  spine.name = 'Spine';
  spine.position.set(0, 0.3, 0);
  hips.add(spine);

  const neck = new THREE.Bone();
  neck.name = 'Neck';
  neck.position.set(0, 0.3, 0);
  spine.add(neck);

  const head = new THREE.Bone();
  head.name = 'Head';
  head.position.set(0, 0.15, 0);
  neck.add(head);

  const leftArm = new THREE.Bone();
  leftArm.name = 'LeftArm';
  leftArm.position.set(0.2, 0, 0);
  neck.add(leftArm);

  const rightArm = new THREE.Bone();
  rightArm.name = 'RightArm';
  rightArm.position.set(-0.2, 0, 0);
  neck.add(rightArm);

  const leftLeg = new THREE.Bone();
  leftLeg.name = 'LeftUpLeg';
  leftLeg.position.set(0.1, -0.5, 0);
  hips.add(leftLeg);

  const rightLeg = new THREE.Bone();
  rightLeg.name = 'RightUpLeg';
  rightLeg.position.set(-0.1, -0.5, 0);
  hips.add(rightLeg);

  const bones = [hips, spine, neck, head, leftArm, rightArm, leftLeg, rightLeg];
  const skeleton = new THREE.Skeleton(bones);
  armature.add(new THREE.SkeletonHelper(hips));

  const geom = new THREE.BoxGeometry(0.1, 0.1, 0.1);
  const mat = new THREE.MeshStandardMaterial();
  const skinned = new THREE.SkinnedMesh(geom, mat);
  skinned.add(hips);
  skinned.bind(skeleton);
  armature.add(skinned);

  return root;
}

export const SkeletonDetectorTests: TestCase[] = [
  {
    id: 'skeleton.detect_from_skinned_mesh',
    name: 'SkeletonDetector - extracts skeleton from SkinnedMesh',
    subsystem: 'SkeletonDetector',
    async run(ctx) {
      const detector = new SkeletonDetector();
      const root = makeFakeRiggedFigure();
      const skeleton = detector.detect(root);
      ctx.expect('skeleton returned (not null)', skeleton !== null);
      if (!skeleton) return;
      ctx.expect('THREE.Skeleton object present', skeleton.skeleton instanceof THREE.Skeleton);
      ctx.expect('8 bones detected', skeleton.skeleton.bones.length === 8, '8', `${skeleton.skeleton.bones.length}`);
      ctx.expect('8 entries in boneHierarchy', Object.keys(skeleton.boneHierarchy).length === 8);
      ctx.expect('8 entries in bindPose', Object.keys(skeleton.bindPose).length === 8);
      ctx.expect('8 entries in boneLengths', Object.keys(skeleton.boneLengths).length === 8);
    },
  },
  {
    id: 'skeleton.find_skinned_mesh',
    name: 'SkeletonDetector - findSkinnedMesh() locates the first SkinnedMesh',
    subsystem: 'SkeletonDetector',
    async run(ctx) {
      const detector = new SkeletonDetector();
      const root = makeFakeRiggedFigure();
      const skinned = detector.findSkinnedMesh(root);
      ctx.expect('SkinnedMesh found', skinned !== null);
      ctx.expect('is a THREE.SkinnedMesh', skinned instanceof THREE.SkinnedMesh);
    },
  },
  {
    id: 'skeleton.normalize_name',
    name: 'SkeletonDetector - normalizeBoneName() strips Mixamo prefixes',
    subsystem: 'SkeletonDetector',
    async run(ctx) {
      const detector = new SkeletonDetector();
      ctx.expect('"mixamorig:Head" -> "Head"', detector.normalizeBoneName('mixamorig:Head') === 'Head');
      ctx.expect('"Armature|Spine" -> "Spine"', detector.normalizeBoneName('Armature|Spine') === 'Spine');
      ctx.expect('"Hips" -> "Hips" (no prefix)', detector.normalizeBoneName('Hips') === 'Hips');
    },
  },
  {
    id: 'skeleton.no_skeleton_returns_null',
    name: 'SkeletonDetector - returns null when no skeleton present',
    subsystem: 'SkeletonDetector',
    async run(ctx) {
      const detector = new SkeletonDetector();
      const root = new THREE.Object3D();
      const mesh = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1), new THREE.MeshBasicMaterial());
      root.add(mesh);
      const skeleton = detector.detect(root);
      ctx.expect('returns null (no skinned mesh, no bones)', skeleton === null);
    },
  },
];
