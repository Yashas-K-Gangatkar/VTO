#!/bin/bash
set -e
cd /Users/yashas/VTO/apps/mobile

echo "=== Writing engine/animation/AnimationController.ts ==="
cat > src/engine/animation/AnimationController.ts << 'ANIMATIONCONTROLLER_EOF'
/**
 * engine/animation/AnimationController.ts
 *
 * Wraps THREE.AnimationMixer with multi-clip playback, cross-fade
 * transitions, per-clip speed, and pause/resume.
 */

import * as THREE from 'three';
import type { AnimationClipData } from '../core/types';

const TAG = '[AnimationController]';

export type PlayMode = 'once' | 'loop' | 'pingpong';

export interface PlayOptions {
  mode?: PlayMode;
  speed?: number;
  weight?: number;
  fadeInSec?: number;
  fadeOutSec?: number;
  layer?: number;
}

export interface ActiveClip {
  name: string;
  action: THREE.AnimationAction;
  mode: PlayMode;
  speed: number;
  weight: number;
  layer: number;
  startedAt: number;
}

export interface IAnimationController {
  registerClip(name: string, clip: AnimationClipData | THREE.AnimationClip): void;
  play(name: string, opts?: PlayOptions): void;
  stop(name: string, fadeSec?: number): void;
  stopAll(fadeSec?: number): void;
  crossFade(fromName: string, toName: string, durationSec: number, opts?: PlayOptions): void;
  pause(): void;
  resume(): void;
  setTimeScale(scale: number): void;
  update(dtSec: number): void;
  setTarget(target: THREE.Object3D): void;
  getMixer(): THREE.AnimationMixer | null;
  getActiveClips(): ActiveClip[];
  listClips(): string[];
  dispose(): void;
}

export interface AnimationControllerOptions {
  target: THREE.Object3D;
}

export class AnimationController implements IAnimationController {
  private mixer: THREE.AnimationMixer | null = null;
  private target: THREE.Object3D;
  private clips = new Map<string, THREE.AnimationClip>();
  private active = new Map<string, ActiveClip>();
  private paused = false;
  private timeScale = 1.0;
  private pendingFades: Array<{
    fromName: string;
    toName: string;
    durationSec: number;
    startedAt: number;
    opts?: PlayOptions;
  }> = [];
  private lastUpdateMs = 0;
  private activeTweens: Array<{
    action: THREE.AnimationAction;
    from: number;
    to: number;
    durationSec: number;
    startedAt: number;
    onComplete?: () => void;
  }> = [];

  constructor(opts: AnimationControllerOptions) {
    this.target = opts.target;
    this.mixer = new THREE.AnimationMixer(this.target);
  }

  setTarget(target: THREE.Object3D): void {
    if (this.target === target) return;
    if (this.mixer) {
      this.mixer.stopAllAction();
      this.mixer.uncacheRoot(this.target);
    }
    this.target = target;
    this.mixer = new THREE.AnimationMixer(target);
    console.log(TAG, `retargeted mixer to new root`);
  }

  registerClip(name: string, clip: AnimationClipData | THREE.AnimationClip): void {
    const threeClip = clip instanceof THREE.AnimationClip
      ? clip
      : new THREE.AnimationClip(name, clip.duration, clip.tracks);
    this.clips.set(name, threeClip);
    console.log(TAG, `registered clip "${name}" (${threeClip.duration.toFixed(2)}s, ${threeClip.tracks.length} tracks)`);
  }

  play(name: string, opts: PlayOptions = {}): void {
    if (!this.mixer) {
      console.warn(TAG, 'play: mixer not initialized');
      return;
    }
    const clip = this.clips.get(name);
    if (!clip) {
      console.warn(TAG, `play: clip "${name}" not registered`);
      return;
    }

    const mode = opts.mode ?? 'loop';
    const speed = opts.speed ?? 1.0;
    const weight = opts.weight ?? 1.0;
    const fadeIn = opts.fadeInSec ?? 0.3;
    const layer = opts.layer ?? 0;

    const action = this.mixer.clipAction(clip);
    action.setLoop(
      mode === 'loop' ? THREE.LoopRepeat :
      mode === 'pingpong' ? THREE.LoopPingPong :
      THREE.LoopOnce,
      Infinity
    );
    action.clampWhenFinished = mode === 'once';
    action.timeScale = speed;
    action.weight = 0;
    action.setEffectiveWeight(0);

    action.reset();
    action.play();

    const active: ActiveClip = {
      name, action, mode, speed, weight, layer,
      startedAt: performance.now() / 1000,
    };
    this.active.set(name, active);

    if (fadeIn > 0) {
      action.setEffectiveWeight(0);
      this.tweenWeight(action, 0, weight, fadeIn);
    } else {
      action.setEffectiveWeight(weight);
    }

    console.log(TAG, `play "${name}" mode=${mode} speed=${speed} layer=${layer}`);
  }

  stop(name: string, fadeSec: number = 0.3): void {
    const active = this.active.get(name);
    if (!active) return;

    if (fadeSec > 0) {
      this.tweenWeight(active.action, active.action.getEffectiveWeight(), 0, fadeSec, () => {
        active.action.stop();
        this.active.delete(name);
      });
    } else {
      active.action.stop();
      this.active.delete(name);
    }
  }

  stopAll(fadeSec: number = 0.3): void {
    for (const name of Array.from(this.active.keys())) {
      this.stop(name, fadeSec);
    }
  }

  crossFade(fromName: string, toName: string, durationSec: number, opts?: PlayOptions): void {
    if (!this.active.has(fromName)) {
      this.play(toName, opts);
      return;
    }
    this.pendingFades.push({
      fromName, toName, durationSec,
      startedAt: performance.now() / 1000,
      opts,
    });
    this.play(toName, { ...opts, fadeInSec: durationSec });
  }

  pause(): void {
    this.paused = true;
    for (const active of this.active.values()) {
      active.action.paused = true;
    }
  }

  resume(): void {
    this.paused = false;
    for (const active of this.active.values()) {
      active.action.paused = false;
    }
  }

  setTimeScale(scale: number): void {
    this.timeScale = scale;
    if (this.mixer) this.mixer.timeScale = scale;
  }

  update(dtSec: number): void {
    if (!this.mixer || this.paused) return;

    const start = performance.now();
    this.mixer.update(dtSec * this.timeScale);

    this.updateTweens();

    const now = performance.now() / 1000;
    for (let i = this.pendingFades.length - 1; i >= 0; i--) {
      const fade = this.pendingFades[i];
      const elapsed = now - fade.startedAt;
      if (elapsed >= fade.durationSec) {
        this.stop(fade.fromName, 0);
        this.pendingFades.splice(i, 1);
      }
    }

    for (const [name, active] of this.active) {
      if (active.mode === 'once' && !active.action.isRunning()) {
        this.active.delete(name);
      }
    }

    this.lastUpdateMs = performance.now() - start;
  }

  getMixer(): THREE.AnimationMixer | null {
    return this.mixer;
  }

  getActiveClips(): ActiveClip[] {
    return Array.from(this.active.values());
  }

  listClips(): string[] {
    return Array.from(this.clips.keys());
  }

  getLastUpdateMs(): number {
    return this.lastUpdateMs;
  }

  dispose(): void {
    if (this.mixer) {
      this.mixer.stopAllAction();
      this.mixer.uncacheRoot(this.target);
      this.mixer = null;
    }
    this.clips.clear();
    this.active.clear();
    this.pendingFades = [];
  }

  private tweenWeight(
    action: THREE.AnimationAction,
    from: number,
    to: number,
    durationSec: number,
    onComplete?: () => void
  ): void {
    if (durationSec <= 0) {
      action.setEffectiveWeight(to);
      onComplete?.();
      return;
    }
    this.activeTweens.push({
      action, from, to, durationSec,
      startedAt: performance.now() / 1000,
      onComplete,
    });
  }

  private updateTweens(): void {
    const now = performance.now() / 1000;
    for (let i = this.activeTweens.length - 1; i >= 0; i--) {
      const t = this.activeTweens[i];
      const elapsed = now - t.startedAt;
      const pct = Math.min(elapsed / t.durationSec, 1);
      const eased = pct < 0.5 ? 2 * pct * pct : 1 - Math.pow(-2 * pct + 2, 2) / 2;
      const w = t.from + (t.to - t.from) * eased;
      t.action.setEffectiveWeight(w);
      if (pct >= 1) {
        this.activeTweens.splice(i, 1);
        t.onComplete?.();
      }
    }
  }
}
ANIMATIONCONTROLLER_EOF
echo "✓ engine/animation/AnimationController.ts"

echo "=== Writing engine/animation/SkeletonRetargeter.ts ==="
cat > src/engine/animation/SkeletonRetargeter.ts << 'SKELETONRETARGETER_EOF'
/**
 * engine/animation/SkeletonRetargeter.ts
 *
 * Retargets animations from a source skeleton to a target skeleton.
 * Handles bone name mapping (Mixamo prefix stripping) + length preservation.
 */

import * as THREE from 'three';
import type { SkeletonData, AnimationClipData } from '../core/types';

const TAG = '[SkeletonRetargeter]';

export interface BoneMapping {
  mapping: Record<string, string>;
  method: 'exact' | 'prefix-strip' | 'manual';
  matchedCount: number;
  unmatched: string[];
}

export interface RetargetOptions {
  preserveLengths: boolean;
  stripPrefixes: string[];
  manualMapping?: Record<string, string>;
  translationScale: number;
}

export const DEFAULT_RETARGET_OPTS: RetargetOptions = {
  preserveLengths: true,
  stripPrefixes: ['mixamorig:', 'mixamorig', 'Armature|', 'Root|'],
  translationScale: 1.0,
};

export interface ISkeletonRetargeter {
  buildMapping(source: SkeletonData, target: SkeletonData, opts?: RetargetOptions): BoneMapping;
  retargetClip(
    clip: AnimationClipData | THREE.AnimationClip,
    mapping: BoneMapping,
    source: SkeletonData,
    target: SkeletonData,
    opts?: RetargetOptions
  ): THREE.AnimationClip;
}

export class SkeletonRetargeter implements ISkeletonRetargeter {
  buildMapping(
    source: SkeletonData,
    target: SkeletonData,
    opts: RetargetOptions = DEFAULT_RETARGET_OPTS
  ): BoneMapping {
    const sourceBoneNames = Object.keys(source.boneLengths);
    const targetBoneNames = Object.keys(target.boneLengths);

    const normalize = (name: string): string => {
      let n = name;
      for (const prefix of opts.stripPrefixes) {
        if (n.startsWith(prefix)) {
          n = n.slice(prefix.length);
          break;
        }
      }
      return n.toLowerCase();
    };

    const sourceNormToOrig = new Map<string, string>();
    for (const n of sourceBoneNames) sourceNormToOrig.set(normalize(n), n);
    const targetNormToOrig = new Map<string, string>();
    for (const n of targetBoneNames) targetNormToOrig.set(normalize(n), n);

    const mapping: Record<string, string> = {};
    if (opts.manualMapping) {
      for (const [src, tgt] of Object.entries(opts.manualMapping)) {
        if (sourceNormToOrig.has(src) && targetNormToOrig.has(tgt)) {
          mapping[sourceNormToOrig.get(src)!] = targetNormToOrig.get(tgt)!;
        }
      }
    }

    let method: BoneMapping['method'] = 'exact';
    if (Object.keys(mapping).length === 0) {
      for (const src of sourceBoneNames) {
        const tgt = targetBoneNames.find((t) => t === src);
        if (tgt) mapping[src] = tgt;
      }
    }

    if (Object.keys(mapping).length === 0) {
      method = 'prefix-strip';
      for (const [norm, src] of sourceNormToOrig) {
        const tgt = targetNormToOrig.get(norm);
        if (tgt) mapping[src] = tgt;
      }
    }

    const matchedCount = Object.keys(mapping).length;
    const unmatched = sourceBoneNames.filter((n) => !mapping[n]);

    console.log(TAG, `bone mapping: ${matchedCount}/${sourceBoneNames.length} matched (method=${method}), ${unmatched.length} unmatched`);

    return { mapping, method, matchedCount, unmatched };
  }

  retargetClip(
    clip: AnimationClipData | THREE.AnimationClip,
    mapping: BoneMapping,
    source: SkeletonData,
    target: SkeletonData,
    opts: RetargetOptions = DEFAULT_RETARGET_OPTS
  ): THREE.AnimationClip {
    const threeClip = clip instanceof THREE.AnimationClip
      ? clip
      : new THREE.AnimationClip('retargeted', clip.duration, clip.tracks);

    const newTracks: THREE.KeyframeTrack[] = [];

    for (const track of threeClip.tracks) {
      const dotIdx = track.name.lastIndexOf('.');
      if (dotIdx < 0) {
        newTracks.push(track.clone());
        continue;
      }
      const boneName = track.name.substring(0, dotIdx);
      const property = track.name.substring(dotIdx + 1);

      const targetBone = mapping.mapping[boneName];
      if (!targetBone) continue;

      const newTrackName = `${targetBone}.${property}`;
      let newTrack: THREE.KeyframeTrack;

      if (property === 'position' && opts.preserveLengths) {
        const srcLen = source.boneLengths[boneName] ?? 1;
        const tgtLen = target.boneLengths[targetBone] ?? 1;
        const ratio = (tgtLen / srcLen) * opts.translationScale;

        const values = (track as any).values as Float32Array | number[];
        const newValues = new Float32Array(values.length);
        for (let i = 0; i < values.length; i++) {
          newValues[i] = values[i] * ratio;
        }
        newTrack = new (track.constructor as any)(
          newTrackName,
          (track as any).times,
          newValues,
          (track as any).interpolation
        );
      } else {
        newTrack = track.clone();
        newTrack.name = newTrackName;
      }
      newTracks.push(newTrack);
    }

    return new THREE.AnimationClip(threeClip.name + '_retargeted', threeClip.duration, newTracks);
  }

  autoRetarget(
    clip: AnimationClipData | THREE.AnimationClip,
    source: SkeletonData,
    target: SkeletonData,
    opts?: Partial<RetargetOptions>
  ): THREE.AnimationClip | null {
    const fullOpts = { ...DEFAULT_RETARGET_OPTS, ...opts };
    const mapping = this.buildMapping(source, target, fullOpts);
    if (mapping.matchedCount === 0) {
      console.warn(TAG, 'autoRetarget: no bones matched — clip cannot be retargeted');
      return null;
    }
    return this.retargetClip(clip, mapping, source, target, fullOpts);
  }
}
SKELETONRETARGETER_EOF
echo "✓ engine/animation/SkeletonRetargeter.ts"

echo "=== Writing engine/skeleton/SkeletonDetector.ts ==="
cat > src/engine/skeleton/SkeletonDetector.ts << 'SKELETONDETECTOR_EOF'
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
SKELETONDETECTOR_EOF
echo "✓ engine/skeleton/SkeletonDetector.ts"

echo "=== Writing engine/skeleton/BodyProportions.ts ==="
cat > src/engine/skeleton/BodyProportions.ts << 'BODYPROPORTIONS_EOF'
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
BODYPROPORTIONS_EOF
echo "✓ engine/skeleton/BodyProportions.ts"

echo "=== Writing engine/skeleton/GarmentFitter.ts ==="
cat > src/engine/skeleton/GarmentFitter.ts << 'GARMENTFITTER_EOF'
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
GARMENTFITTER_EOF
echo "✓ engine/skeleton/GarmentFitter.ts"

echo "=== Writing engine/debug/PerformanceProfiler.ts ==="
cat > src/engine/debug/PerformanceProfiler.ts << 'PERFORMANCEPROFILER_EOF'
/**
 * engine/debug/PerformanceProfiler.ts
 *
 * Measures per-frame rendering performance.
 */

import * as THREE from 'three';
import type { FrameStats } from '../core/types';

const TAG = '[PerformanceProfiler]';

const FRAME_HISTORY_SIZE = 60;
const SECOND_MS = 1000;

export interface IPerformanceProfiler {
  beginFrame(): void;
  beginRender(): void;
  endRender(): void;
  endFrame(renderer: THREE.WebGLRenderer, opts?: { animationTimeMs?: number; gpuMemoryBytes?: number }): FrameStats;
  getLatest(): FrameStats;
  getRollingStats(): RollingStats;
  subscribe(listener: (stats: FrameStats) => void, everyNFrames?: number): () => void;
  reset(): void;
}

export interface RollingStats {
  fpsAvg: number;
  fpsMin: number;
  fpsMax: number;
  frameTimeAvgMs: number;
  frameTimeMinMs: number;
  frameTimeMaxMs: number;
  drawCallsAvg: number;
  trianglesAvg: number;
  renderTimeAvgMs: number;
  animationTimeAvgMs: number;
  sampleCount: number;
}

export class PerformanceProfiler implements IPerformanceProfiler {
  private frameCount = 0;
  private currentFrameStart = 0;
  private currentRenderStart = 0;
  private latest: FrameStats | null = null;

  private frameTimes: number[] = [];
  private fpsHistory: number[] = [];
  private drawCallHistory: number[] = [];
  private triangleHistory: number[] = [];
  private renderTimeHistory: number[] = [];
  private animationTimeHistory: number[] = [];

  private listeners = new Set<{ cb: (s: FrameStats) => void; everyN: number }>();

  beginFrame(): void {
    this.currentFrameStart = performance.now();
  }

  beginRender(): void {
    this.currentRenderStart = performance.now();
  }

  endRender(): void {
    // Time is read in endFrame
  }

  endFrame(renderer: THREE.WebGLRenderer, opts: { animationTimeMs?: number; gpuMemoryBytes?: number } = {}): FrameStats {
    const now = performance.now();
    const frameTimeMs = now - this.currentFrameStart;
    const renderTimeMs = this.currentRenderStart > 0 ? (now - this.currentRenderStart) : 0;
    const animationTimeMs = opts.animationTimeMs ?? 0;

    const info = (renderer as any).info;
    const renderInfo = info?.render ?? {};
    const memoryInfo = info?.memory ?? {};

    const fps = frameTimeMs > 0 ? SECOND_MS / frameTimeMs : 0;

    let jsHeapUsedMB = 0;
    let jsHeapTotalMB = 0;
    // @ts-ignore
    if (typeof performance !== 'undefined' && (performance as any).memory) {
      // @ts-ignore
      const mem = (performance as any).memory;
      jsHeapUsedMB = mem.usedJSHeapSize / (1024 * 1024);
      jsHeapTotalMB = mem.totalJSHeapSize / (1024 * 1024);
    }

    const stats: FrameStats = {
      frameNumber: this.frameCount,
      frameTimeMs,
      fps,
      drawCalls: renderInfo.calls ?? 0,
      triangles: renderInfo.triangles ?? 0,
      geometries: memoryInfo.geometries ?? 0,
      textures: memoryInfo.textures ?? 0,
      programs: info?.programs?.length ?? 0,
      jsHeapUsedMB,
      jsHeapTotalMB,
      estimatedGpuMemoryMB: (opts.gpuMemoryBytes ?? 0) / (1024 * 1024),
      animationTimeMs,
      renderTimeMs,
    };

    this.frameTimes.push(frameTimeMs);
    this.fpsHistory.push(fps);
    this.drawCallHistory.push(stats.drawCalls);
    this.triangleHistory.push(stats.triangles);
    this.renderTimeHistory.push(renderTimeMs);
    this.animationTimeHistory.push(animationTimeMs);

    if (this.frameTimes.length > FRAME_HISTORY_SIZE) this.frameTimes.shift();
    if (this.fpsHistory.length > FRAME_HISTORY_SIZE) this.fpsHistory.shift();
    if (this.drawCallHistory.length > FRAME_HISTORY_SIZE) this.drawCallHistory.shift();
    if (this.triangleHistory.length > FRAME_HISTORY_SIZE) this.triangleHistory.shift();
    if (this.renderTimeHistory.length > FRAME_HISTORY_SIZE) this.renderTimeHistory.shift();
    if (this.animationTimeHistory.length > FRAME_HISTORY_SIZE) this.animationTimeHistory.shift();

    this.latest = stats;
    this.frameCount++;

    for (const l of this.listeners) {
      if (this.frameCount % l.everyN === 0) {
        try { l.cb(stats); } catch (e) { /* swallow */ }
      }
    }

    return stats;
  }

  getLatest(): FrameStats {
    return this.latest ?? {
      frameNumber: 0, frameTimeMs: 0, fps: 0, drawCalls: 0, triangles: 0,
      geometries: 0, textures: 0, programs: 0, jsHeapUsedMB: 0, jsHeapTotalMB: 0,
      estimatedGpuMemoryMB: 0, animationTimeMs: 0, renderTimeMs: 0,
    };
  }

  getRollingStats(): RollingStats {
    const n = this.frameTimes.length;
    if (n === 0) {
      return {
        fpsAvg: 0, fpsMin: 0, fpsMax: 0,
        frameTimeAvgMs: 0, frameTimeMinMs: 0, frameTimeMaxMs: 0,
        drawCallsAvg: 0, trianglesAvg: 0,
        renderTimeAvgMs: 0, animationTimeAvgMs: 0,
        sampleCount: 0,
      };
    }
    const sum = (arr: number[]): number => arr.reduce((a, b) => a + b, 0);
    const avg = (arr: number[]): number => sum(arr) / arr.length;
    const min = (arr: number[]): number => Math.min(...arr);
    const max = (arr: number[]): number => Math.max(...arr);

    return {
      fpsAvg: avg(this.fpsHistory),
      fpsMin: min(this.fpsHistory),
      fpsMax: max(this.fpsHistory),
      frameTimeAvgMs: avg(this.frameTimes),
      frameTimeMinMs: min(this.frameTimes),
      frameTimeMaxMs: max(this.frameTimes),
      drawCallsAvg: avg(this.drawCallHistory),
      trianglesAvg: avg(this.triangleHistory),
      renderTimeAvgMs: avg(this.renderTimeHistory),
      animationTimeAvgMs: avg(this.animationTimeHistory),
      sampleCount: n,
    };
  }

  subscribe(listener: (stats: FrameStats) => void, everyNFrames: number = 30): () => void {
    const entry = { cb: listener, everyN: everyNFrames };
    this.listeners.add(entry);
    return () => this.listeners.delete(entry);
  }

  reset(): void {
    this.frameCount = 0;
    this.frameTimes = [];
    this.fpsHistory = [];
    this.drawCallHistory = [];
    this.triangleHistory = [];
    this.renderTimeHistory = [];
    this.animationTimeHistory = [];
    this.latest = null;
  }
}
PERFORMANCEPROFILER_EOF
echo "✓ engine/debug/PerformanceProfiler.ts"

echo "=== Writing engine/debug/DebugOverlay.tsx ==="
cat > src/engine/debug/DebugOverlay.tsx << 'DEBUGOVERLAY_EOF'
/**
 * engine/debug/DebugOverlay.tsx
 *
 * On-screen HUD showing live engine stats.
 */

import React, { useState, useEffect, useRef } from 'react';
import {
  View, Text, TouchableOpacity, StyleSheet, PanResponder,
  GestureResponderEvent,
} from 'react-native';
import type {
  IPerformanceProfiler, FrameStats, RollingStats,
} from './PerformanceProfiler';
import type { IAssetManager } from '../assets/AssetManager';
import type { ILODSystem } from '../geometry/LODSystem';
import type { IMaterialSystem } from '../materials/MaterialSystem';
import type { ICameraController } from '../camera/CameraController';

const TAG = '[DebugOverlay]';

export interface DebugOverlayProps {
  profiler: IPerformanceProfiler;
  assetManager?: IAssetManager;
  lodSystem?: ILODSystem;
  materialSystem?: IMaterialSystem;
  cameraController?: ICameraController;
  initialPosition?: { x: number; y: number };
  startCollapsed?: boolean;
  updateEveryNFrames?: number;
}

export function DebugOverlay(props: DebugOverlayProps) {
  const [collapsed, setCollapsed] = useState(props.startCollapsed ?? false);
  const [position, setPosition] = useState(props.initialPosition ?? { x: 240, y: 80 });
  const [stats, setStats] = useState<FrameStats | null>(null);
  const [rolling, setRolling] = useState<RollingStats | null>(null);
  const panRef = useRef({ x: 0, y: 0 });

  useEffect(() => {
    const unsub = props.profiler.subscribe((s) => {
      setStats(s);
      setRolling(props.profiler.getRollingStats());
    }, props.updateEveryNFrames ?? 30);
    return unsub;
  }, [props.profiler, props.updateEveryNFrames]);

  const panResponder = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => true,
      onMoveShouldSetPanResponder: (_, g) => Math.abs(g.dx) > 2 || Math.abs(g.dy) > 2,
      onPanResponderGrant: () => {
        panRef.current = { ...position };
      },
      onPanResponderMove: (_, g) => {
        setPosition({
          x: Math.max(0, panRef.current.x + g.dx),
          y: Math.max(0, panRef.current.y + g.dy),
        });
      },
    })
  ).current;

  if (!stats) return null;

  const fpsColor = (fps: number): string => {
    if (fps >= 55) return '#00FF66';
    if (fps >= 30) return '#FFB74D';
    return '#FF5252';
  };

  const fmt = (n: number, decimals: number = 0): string => {
    return n.toLocaleString(undefined, { maximumFractionDigits: decimals, minimumFractionDigits: 0 });
  };

  return (
    <View
      style={[styles.container, { left: position.x, top: position.y }]}
      pointerEvents="box-none"
    >
      <View style={styles.panel} {...panResponder.panHandlers}>
        <View style={styles.header}>
          <Text style={[styles.fps, { color: fpsColor(stats.fps) }]}>
            {fmt(stats.fps)} FPS
          </Text>
          <Text style={styles.frameTime}>
            {fmt(stats.frameTimeMs, 1)}ms
          </Text>
          <TouchableOpacity
            style={styles.collapseBtn}
            onPress={() => setCollapsed(!collapsed)}
            hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
          >
            <Text style={styles.collapseBtnText}>{collapsed ? 'v' : '^'}</Text>
          </TouchableOpacity>
        </View>

        {!collapsed && (
          <View style={styles.body}>
            <Section title="Frame">
              <Row label="Frame #" value={fmt(stats.frameNumber)} />
              <Row label="Render" value={`${fmt(stats.renderTimeMs, 2)}ms`} />
              <Row label="Animation" value={`${fmt(stats.animationTimeMs, 2)}ms`} />
              <Row label="Avg" value={`${fmt(rolling?.frameTimeAvgMs ?? 0, 2)}ms`} />
              <Row label="Min/Max" value={`${fmt(rolling?.frameTimeMinMs ?? 0, 1)}/${fmt(rolling?.frameTimeMaxMs ?? 0, 1)}ms`} />
            </Section>

            <Section title="GPU">
              <Row label="Draw calls" value={fmt(stats.drawCalls)} />
              <Row label="Triangles" value={fmt(stats.triangles)} />
              <Row label="Geometries" value={fmt(stats.geometries)} />
              <Row label="Textures" value={fmt(stats.textures)} />
              <Row label="Programs" value={fmt(stats.programs)} />
              <Row label="GPU mem" value={`${fmt(stats.estimatedGpuMemoryMB, 1)} MB`} />
            </Section>

            <Section title="Memory">
              <Row label="JS heap" value={`${fmt(stats.jsHeapUsedMB, 1)} / ${fmt(stats.jsHeapTotalMB, 1)} MB`} />
            </Section>

            {props.cameraController && (
              <Section title="Camera">
                <Row label="Yaw" value={`${((props.cameraController.getState().yaw * 180) / Math.PI).toFixed(0)}deg`} />
                <Row label="Pitch" value={`${((props.cameraController.getState().pitch * 180) / Math.PI).toFixed(0)}deg`} />
                <Row label="Distance" value={props.cameraController.getState().distance.toFixed(2)} />
              </Section>
            )}

            {props.lodSystem && (
              <Section title="LOD">
                {(() => {
                  const lodStats = props.lodSystem!.getStats();
                  return (
                    <>
                      <Row label="Groups" value={fmt(lodStats.groupCount)} />
                      <Row label="Variants" value={fmt(lodStats.totalVariants)} />
                      <Row label="Swaps" value={fmt(lodStats.swapsTotal)} />
                      <Row label="High" value={fmt(lodStats.histogram.high)} />
                      <Row label="Med" value={fmt(lodStats.histogram.medium)} />
                      <Row label="Low" value={fmt(lodStats.histogram.low)} />
                    </>
                  );
                })()}
              </Section>
            )}

            {props.materialSystem && (
              <Section title="Materials">
                {(() => {
                  const m = props.materialSystem!.getStats();
                  return (
                    <>
                      <Row label="Instances" value={fmt(m.materials.count)} />
                      <Row label="Refs" value={fmt(m.materials.totalRefs)} />
                      <Row label="Hits/Miss" value={`${m.materials.hits}/${m.materials.misses}`} />
                      <Row label="Tex bytes" value={`${fmt(m.textures.bytes / 1024 / 1024, 1)} MB`} />
                      <Row label="Tex count" value={fmt(m.textures.count)} />
                    </>
                  );
                })()}
              </Section>
            )}

            {props.assetManager && (
              <Section title="Loads">
                {(() => {
                  const loads = props.assetManager!.getActiveLoads();
                  if (loads.length === 0) return <Row label="Active" value="0" />;
                  return loads.map((load) => (
                    <Row
                      key={load.descriptor.id}
                      label={load.descriptor.id.slice(0, 14)}
                      value={`${load.phase} ${(load.overallProgress * 100).toFixed(0)}%`}
                    />
                  ));
                })()}
              </Section>
            )}
          </View>
        )}
      </View>
    </View>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle}>{title}</Text>
      {children}
    </View>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.row}>
      <Text style={styles.rowLabel}>{label}</Text>
      <Text style={styles.rowValue}>{value}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { position: 'absolute', zIndex: 100, minWidth: 180 },
  panel: {
    backgroundColor: 'rgba(0, 0, 0, 0.85)',
    borderRadius: 8,
    borderWidth: 1,
    borderColor: 'rgba(108, 99, 255, 0.4)',
    padding: 8,
  },
  header: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  fps: { fontSize: 16, fontWeight: '700', fontFamily: 'monospace' },
  frameTime: { color: '#AAA', fontSize: 12, fontFamily: 'monospace', flex: 1 },
  collapseBtn: { paddingHorizontal: 6, paddingVertical: 2 },
  collapseBtnText: { color: '#FFF', fontSize: 14 },
  body: { marginTop: 6, gap: 8 },
  section: { borderTopWidth: 1, borderTopColor: 'rgba(255,255,255,0.1)', paddingTop: 4 },
  sectionTitle: {
    color: '#6C63FF', fontSize: 10, fontWeight: '700',
    textTransform: 'uppercase', marginBottom: 2,
  },
  row: { flexDirection: 'row', justifyContent: 'space-between' },
  rowLabel: { color: '#BBB', fontSize: 11, fontFamily: 'monospace' },
  rowValue: { color: '#FFF', fontSize: 11, fontFamily: 'monospace', fontWeight: '600' },
});
DEBUGOVERLAY_EOF
echo "✓ engine/debug/DebugOverlay.tsx"

echo "=== Writing engine/streaming/AssetStreamer.ts ==="
cat > src/engine/streaming/AssetStreamer.ts << 'ASSETSTREAMER_EOF'
/**
 * engine/streaming/AssetStreamer.ts
 *
 * Progressive asset streaming — shows a tiny placeholder immediately
 * while the full-quality asset downloads in the background.
 */

import * as THREE from 'three';
import type {
  AssetDescriptor, LoadedAsset,
} from '../core/types';
import type { IAssetManager } from '../assets/AssetManager';
import type { ILODSystem } from '../geometry/LODSystem';

const TAG = '[AssetStreamer]';

export interface StreamResult {
  preview: LoadedAsset;
  fullReady: Promise<LoadedAsset>;
  cancel: () => void;
}

export interface IAssetStreamer {
  stream(descriptor: AssetDescriptor, opts?: StreamOptions): Promise<StreamResult>;
  getActiveStreams(): StreamStatus[];
}

export interface StreamOptions {
  groupId?: string;
  previewUrl?: string;
  fullUrl?: string;
  crossFadeSec?: number;
  generatePlaceholder?: boolean;
  priority?: number;
}

export interface StreamStatus {
  descriptorId: string;
  phase: 'preview-ready' | 'downloading-full' | 'parsing-full' | 'swapping' | 'complete' | 'cancelled' | 'error';
  progress: number;
  bytesLoaded?: number;
  bytesTotal?: number;
  startedAt: number;
}

export class AssetStreamer implements IAssetStreamer {
  private assetManager: IAssetManager;
  private lodSystem?: ILODSystem;
  private activeStreams = new Map<string, StreamStatus>();
  private maxConcurrentStreams = 2;
  private queue: Array<{ descriptor: AssetDescriptor; opts?: StreamOptions; resolve: (r: StreamResult) => void; reject: (e: any) => void }> = [];

  constructor(assetManager: IAssetManager, lodSystem?: ILODSystem) {
    this.assetManager = assetManager;
    this.lodSystem = lodSystem;
  }

  async stream(descriptor: AssetDescriptor, opts: StreamOptions = {}): Promise<StreamResult> {
    const generatePlaceholder = opts.generatePlaceholder ?? true;

    let preview: LoadedAsset;
    const previewDesc: AssetDescriptor = {
      ...descriptor,
      id: `${descriptor.id}__preview`,
      url: opts.previewUrl ?? (descriptor as any).previewUrl ?? '',
      kind: descriptor.kind,
    };

    if (previewDesc.url) {
      try {
        preview = await this.assetManager.load(previewDesc, { lod: 'preview' });
      } catch (e) {
        console.warn(TAG, `preview load failed for ${descriptor.id}: ${e}`);
        preview = this.generatePlaceholderAsset(descriptor);
      }
    } else if (generatePlaceholder) {
      preview = this.generatePlaceholderAsset(descriptor);
    } else {
      throw new Error(`No previewUrl for ${descriptor.id} and generatePlaceholder=false`);
    }

    const groupId = opts.groupId ?? descriptor.id;
    if (this.lodSystem) {
      this.lodSystem.register(groupId, 'preview', preview);
    }

    let cancelled = false;
    const status: StreamStatus = {
      descriptorId: descriptor.id,
      phase: 'downloading-full',
      progress: 0,
      startedAt: Date.now(),
    };
    this.activeStreams.set(descriptor.id, status);

    const fullReady = new Promise<LoadedAsset>((resolve, reject) => {
      if (this.activeStreams.size > this.maxConcurrentStreams) {
        this.queue.push({ descriptor, opts, resolve, reject });
        return;
      }

      const fullDesc: AssetDescriptor = {
        ...descriptor,
        url: opts.fullUrl ?? descriptor.url,
      };

      this.assetManager.load(fullDesc, { lod: 'high' })
        .then((full) => {
          if (cancelled) {
            this.assetManager.release(full);
            status.phase = 'cancelled';
            return;
          }

          if (this.lodSystem) {
            this.lodSystem.register(groupId, 'high', full, {
              onSwap: (from, to) => {
                if (to === 'high') {
                  status.phase = 'complete';
                  status.progress = 1;
                }
              },
            });

            setTimeout(() => {
              if (!cancelled) {
                this.lodSystem!.forceLOD(groupId, 'high');
                status.phase = 'swapping';
              }
            }, 50);
          }

          status.phase = 'parsing-full';
          status.progress = 0.95;
          resolve(full);
        })
        .catch((e) => {
          status.phase = 'error';
          console.error(TAG, `full load failed for ${descriptor.id}:`, e);
          reject(e);
        });
    });

    const cancel = () => {
      cancelled = true;
      status.phase = 'cancelled';
      this.activeStreams.delete(descriptor.id);
      this.processQueue();
    };

    return { preview, fullReady, cancel };
  }

  getActiveStreams(): StreamStatus[] {
    return Array.from(this.activeStreams.values());
  }

  private processQueue(): void {
    while (this.queue.length > 0 && this.activeStreams.size < this.maxConcurrentStreams) {
      const item = this.queue.shift()!;
      this.stream(item.descriptor, item.opts)
        .then(item.resolve)
        .catch(item.reject);
    }
  }

  private generatePlaceholderAsset(descriptor: AssetDescriptor): LoadedAsset {
    const geom = new THREE.BoxGeometry(0.6, 1.7, 0.3);
    const mat = new THREE.MeshBasicMaterial({
      color: 0x6C63FF, wireframe: true, transparent: true, opacity: 0.4,
    });
    const mesh = new THREE.Mesh(geom, mat);
    const group = new THREE.Group();
    group.add(mesh);

    const box = new THREE.Box3().setFromObject(group);
    const size = box.getSize(new THREE.Vector3());
    const center = box.getCenter(new THREE.Vector3());

    return {
      descriptor: { ...descriptor, id: `${descriptor.id}__placeholder` },
      scene: group,
      bbox: {
        min: { x: box.min.x, y: box.min.y, z: box.min.z },
        max: { x: box.max.x, y: box.max.y, z: box.max.z },
        center: { x: center.x, y: center.y, z: center.z },
        size: { x: size.x, y: size.y, z: size.z },
      },
      stats: {
        meshCount: 1, triangleCount: 12, vertexCount: 8,
        materialCount: 1, textureCount: 0, estimatedMemoryBytes: 384,
      },
      skeleton: null,
      activeLOD: 'preview',
      localPath: '',
      loadTimeMs: 0,
    };
  }
}
ASSETSTREAMER_EOF
echo "✓ engine/streaming/AssetStreamer.ts"

echo ""
echo "=== Part 4 complete ==="
echo "Files written:"
ls -la src/engine/animation/ src/engine/skeleton/ src/engine/debug/ src/engine/streaming/
echo ""
echo "Total engine files so far:"
find src/engine -type f | wc -l
echo ""
