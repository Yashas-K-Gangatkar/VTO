/**
 * engine/geometry/MeshOptimizer.ts
 *
 * Reduces mesh complexity in-place using greedy edge collapse.
 *
 * This is a SIMPLIFIED QEM implementation. For production swap in
 * meshoptimizer library (https://github.com/zeux/meshoptimizer).
 */

import * as THREE from 'three';

const TAG = '[MeshOptimizer]';

export interface OptimizationOptions {
  targetTriangles: number;
  preserveBoundaries: boolean;
  recomputeNormals: boolean;
  aggressiveness: number;
}

export const DEFAULT_OPTS: OptimizationOptions = {
  targetTriangles: 5000,
  preserveBoundaries: true,
  recomputeNormals: true,
  aggressiveness: 0.5,
};

export interface OptimizationResult {
  originalTriangles: number;
  originalVertices: number;
  optimizedTriangles: number;
  optimizedVertices: number;
  reductionRatio: number;
  durationMs: number;
}

export class MeshOptimizer {
  optimize(geometry: THREE.BufferGeometry, opts: OptimizationOptions = DEFAULT_OPTS): OptimizationResult {
    const start = performance.now();
    const origTris = this.countTriangles(geometry);
    const origVerts = geometry.attributes.position.count;

    if (origTris <= opts.targetTriangles) {
      this.optimizeVertexCache(geometry);
      return {
        originalTriangles: origTris,
        originalVertices: origVerts,
        optimizedTriangles: origTris,
        optimizedVertices: origVerts,
        reductionRatio: 1.0,
        durationMs: performance.now() - start,
      };
    }

    const result = this.decimate(geometry, opts.targetTriangles, opts);

    if (opts.recomputeNormals) {
      geometry.computeVertexNormals();
    }
    geometry.computeBoundingSphere();
    geometry.computeBoundingBox();

    const optTris = this.countTriangles(geometry);
    const optVerts = geometry.attributes.position.count;

    return {
      originalTriangles: origTris,
      originalVertices: origVerts,
      optimizedTriangles: optTris,
      optimizedVertices: optVerts,
      reductionRatio: optTris / origTris,
      durationMs: performance.now() - start,
    };
  }

  optimizeSkinnedMesh(geometry: THREE.BufferGeometry, _opts: OptimizationOptions): OptimizationResult {
    const start = performance.now();
    const tris = this.countTriangles(geometry);
    const verts = geometry.attributes.position.count;
    this.optimizeVertexCache(geometry);
    return {
      originalTriangles: tris,
      originalVertices: verts,
      optimizedTriangles: tris,
      optimizedVertices: verts,
      reductionRatio: 1.0,
      durationMs: performance.now() - start,
    };
  }

  private countTriangles(geometry: THREE.BufferGeometry): number {
    const pos = geometry.attributes.position;
    if (geometry.index) return geometry.index.count / 3;
    return pos.count / 3;
  }

  private decimate(geometry: THREE.BufferGeometry, targetTriangles: number, opts: OptimizationOptions): void {
    let wasIndexed = false;
    if (geometry.index) {
      geometry.toNonIndexed();
      wasIndexed = true;
    }

    const pos = geometry.attributes.position;
    const positions = pos.array as Float32Array;
    let triangleCount = positions.length / 9;

    const vertices: number[][] = [];
    for (let i = 0; i < positions.length / 3; i++) vertices.push([]);
    for (let t = 0; t < triangleCount; t++) {
      for (let i = 0; i < 3; i++) {
        const vIdx = t * 3 + i;
        vertices[vIdx].push(t);
      }
    }

    let collapseCount = 0;
    const maxCollapses = Math.floor((triangleCount - targetTriangles) / 2);

    while (triangleCount > targetTriangles && collapseCount < maxCollapses) {
      let bestT = -1;
      let bestI = -1;
      let bestLen = Infinity;

      for (let t = 0; t < triangleCount; t++) {
        const base = t * 9;
        if (positions[base] === 0 && positions[base + 1] === 0 && positions[base + 2] === 0) continue;

        for (let i = 0; i < 3; i++) {
          const i1 = base + i * 3;
          const i2 = base + ((i + 1) % 3) * 3;
          const dx = positions[i1] - positions[i2];
          const dy = positions[i1 + 1] - positions[i2 + 1];
          const dz = positions[i1 + 2] - positions[i2 + 2];
          const len = dx * dx + dy * dy + dz * dz;
          if (len < bestLen) {
            bestLen = len;
            bestT = t;
            bestI = i;
          }
        }
      }

      if (bestT < 0) break;

      const base = bestT * 9;
      const v1Base = base + bestI * 3;
      const v2Base = base + ((bestI + 1) % 3) * 3;

      positions[v1Base] = (positions[v1Base] + positions[v2Base]) / 2;
      positions[v1Base + 1] = (positions[v1Base + 1] + positions[v2Base + 1]) / 2;
      positions[v1Base + 2] = (positions[v1Base + 2] + positions[v2Base + 2]) / 2;

      positions[base] = 0; positions[base + 1] = 0; positions[base + 2] = 0;
      positions[base + 3] = 0; positions[base + 4] = 0; positions[base + 5] = 0;
      positions[base + 6] = 0; positions[base + 7] = 0; positions[base + 8] = 0;

      triangleCount--;
      collapseCount++;
    }

    this.compactGeometry(geometry, triangleCount);

    if (wasIndexed) {
      this.reindexGeometry(geometry);
    }

    pos.needsUpdate = true;
  }

  private compactGeometry(geometry: THREE.BufferGeometry, expectedTriangles: number): void {
    const pos = geometry.attributes.position;
    const src = pos.array as Float32Array;
    const dst = new Float32Array(expectedTriangles * 9);

    let writeIdx = 0;
    for (let t = 0; t < src.length / 9; t++) {
      const base = t * 9;
      if (src[base] === 0 && src[base + 1] === 0 && src[base + 2] === 0) continue;
      for (let i = 0; i < 9; i++) dst[writeIdx + i] = src[base + i];
      writeIdx += 9;
    }

    geometry.setAttribute('position', new THREE.BufferAttribute(dst, 3));

    for (const name of ['normal', 'uv', 'color']) {
      const attr = geometry.attributes[name];
      if (!attr) continue;
      const srcAttr = attr.array as Float32Array;
      const itemSize = attr.itemSize;
      const dstAttr = new Float32Array(expectedTriangles * 3 * itemSize);
      let w = 0;
      for (let t = 0; t < src.length / 9; t++) {
        const base = t * 9;
        if (src[base] === 0 && src[base + 1] === 0 && src[base + 2] === 0) continue;
        for (let i = 0; i < 3 * itemSize; i++) {
          dstAttr[w++] = srcAttr[t * 3 * itemSize + i];
        }
      }
      geometry.setAttribute(name, new THREE.BufferAttribute(dstAttr, itemSize));
    }
  }

  private reindexGeometry(geometry: THREE.BufferGeometry): void {
    const pos = geometry.attributes.position;
    const positions = pos.array as Float32Array;
    const vertexCount = positions.length / 3;

    const vertexMap = new Map<string, number>();
    const newIndex: number[] = [];
    const uniquePositions: number[] = [];

    for (let i = 0; i < vertexCount; i++) {
      const x = positions[i * 3];
      const y = positions[i * 3 + 1];
      const z = positions[i * 3 + 2];
      const key = `${x.toFixed(6)},${y.toFixed(6)},${z.toFixed(6)}`;
      let idx = vertexMap.get(key);
      if (idx === undefined) {
        idx = uniquePositions.length / 3;
        uniquePositions.push(x, y, z);
        vertexMap.set(key, idx);
      }
      newIndex.push(idx);
    }

    geometry.setAttribute('position', new THREE.BufferAttribute(new Float32Array(uniquePositions), 3));
    geometry.setIndex(newIndex);
  }

  private optimizeVertexCache(geometry: THREE.BufferGeometry): void {
    // Future: implement Tipsify vertex cache optimization.
    // For now, this is a no-op.
  }
}
