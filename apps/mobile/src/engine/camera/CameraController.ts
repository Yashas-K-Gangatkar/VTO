/**
 * engine/camera/CameraController.ts
 *
 * Orbit camera with frame-rate-independent damping, target tracking,
 * and constraint enforcement.
 *
 * The controller owns NO three.js objects — it just maintains
 * {yaw, pitch, distance, target} state and applies it to a camera
 * passed in by the Engine.
 */

import * as THREE from 'three';
import {
  CameraConstraints,
  DEFAULT_VTO_CONSTRAINTS,
  clamp,
  damp,
} from './CameraConstraints';
import type { Vec3 } from '../core/types';

const TAG = '[CameraController]';

export interface CameraState {
  yaw: number;
  pitch: number;
  distance: number;
  targetX: number;
  targetY: number;
  targetZ: number;
  fov: number;
}

export interface ICameraController {
  orbitBy(dYaw: number, dPitch: number): void;
  zoomBy(factor: number): void;
  panTargetBy(dx: number, dy: number, dz: number): void;
  focusOn(target: Vec3, smooth?: boolean): void;
  reset(): void;
  update(dtSec: number): void;
  apply(camera: THREE.PerspectiveCamera): void;
  getState(): CameraState;
  getVelocity(): { yaw: number; pitch: number; zoom: number };
  setConstraints(c: CameraConstraints): void;
  markInteracting(): void;
}

export interface CameraControllerOptions {
  constraints?: CameraConstraints;
  initialState?: Partial<CameraState>;
}

export class CameraController implements ICameraController {
  private constraints: CameraConstraints;
  private current: CameraState;
  private target: CameraState;
  private velocity = { yaw: 0, pitch: 0, zoom: 0 };
  private lastInteractionAt: number = 0;
  private autoRotateActive = false;

  constructor(opts: CameraControllerOptions = {}) {
    this.constraints = opts.constraints ?? { ...DEFAULT_VTO_CONSTRAINTS };
    const defaults: CameraState = {
      yaw: 0,
      pitch: 0.2,
      distance: 4,
      targetX: 0,
      targetY: 0.5,
      targetZ: 0,
      fov: 50,
    };
    const init = { ...defaults, ...(opts.initialState ?? {}) };
    this.current = { ...init };
    this.target = { ...init };
  }

  orbitBy(dYaw: number, dPitch: number): void {
    const c = this.constraints;
    const sYaw = c.invertYaw ? -1 : 1;
    const sPitch = c.invertPitch ? -1 : 1;
    const scaledYaw = dYaw * c.rotationSensitivity * sYaw;
    const scaledPitch = dPitch * c.rotationSensitivity * sPitch;
    this.velocity.yaw = scaledYaw;
    this.velocity.pitch = scaledPitch;
    this.target.yaw += scaledYaw;
    this.target.pitch += scaledPitch;
    this.markInteracting();
  }

  zoomBy(factor: number): void {
    const c = this.constraints;
    const sZoom = c.invertZoom ? 1 / factor : factor;
    const newDistance = this.target.distance * sZoom * c.zoomSensitivity;
    this.target.distance = clamp(newDistance, c.distanceRange);
    this.velocity.zoom = (this.target.distance - this.current.distance) * 5;
    this.markInteracting();
  }

  panTargetBy(dx: number, dy: number, dz: number): void {
    this.target.targetX += dx;
    this.target.targetY += dy;
    this.target.targetZ += dz;
    this.markInteracting();
  }

  focusOn(target: Vec3, smooth: boolean = true): void {
    this.target.targetX = target.x;
    this.target.targetY = target.y;
    this.target.targetZ = target.z;
    if (!smooth) {
      this.current.targetX = target.x;
      this.current.targetY = target.y;
      this.current.targetZ = target.z;
    }
    this.markInteracting();
  }

  reset(): void {
    this.target.yaw = 0;
    this.target.pitch = 0.2;
    this.target.distance = 4;
    this.target.targetX = 0;
    this.target.targetY = 0.5;
    this.target.targetZ = 0;
    this.velocity = { yaw: 0, pitch: 0, zoom: 0 };
    this.markInteracting();
  }

  update(dtSec: number): void {
    const c = this.constraints;
    const now = performance.now() / 1000;
    const sinceInteraction = now - this.lastInteractionAt;
    const isInertial = sinceInteraction > 0.05 && sinceInteraction < 1.5;

    if (isInertial) {
      this.velocity.yaw *= c.inertia;
      this.velocity.pitch *= c.inertia;
      this.velocity.zoom *= c.inertia;
      this.target.yaw += this.velocity.yaw * dtSec;
      this.target.pitch += this.velocity.pitch * dtSec;
      this.target.distance = clamp(
        this.target.distance + this.velocity.zoom * dtSec,
        c.distanceRange
      );
    } else if (sinceInteraction >= 1.5) {
      this.velocity = { yaw: 0, pitch: 0, zoom: 0 };
    }

    const shouldAutoRotate =
      c.autoRotateSpeed > 0 &&
      sinceInteraction > c.autoRotateDelaySec &&
      Math.abs(this.velocity.yaw) < 0.01;
    if (shouldAutoRotate) {
      this.target.yaw += c.autoRotateSpeed * dtSec;
      this.autoRotateActive = true;
    } else {
      this.autoRotateActive = false;
    }

    this.target.yaw = wrapAngle(this.target.yaw);
    this.target.pitch = clamp(this.target.pitch, c.pitchRange);
    this.target.distance = clamp(this.target.distance, c.distanceRange);
    this.target.fov = clamp(this.target.fov, c.fovRange);

    this.current.yaw = dampAngle(this.current.yaw, this.target.yaw, c.rotationDamping, dtSec);
    this.current.pitch = damp(this.current.pitch, this.target.pitch, c.rotationDamping, dtSec);
    this.current.distance = damp(this.current.distance, this.target.distance, c.zoomDamping, dtSec);
    this.current.targetX = damp(this.current.targetX, this.target.targetX, c.targetDamping, dtSec);
    this.current.targetY = damp(this.current.targetY, this.target.targetY, c.targetDamping, dtSec);
    this.current.targetZ = damp(this.current.targetZ, this.target.targetZ, c.targetDamping, dtSec);
    this.current.fov = damp(this.current.fov, this.target.fov, c.rotationDamping, dtSec);
  }

  apply(camera: THREE.PerspectiveCamera): void {
    const { yaw, pitch, distance, targetX, targetY, targetZ, fov } = this.current;
    const cosPitch = Math.cos(pitch);
    const sinPitch = Math.sin(pitch);
    const cosYaw = Math.cos(yaw);
    const sinYaw = Math.sin(yaw);

    camera.position.x = targetX + distance * sinPitch * sinYaw;
    camera.position.y = targetY + distance * cosPitch;
    camera.position.z = targetZ + distance * sinPitch * cosYaw;

    camera.lookAt(targetX, targetY, targetZ);

    if (camera.fov !== fov) {
      camera.fov = fov;
      camera.updateProjectionMatrix();
    }
  }

  getState(): CameraState {
    return { ...this.current };
  }

  getVelocity(): { yaw: number; pitch: number; zoom: number } {
    return { ...this.velocity };
  }

  setConstraints(c: CameraConstraints): void {
    this.constraints = c;
    this.current.yaw = wrapAngle(this.current.yaw);
    this.current.pitch = clamp(this.current.pitch, c.pitchRange);
    this.current.distance = clamp(this.current.distance, c.distanceRange);
    this.target.yaw = wrapAngle(this.target.yaw);
    this.target.pitch = clamp(this.target.pitch, c.pitchRange);
    this.target.distance = clamp(this.target.distance, c.distanceRange);
  }

  markInteracting(): void {
    this.lastInteractionAt = performance.now() / 1000;
  }

  isAutoRotating(): boolean {
    return this.autoRotateActive;
  }
}

function wrapAngle(a: number): number {
  const TWO_PI = Math.PI * 2;
  let r = a % TWO_PI;
  if (r > Math.PI) r -= TWO_PI;
  if (r < -Math.PI) r += TWO_PI;
  return r;
}

function dampAngle(current: number, target: number, damping: number, dtSec: number): number {
  const c = wrapAngle(current);
  const t = wrapAngle(target);
  let delta = t - c;
  if (delta > Math.PI) delta -= Math.PI * 2;
  if (delta < -Math.PI) delta += Math.PI * 2;
  const closurePerFrame = 1 - Math.pow(1 - damping, dtSec);
  return wrapAngle(c + delta * closurePerFrame);
}
