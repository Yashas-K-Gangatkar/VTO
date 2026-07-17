/**
 * engine/__tests__/framework/types.ts
 */

export type TestStatus = 'pass' | 'fail' | 'skipped' | 'running' | 'pending';

export interface TestResult {
  id: string;
  name: string;
  subsystem: SubsystemName;
  status: TestStatus;
  durationMs: number;
  timestamp: number;
  assertions: AssertionResult[];
  metrics: BenchmarkMetrics;
  error?: string;
  deviceInfo: DeviceInfo;
  logs?: string[];
}

export interface AssertionResult {
  label: string;
  passed: boolean;
  expected?: string;
  actual?: string;
}

export type SubsystemName =
  | 'TextureLoader' | 'TextureManager' | 'AssetValidator' | 'CacheManager'
  | 'AssetManager' | 'CameraController' | 'GestureController' | 'LODSystem'
  | 'MeshOptimizer' | 'MaterialSystem' | 'AnimationController'
  | 'SkeletonRetargeter' | 'SkeletonDetector' | 'BodyProportions'
  | 'GarmentFitter' | 'AssetStreamer' | 'PerformanceProfiler' | 'Engine';

export interface BenchmarkMetrics {
  fpsAvg?: number; fpsMin?: number; fpsMax?: number;
  frameTimeAvgMs?: number; frameTimeMinMs?: number; frameTimeMaxMs?: number;
  renderTimeMs?: number; animationTimeMs?: number;
  jsHeapUsedMB?: number; jsHeapTotalMB?: number;
  estimatedGpuMemoryMB?: number; textureMemoryMB?: number; geometryMemoryMB?: number;
  drawCalls?: number; triangles?: number; vertices?: number;
  geometries?: number; textures?: number; programs?: number;
  loadTimeMs?: number; downloadTimeMs?: number; parseTimeMs?: number;
  validateTimeMs?: number; cacheHitTimeMs?: number; cacheMissTimeMs?: number;
  cacheHits?: number; cacheMisses?: number;
  cacheSizeBytes?: number; cacheEvictions?: number;
  gestureLatencyMs?: number; gestureDroppedFrames?: number;
  lodSwitches?: number; lodHysteresisCorrect?: boolean;
  streamPreviewReadyMs?: number; streamFullReadyMs?: number;
  animationClipsActive?: number; animationCrossFadeMs?: number;
  custom?: Record<string, number | string | boolean>;
}

export interface DeviceInfo {
  platform: 'android' | 'ios' | 'web';
  osVersion: string;
  manufacturer?: string;
  model?: string;
  expoSdkVersion: string;
  reactNativeVersion: string;
  totalMemoryMB?: number;
  devicePixelRatio?: number;
  screenDimensions?: { width: number; height: number };
}

export interface TestCase {
  id: string;
  name: string;
  subsystem: SubsystemName;
  skipReason?: string;
  run: (ctx: TestContext) => Promise<void>;
}

export interface TestContext {
  log: (msg: string) => void;
  expect: (label: string, condition: boolean, expected?: string, actual?: string) => void;
  startTimer: (name: string) => () => number;
  getDeviceInfo: () => Promise<DeviceInfo>;
  sampleMemory: () => MemorySample;
}

export interface MemorySample {
  jsHeapUsedMB: number;
  jsHeapTotalMB: number;
  timestamp: number;
}

export interface TestReport {
  generatedAt: number;
  deviceInfo: DeviceInfo;
  totalTests: number;
  passed: number;
  failed: number;
  skipped: number;
  totalDurationMs: number;
  results: TestResult[];
  bySubsystem: Record<string, { total: number; passed: number; failed: number; skipped: number }>;
  findings: string[];
  notes: string[];
}
