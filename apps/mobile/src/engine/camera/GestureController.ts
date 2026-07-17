/**
 * engine/camera/GestureController.ts
 *
 * Translates raw React Native touch events into semantic camera commands
 * (orbit, zoom, pan) and forwards them to an ICameraController.
 *
 * Supported gestures:
 *   - 1 finger drag       → orbit (yaw + pitch)
 *   - 2 finger pinch      → zoom (distance)
 *   - 2 finger drag       → pan target (translate camera target)
 *   - Double tap          → reset camera to defaults
 */

import {
  PanResponder,
  GestureResponderEvent,
  PanResponderGestureState,
} from 'react-native';
import type { ICameraController } from './CameraController';

const TAG = '[GestureController]';

export interface IGestureController {
  getPanHandlers(): any;
  detach(): void;
  attach(camera: ICameraController): void;
}

export interface GestureControllerOptions {
  tapThreshold?: number;
  doubleTapWindowMs?: number;
  dragSensitivity?: number;
  pinchSensitivity?: number;
  panSensitivity?: number;
  debug?: boolean;
}

interface TouchPoint {
  x: number;
  y: number;
}

export class GestureController implements IGestureController {
  private camera: ICameraController | null = null;
  private opts: Required<GestureControllerOptions>;
  private panResponder: ReturnType<typeof PanResponder.create>;

  private pinchInitialDist = 0;
  private pinchInitialZoom = 0;
  private panInitialCenter: TouchPoint | null = null;
  private lastDragPos: TouchPoint | null = null;
  private lastDragTime = 0;
  private touchStartPos: TouchPoint | null = null;
  private touchStartTime = 0;
  private lastTapTime = 0;

  constructor(camera: ICameraController, opts: GestureControllerOptions = {}) {
    this.camera = camera;
    this.opts = {
      tapThreshold: opts.tapThreshold ?? 10,
      doubleTapWindowMs: opts.doubleTapWindowMs ?? 300,
      dragSensitivity: opts.dragSensitivity ?? 0.01,
      pinchSensitivity: opts.pinchSensitivity ?? 1.0,
      panSensitivity: opts.panSensitivity ?? 0.005,
      debug: opts.debug ?? false,
    };

    this.panResponder = PanResponder.create({
      onStartShouldSetPanResponder: () => true,
      onMoveShouldSetPanResponder: () => true,
      onPanResponderGrant: this.onGrant,
      onPanResponderMove: this.onMove,
      onPanResponderRelease: this.onRelease,
      onPanResponderTerminate: this.onRelease,
    });
  }

  private onGrant = (evt: GestureResponderEvent) => {
    const touches = evt.nativeEvent.touches;
    if (this.opts.debug) console.log(TAG, `grant: ${touches.length} touches`);

    if (touches.length >= 2) {
      const p1 = { x: touches[0].locationX, y: touches[0].locationY };
      const p2 = { x: touches[1].locationX, y: touches[1].locationY };
      this.pinchInitialDist = distance(p1, p2);
      this.pinchInitialZoom = this.camera?.getState().distance ?? 4;
      this.panInitialCenter = midpoint(p1, p2);
      this.lastDragPos = null;
    } else if (touches.length === 1) {
      this.lastDragPos = { x: touches[0].locationX, y: touches[0].locationY };
      this.lastDragTime = Date.now();
      this.touchStartPos = { x: touches[0].locationX, y: touches[0].locationY };
      this.touchStartTime = Date.now();
      this.pinchInitialDist = 0;
      this.panInitialCenter = null;
    }
    this.camera?.markInteracting();
  };

  private onMove = (evt: GestureResponderEvent, _gs: PanResponderGestureState) => {
    const touches = evt.nativeEvent.touches;
    if (!this.camera) return;

    if (touches.length >= 2) {
      if (this.pinchInitialDist > 0) {
        const p1 = { x: touches[0].locationX, y: touches[0].locationY };
        const p2 = { x: touches[1].locationX, y: touches[1].locationY };
        const currentDist = distance(p1, p2);
        if (currentDist > 0) {
          const ratio = (currentDist / this.pinchInitialDist) * this.opts.pinchSensitivity;
          const newDist = this.pinchInitialZoom * ratio;
          const currentCamDist = this.camera.getState().distance;
          if (currentCamDist > 0) {
            const factor = newDist / currentCamDist;
            this.camera.zoomBy(factor);
          }
        }
      }

      if (this.panInitialCenter) {
        const p1 = { x: touches[0].locationX, y: touches[0].locationY };
        const p2 = { x: touches[1].locationX, y: touches[1].locationY };
        const curCenter = midpoint(p1, p2);
        const dx = (curCenter.x - this.panInitialCenter.x) * this.opts.panSensitivity;
        const dy = (curCenter.y - this.panInitialCenter.y) * this.opts.panSensitivity;
        if (Math.abs(dx) > 0.001 || Math.abs(dy) > 0.001) {
          this.camera.panTargetBy(dx, -dy, 0);
          this.panInitialCenter = curCenter;
        }
      }
    } else if (touches.length === 1 && this.lastDragPos) {
      const x = touches[0].locationX;
      const y = touches[0].locationY;
      const dx = x - this.lastDragPos.x;
      const dy = y - this.lastDragPos.y;
      const now = Date.now();
      const dt = Math.max(now - this.lastDragTime, 1);

      const dYaw = dx * this.opts.dragSensitivity;
      const dPitch = -dy * this.opts.dragSensitivity;
      this.camera.orbitBy(dYaw, dPitch);

      this.lastDragPos = { x, y };
      this.lastDragTime = now;
    }
  };

  private onRelease = (evt: GestureResponderEvent) => {
    if (this.opts.debug) console.log(TAG, 'release');

    if (this.touchStartPos) {
      const releasePos = evt.nativeEvent.touches.length > 0
        ? { x: evt.nativeEvent.touches[0].locationX, y: evt.nativeEvent.touches[0].locationY }
        : null;
      const finalPos = releasePos ?? (
        evt.nativeEvent.changedTouches?.length > 0
          ? { x: evt.nativeEvent.changedTouches[0].locationX, y: evt.nativeEvent.changedTouches[0].locationY }
          : null
      );

      if (finalPos) {
        const moved = distance(this.touchStartPos, finalPos);
        const elapsed = Date.now() - this.touchStartTime;
        if (moved < this.opts.tapThreshold && elapsed < 300) {
          const now = Date.now();
          if (now - this.lastTapTime < this.opts.doubleTapWindowMs) {
            if (this.opts.debug) console.log(TAG, 'double tap → reset camera');
            this.camera?.reset();
            this.lastTapTime = 0;
          } else {
            this.lastTapTime = now;
          }
        }
      }
    }

    this.pinchInitialDist = 0;
    this.panInitialCenter = null;
    this.lastDragPos = null;
    this.touchStartPos = null;
  };

  getPanHandlers(): any {
    return this.panResponder.panHandlers;
  }

  detach(): void {
    this.camera = null;
  }

  attach(camera: ICameraController): void {
    this.camera = camera;
  }
}

function distance(a: TouchPoint, b: TouchPoint): number {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  return Math.sqrt(dx * dx + dy * dy);
}

function midpoint(a: TouchPoint, b: TouchPoint): TouchPoint {
  return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
}
