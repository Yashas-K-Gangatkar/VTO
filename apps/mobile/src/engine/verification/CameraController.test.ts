import * as THREE from 'three';
import type { TestCase } from './framework/types';
import { CameraController } from '../camera/CameraController';
import { DEFAULT_VTO_CONSTRAINTS } from '../camera/CameraConstraints';
import type { CameraConstraints } from '../camera/CameraConstraints';

export const CameraControllerTests: TestCase[] = [
  {
    id: 'camera.initial_state', name: 'CameraController - initial state', subsystem: 'CameraController',
    async run(ctx) {
      const cam = new CameraController();
      const s = cam.getState();
      ctx.expect('yaw = 0', Math.abs(s.yaw) < 0.001);
      ctx.expect('pitch = 0.2', Math.abs(s.pitch - 0.2) < 0.001);
      ctx.expect('distance = 4', Math.abs(s.distance - 4) < 0.001);
      ctx.expect('targetY = 0.5', Math.abs(s.targetY - 0.5) < 0.001);
      ctx.expect('fov = 50', Math.abs(s.fov - 50) < 0.001);
    },
  },
  {
    id: 'camera.orbit_by', name: 'CameraController - orbitBy', subsystem: 'CameraController',
    async run(ctx) {
      const cam = new CameraController();
      cam.orbitBy(0.5, 0.3);
      for (let i = 0; i < 300; i++) await cam.update(1 / 60);
      const s = cam.getState();
      ctx.expect('yaw approx 0.5', Math.abs(s.yaw - 0.5) < 0.2, '0.5+-0.2', s.yaw.toFixed(3));
      ctx.expect('pitch approx 0.5', Math.abs(s.pitch - 0.5) < 0.2, '0.5+-0.2', s.pitch.toFixed(3));
    },
  },
  {
    id: 'camera.pitch_clamped', name: 'CameraController - pitch clamped', subsystem: 'CameraController',
    async run(ctx) {
      const cam = new CameraController();
      cam.orbitBy(0, 10);
      for (let i = 0; i < 300; i++) await cam.update(1 / 60);
      const s = cam.getState();
      const maxPitch = DEFAULT_VTO_CONSTRAINTS.pitchRange[1];
      ctx.expect('pitch <= max', s.pitch <= maxPitch + 0.01);
      ctx.expect('pitch >= -max', s.pitch >= -maxPitch - 0.01);
    },
  },
  {
    id: 'camera.distance_clamped', name: 'CameraController - distance clamped', subsystem: 'CameraController',
    async run(ctx) {
      const cam = new CameraController();
      cam.zoomBy(0.001);
      for (let i = 0; i < 60; i++) await cam.update(1 / 60);
      let s = cam.getState();
      ctx.expect('distance >= 1.5', s.distance >= 1.5 - 0.01);
      cam.zoomBy(100);
      for (let i = 0; i < 60; i++) await cam.update(1 / 60);
      s = cam.getState();
      ctx.expect('distance <= 8', s.distance <= 8 + 0.01);
    },
  },
  {
    id: 'camera.damping', name: 'CameraController - damping', subsystem: 'CameraController',
    async run(ctx) {
      const cam = new CameraController();
      cam.orbitBy(1.0, 0);
      await cam.update(1 / 60);
      const s1 = cam.getState();
      ctx.expect('yaw moved toward target', s1.yaw > 0.01);
      ctx.expect('yaw not yet at target', s1.yaw < 0.5);
      for (let i = 0; i < 300; i++) await cam.update(1 / 60);
      const s2 = cam.getState();
      ctx.expect('yaw approx 1.0 after 5 sec', Math.abs(s2.yaw - 1.0) < 0.2, '1.0+-0.2', s2.yaw.toFixed(3));
    },
  },
  {
    id: 'camera.focus_on', name: 'CameraController - focusOn', subsystem: 'CameraController',
    async run(ctx) {
      const cam = new CameraController();
      cam.focusOn({ x: 1, y: 2, z: 3 });
      for (let i = 0; i < 300; i++) await cam.update(1 / 60);
      const s = cam.getState();
      ctx.expect('targetX approx 1', Math.abs(s.targetX - 1) < 0.2, '1+-0.2', s.targetX.toFixed(3));
      ctx.expect('targetY approx 2', Math.abs(s.targetY - 2) < 0.2);
      ctx.expect('targetZ approx 3', Math.abs(s.targetZ - 3) < 0.2);
    },
  },
  {
    id: 'camera.focus_on_immediate', name: 'CameraController - focusOn immediate', subsystem: 'CameraController',
    async run(ctx) {
      const cam = new CameraController();
      cam.focusOn({ x: 5, y: 5, z: 5 }, false);
      const s = cam.getState();
      ctx.expect('targetX = 5', s.targetX === 5);
      ctx.expect('targetY = 5', s.targetY === 5);
      ctx.expect('targetZ = 5', s.targetZ === 5);
    },
  },
  {
    id: 'camera.reset', name: 'CameraController - reset', subsystem: 'CameraController',
    async run(ctx) {
      const cam = new CameraController();
      cam.orbitBy(1, 1); cam.zoomBy(0.5);
      for (let i = 0; i < 30; i++) await cam.update(1 / 60);
      cam.reset();
      for (let i = 0; i < 300; i++) await cam.update(1 / 60);
      const s = cam.getState();
      ctx.expect('yaw back to 0', Math.abs(s.yaw) < 0.15);
      ctx.expect('pitch back to 0.2', Math.abs(s.pitch - 0.2) < 0.15);
      ctx.expect('distance back to 4', Math.abs(s.distance - 4) < 0.15);
    },
  },
  {
    id: 'camera.apply_to_three_camera', name: 'CameraController - apply to THREE camera', subsystem: 'CameraController',
    async run(ctx) {
      const cam = new CameraController();
      cam.focusOn({ x: 0, y: 0, z: 0 }, false);
      cam.reset();
      for (let i = 0; i < 300; i++) await cam.update(1 / 60);
      const threeCam = new THREE.PerspectiveCamera(50, 1, 0.1, 1000);
      cam.apply(threeCam);
      const dist = Math.sqrt(threeCam.position.x ** 2 + threeCam.position.y ** 2 + threeCam.position.z ** 2);
      ctx.expect('distance ~4', Math.abs(dist - 4) < 0.6, '4+-0.6', dist.toFixed(3));
      ctx.expect('finite position', isFinite(threeCam.position.x) && isFinite(threeCam.position.y) && isFinite(threeCam.position.z));
    },
  },
  {
    id: 'camera.custom_constraints', name: 'CameraController - custom constraints', subsystem: 'CameraController',
    async run(ctx) {
      const tight: CameraConstraints = { ...DEFAULT_VTO_CONSTRAINTS, distanceRange: [3, 5], pitchRange: [0, 0] };
      const cam = new CameraController({ constraints: tight });
      cam.orbitBy(0, 1); cam.zoomBy(0.1);
      for (let i = 0; i < 300; i++) await cam.update(1 / 60);
      const s = cam.getState();
      ctx.expect('pitch locked at 0', Math.abs(s.pitch) < 0.05);
      ctx.expect('distance >= 3', s.distance >= 3 - 0.05);
      ctx.expect('distance <= 5', s.distance <= 5 + 0.05);
    },
  },
];

function isFinite(n: number): boolean { return typeof n === 'number' && globalThis.isFinite(n); }
