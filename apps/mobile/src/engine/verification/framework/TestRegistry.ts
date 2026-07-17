/**
 * engine/__tests__/framework/TestRegistry.ts
 */

import type { TestCase, SubsystemName } from './types';
import { TextureLoaderTests } from '../TextureLoader.test';
import { AssetValidatorTests } from '../AssetValidator.test';
import { CacheManagerTests } from '../CacheManager.test';
import { AssetManagerTests } from '../AssetManager.test';
import { MeshOptimizerTests } from '../MeshOptimizer.test';
import { CameraControllerTests } from '../CameraController.test';
import { LODSystemTests } from '../LODSystem.test';
import { PerformanceProfilerTests } from '../PerformanceProfiler.test';
import { TextureManagerTests } from '../TextureManager.test';
import { SkeletonDetectorTests } from '../SkeletonDetector.test';

const ALL_TESTS: TestCase[] = [
  ...TextureLoaderTests,
  ...AssetValidatorTests,
  ...CacheManagerTests,
  ...AssetManagerTests,
  ...MeshOptimizerTests,
  ...CameraControllerTests,
  ...LODSystemTests,
  ...PerformanceProfilerTests,
  ...TextureManagerTests,
  ...SkeletonDetectorTests,
];

export function getAllTests(): TestCase[] { return ALL_TESTS; }
export function getTestsBySubsystem(subsystem: SubsystemName): TestCase[] {
  return ALL_TESTS.filter((t) => t.subsystem === subsystem);
}
export function getTestById(id: string): TestCase | undefined {
  return ALL_TESTS.find((t) => t.id === id);
}
export function listSubsystems(): SubsystemName[] {
  const set = new Set<SubsystemName>(ALL_TESTS.map((t) => t.subsystem));
  return Array.from(set).sort();
}
