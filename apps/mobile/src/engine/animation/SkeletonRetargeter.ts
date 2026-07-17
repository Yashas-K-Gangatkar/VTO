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
