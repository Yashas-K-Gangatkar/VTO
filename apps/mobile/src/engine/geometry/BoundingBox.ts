/**
 * engine/geometry/BoundingBox.ts
 *
 * Bounding box utilities — computation, transform, intersection, fitting.
 */

import * as THREE from 'three';
import type { BoundingBox as BBox, Vec3 } from '../core/types';

export class BoundingBoxUtils {
  static fromObject(obj: THREE.Object3D): BBox {
    const box = new THREE.Box3().setFromObject(obj);
    return BoundingBoxUtils.fromThreeBox(box);
  }

  static fromThreeBox(box: THREE.Box3): BBox {
    const size = box.getSize(new THREE.Vector3());
    const center = box.getCenter(new THREE.Vector3());
    return {
      min: { x: box.min.x, y: box.min.y, z: box.min.z },
      max: { x: box.max.x, y: box.max.y, z: box.max.z },
      center: { x: center.x, y: center.y, z: center.z },
      size: { x: size.x, y: size.y, z: size.z },
    };
  }

  static toThreeBox(b: BBox): THREE.Box3 {
    return new THREE.Box3(
      new THREE.Vector3(b.min.x, b.min.y, b.min.z),
      new THREE.Vector3(b.max.x, b.max.y, b.max.z)
    );
  }

  static maxDim(b: BBox): number {
    return Math.max(b.size.x, b.size.y, b.size.z);
  }

  static volume(b: BBox): number {
    return b.size.x * b.size.y * b.size.z;
  }

  static contains(b: BBox, p: Vec3): boolean {
    return (
      p.x >= b.min.x && p.x <= b.max.x &&
      p.y >= b.min.y && p.y <= b.max.y &&
      p.z >= b.min.z && p.z <= b.max.z
    );
  }

  static intersects(a: BBox, b: BBox): boolean {
    return !(
      a.max.x < b.min.x || a.min.x > b.max.x ||
      a.max.y < b.min.y || a.min.y > b.max.y ||
      a.max.z < b.min.z || a.min.z > b.max.z
    );
  }

  static fit(source: BBox, target: BBox): { scale: number; offset: Vec3 } {
    const sMax = BoundingBoxUtils.maxDim(source);
    const tMax = BoundingBoxUtils.maxDim(target);
    if (sMax < 1e-6) return { scale: 1, offset: { x: 0, y: 0, z: 0 } };
    const scale = tMax / sMax;
    return {
      scale,
      offset: {
        x: target.center.x - source.center.x * scale,
        y: target.center.y - source.center.y * scale,
        z: target.center.z - source.center.z * scale,
      },
    };
  }

  static toWireframe(b: BBox, color: number = 0x00ff00): THREE.Box3Helper {
    const box = BoundingBoxUtils.toThreeBox(b);
    return new THREE.Box3Helper(box, new THREE.Color(color));
  }

  static lerp(a: BBox, b: BBox, t: number): BBox {
    const lerpVec = (v1: Vec3, v2: Vec3, t: number): Vec3 => ({
      x: v1.x + (v2.x - v1.x) * t,
      y: v1.y + (v2.y - v1.y) * t,
      z: v1.z + (v2.z - v1.z) * t,
    });
    const min = lerpVec(a.min, b.min, t);
    const max = lerpVec(a.max, b.max, t);
    const center = lerpVec(a.center, b.center, t);
    const size = lerpVec(a.size, b.size, t);
    return { min, max, center, size };
  }
}
