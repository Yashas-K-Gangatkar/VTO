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
