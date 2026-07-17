import type { TestCase } from './framework/types';
import { PerformanceProfiler } from '../debug/PerformanceProfiler';

function makeFakeRenderer(): any {
  return { info: { render: { calls: 5, triangles: 1000, lines: 0, points: 0 }, memory: { geometries: 3, textures: 2 }, programs: [{}, {}] } };
}

export const PerformanceProfilerTests: TestCase[] = [
  {
    id: 'profiler.basic_frame', name: 'PerformanceProfiler - basic frame', subsystem: 'PerformanceProfiler',
    async run(ctx) {
      const prof = new PerformanceProfiler();
      const fake = makeFakeRenderer();
      prof.beginFrame();
      await sleep(16);
      prof.endFrame(fake, { animationTimeMs: 2, gpuMemoryBytes: 1024 * 1024 });
      const s = prof.getLatest();
      ctx.expect('frameNumber = 0 (first frame)', s.frameNumber === 0);
      ctx.expect('frameTimeMs > 0', s.frameTimeMs > 0);
      ctx.expect('fps > 0', s.fps > 0);
      ctx.expect('drawCalls = 5', s.drawCalls === 5);
      ctx.expect('triangles = 1000', s.triangles === 1000);
      ctx.expect('geometries = 3', s.geometries === 3);
      ctx.expect('textures = 2', s.textures === 2);
      ctx.expect('programs = 2', s.programs === 2);
      ctx.expect('animationTimeMs = 2', s.animationTimeMs === 2);
      ctx.expect('gpuMem ~1MB', Math.abs(s.estimatedGpuMemoryMB - 1) < 0.01);
    },
  },
  {
    id: 'profiler.rolling_stats', name: 'PerformanceProfiler - rolling stats', subsystem: 'PerformanceProfiler',
    async run(ctx) {
      const prof = new PerformanceProfiler();
      const fake = makeFakeRenderer();
      for (let i = 0; i < 10; i++) { prof.beginFrame(); await sleep(10); prof.endFrame(fake); }
      const r = prof.getRollingStats();
      ctx.expect('sampleCount = 10', r.sampleCount === 10);
      ctx.expect('fpsAvg > 0', r.fpsAvg > 0);
      ctx.expect('frameTimeAvgMs > 0', r.frameTimeAvgMs > 0);
      ctx.expect('min <= max', r.frameTimeMinMs <= r.frameTimeMaxMs);
      ctx.expect('drawCallsAvg = 5', r.drawCallsAvg === 5);
      ctx.expect('trianglesAvg = 1000', r.trianglesAvg === 1000);
    },
  },
  {
    id: 'profiler.fps_calculation', name: 'PerformanceProfiler - FPS calculation', subsystem: 'PerformanceProfiler',
    async run(ctx) {
      const prof = new PerformanceProfiler();
      const fake = makeFakeRenderer();
      prof.beginFrame();
      await sleep(16);
      prof.endFrame(fake);
      const s = prof.getLatest();
      const expected = 1000 / s.frameTimeMs;
      ctx.expect('fps ~ 1000/frameTime', Math.abs(s.fps - expected) < 1);
    },
  },
  {
    id: 'profiler.subscriber', name: 'PerformanceProfiler - subscriber', subsystem: 'PerformanceProfiler',
    async run(ctx) {
      const prof = new PerformanceProfiler();
      const fake = makeFakeRenderer();
      let calls = 0;
      const unsub = prof.subscribe(() => { calls++; }, 5);
      for (let i = 0; i < 12; i++) { prof.beginFrame(); prof.endFrame(fake); }
      ctx.expect('called 2 times', calls === 2, '2', `${calls}`);
      unsub();
      for (let i = 0; i < 10; i++) { prof.beginFrame(); prof.endFrame(fake); }
      ctx.expect('not called after unsub', calls === 2);
    },
  },
  {
    id: 'profiler.reset', name: 'PerformanceProfiler - reset', subsystem: 'PerformanceProfiler',
    async run(ctx) {
      const prof = new PerformanceProfiler();
      const fake = makeFakeRenderer();
      for (let i = 0; i < 5; i++) { prof.beginFrame(); prof.endFrame(fake); }
      ctx.expect('advanced before reset', prof.getLatest().frameNumber === 4);
      prof.reset();
      ctx.expect('frameNumber = 0 after reset', prof.getLatest().frameNumber === 0);
      ctx.expect('sampleCount = 0', prof.getRollingStats().sampleCount === 0);
    },
  },
];

function sleep(ms: number): Promise<void> { return new Promise((r) => setTimeout(r, ms)); }
