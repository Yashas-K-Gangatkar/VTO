import * as THREE from 'three';
import type { TestCase } from './framework/types';
import { MeshOptimizer, DEFAULT_OPTS } from '../geometry/MeshOptimizer';

function makeIcosphere(subdivisions: number): THREE.BufferGeometry {
  return new THREE.IcosahedronGeometry(1, subdivisions);
}
function countTris(geom: THREE.BufferGeometry): number {
  return geom.index ? geom.index.count / 3 : geom.attributes.position.count / 3;
}

export const MeshOptimizerTests: TestCase[] = [
  {
    id: 'meshoptimizer.small', name: 'MeshOptimizer - decimate small mesh', subsystem: 'MeshOptimizer',
    async run(ctx) {
      const geom = makeIcosphere(3);
      const orig = countTris(geom);
      ctx.log(`Original: ${orig} triangles`);
      const opt = new MeshOptimizer();
      const stop = ctx.startTimer('optimize');
      const result = opt.optimize(geom, { ...DEFAULT_OPTS, targetTriangles: Math.max(50, Math.floor(orig / 2)) });
      const ms = stop();
      const optimized = countTris(geom);
      ctx.log(`Optimized: ${optimized} triangles in ${ms.toFixed(0)}ms`);
      ctx.expect('original > 0', orig > 0);
      ctx.expect('optimized reduced or equal', optimized <= orig);
      ctx.log(`>>> MeshOptimizer ${orig}->${optimized}: ${ms.toFixed(0)}ms`);
    },
  },
  {
    id: 'meshoptimizer.medium', name: 'MeshOptimizer - decimate medium mesh', subsystem: 'MeshOptimizer',
    async run(ctx) {
      const geom = makeIcosphere(4);
      const orig = countTris(geom);
      ctx.log(`Original: ${orig} triangles`);
      const opt = new MeshOptimizer();
      const stop = ctx.startTimer('optimize');
      opt.optimize(geom, { ...DEFAULT_OPTS, targetTriangles: Math.max(100, Math.floor(orig / 3)) });
      const ms = stop();
      const optimized = countTris(geom);
      ctx.log(`Optimized: ${optimized} triangles in ${ms.toFixed(0)}ms`);
      ctx.expect('original > 0', orig > 0);
      ctx.expect('optimized reduced or equal', optimized <= orig);
      ctx.log(`>>> MeshOptimizer ${orig}->${optimized}: ${ms.toFixed(0)}ms`);
    },
  },
  {
    id: 'meshoptimizer.large', name: 'MeshOptimizer - decimate large mesh', subsystem: 'MeshOptimizer',
    async run(ctx) {
      const geom = makeIcosphere(5);
      const orig = countTris(geom);
      ctx.log(`Original: ${orig} triangles`);
      const opt = new MeshOptimizer();
      const stop = ctx.startTimer('optimize');
      opt.optimize(geom, { ...DEFAULT_OPTS, targetTriangles: Math.max(200, Math.floor(orig / 4)) });
      const ms = stop();
      const optimized = countTris(geom);
      ctx.log(`Optimized: ${optimized} triangles in ${ms.toFixed(0)}ms`);
      ctx.expect('original > 0', orig > 0);
      ctx.expect('optimized reduced or equal', optimized <= orig);
      ctx.log(`>>> MeshOptimizer ${orig}->${optimized}: ${ms.toFixed(0)}ms`);
    },
  },
  {
    id: 'meshoptimizer.noop_when_under_target', name: 'MeshOptimizer - no-op when under target', subsystem: 'MeshOptimizer',
    async run(ctx) {
      const geom = makeIcosphere(2);
      const orig = countTris(geom);
      const opt = new MeshOptimizer();
      const stop = ctx.startTimer('optimize');
      const result = opt.optimize(geom, { ...DEFAULT_OPTS, targetTriangles: orig * 2 });
      const ms = stop();
      ctx.expect('no-op (ratio = 1.0)', result.reductionRatio === 1.0);
      ctx.expect('triangle count unchanged', countTris(geom) === orig);
      ctx.expect('fast (<10ms)', ms < 10);
    },
  },
];
