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
