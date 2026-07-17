/**
 * engine/index.ts
 *
 * Public API of the rendering engine.
 */

export * from './core/types';
export { AssetManager, type IAssetManager, type LoadOptions } from './assets/AssetManager';
export { CacheManager, type ICacheManager, type CacheManagerOptions } from './assets/CacheManager';
export { AssetValidator, type IAssetValidator, type ValidationResult } from './assets/AssetValidator';
export { TextureLoader, type ITextureLoader, type ExtractedTextures } from './textures/TextureLoader';
export { TextureManager, type ITextureManager, type TextureManagerOptions } from './textures/TextureManager';
export {
  CameraController, type ICameraController, type CameraState, type CameraControllerOptions,
} from './camera/CameraController';
export { GestureController, type IGestureController, type GestureControllerOptions } from './camera/GestureController';
export {
  CameraConstraints, DEFAULT_VTO_CONSTRAINTS, AVATAR_CUSTOMIZER_CONSTRAINTS,
  WALKTHROUGH_CONSTRAINTS, clamp, lerp, damp,
} from './camera/CameraConstraints';
export {
  LODSystem, type ILODSystem, type LODGroup, type LODVariant, type LODStats,
} from './geometry/LODSystem';
export {
  MeshOptimizer, type OptimizationOptions, type OptimizationResult, DEFAULT_OPTS as DEFAULT_MESH_OPTS,
} from './geometry/MeshOptimizer';
export { BoundingBoxUtils } from './geometry/BoundingBox';
export {
  MaterialSystem, type IMaterialSystem, type MaterialSystemOptions, type TextureSlot as MaterialTextureSlot,
} from './materials/MaterialSystem';
export { MaterialCache, type IMaterialCache, type MaterialCacheStats } from './materials/MaterialCache';
export { MaterialFactory, FABRIC_PRESETS, type MaterialPreset, type TextureSlot } from './materials/MaterialFactory';
export {
  AnimationController, type IAnimationController, type ActiveClip, type PlayOptions, type PlayMode, type AnimationControllerOptions,
} from './animation/AnimationController';
export {
  SkeletonRetargeter, type ISkeletonRetargeter, type BoneMapping, type RetargetOptions, DEFAULT_RETARGET_OPTS,
} from './animation/SkeletonRetargeter';
export { SkeletonDetector, type ISkeletonDetector } from './skeleton/SkeletonDetector';
export { BodyProportions, type IBodyProportions, type BodyMeasurements } from './skeleton/BodyProportions';
export {
  GarmentFitter, type IGarmentFitter, type FitOptions, type FitResult, type FitLevel, DEFAULT_FIT_OPTS,
} from './skeleton/GarmentFitter';
export {
  PerformanceProfiler, type IPerformanceProfiler, type RollingStats,
} from './debug/PerformanceProfiler';
export { DebugOverlay, type DebugOverlayProps } from './debug/DebugOverlay';
export {
  AssetStreamer, type IAssetStreamer, type StreamResult, type StreamOptions, type StreamStatus,
} from './streaming/AssetStreamer';
export { Engine, type EngineOptions, type LoadBodyResult } from './core/Engine';
export { EngineViewer, type EngineViewerProps } from './viewer/EngineViewer';
