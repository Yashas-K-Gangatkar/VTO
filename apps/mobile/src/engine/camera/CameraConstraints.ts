/**
 * engine/camera/CameraConstraints.ts
 *
 * Declarative limits on camera motion. Pure data — no behavior.
 */

export interface CameraConstraints {
  yawRange: [number, number];
  pitchRange: [number, number];
  distanceRange: [number, number];
  fovRange: [number, number];
  rotationDamping: number;
  zoomDamping: number;
  targetDamping: number;
  autoRotateSpeed: number;
  autoRotateDelaySec: number;
  invertYaw: boolean;
  invertPitch: boolean;
  invertZoom: boolean;
  rotationSensitivity: number;
  zoomSensitivity: number;
  inertia: number;
}

export const DEFAULT_VTO_CONSTRAINTS: CameraConstraints = {
  yawRange: [-Math.PI, Math.PI],
  pitchRange: [(-75 * Math.PI) / 180, (75 * Math.PI) / 180],
  distanceRange: [1.5, 8],
  fovRange: [40, 60],
  rotationDamping: 0.85,
  zoomDamping: 0.9,
  targetDamping: 0.85,
  autoRotateSpeed: 0.1,
  autoRotateDelaySec: 3.0,
  invertYaw: false,
  invertPitch: false,
  invertZoom: false,
  rotationSensitivity: 1.0,
  zoomSensitivity: 1.0,
  inertia: 0.92,
};

export const AVATAR_CUSTOMIZER_CONSTRAINTS: CameraConstraints = {
  ...DEFAULT_VTO_CONSTRAINTS,
  pitchRange: [0, 0],
  distanceRange: [2.5, 5],
  autoRotateSpeed: 0,
  rotationSensitivity: 0.7,
};

export const WALKTHROUGH_CONSTRAINTS: CameraConstraints = {
  ...DEFAULT_VTO_CONSTRAINTS,
  pitchRange: [(-89 * Math.PI) / 180, (89 * Math.PI) / 180],
  distanceRange: [1, 25],
  fovRange: [30, 90],
  autoRotateSpeed: 0,
  rotationSensitivity: 1.5,
  zoomSensitivity: 1.5,
};

export function clamp(value: number, range: [number, number]): number {
  if (value < range[0]) return range[0];
  if (value > range[1]) return range[1];
  return value;
}

export function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

export function damp(
  current: number,
  target: number,
  damping: number,
  dtSec: number
): number {
  const closurePerFrame = 1 - Math.pow(1 - damping, dtSec);
  return lerp(current, target, closurePerFrame);
}
