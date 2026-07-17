/**
 * engine/__tests__/LODSystem.test.ts
 */

import * as THREE from 'three';
import type { TestCase } from './framework/types';
import { LODSystem } from '../geometry/LODSystem';
import type { LoadedAsset, AssetDescriptor, BBox } from '../core/types';

function makeFakeAsset(id: string): LoadedAsset {
  const group = new THREE.Group();
  const geom = new THREE.BoxGeometry(0.1, 0.1, 0.1);
  const mat = new THREE.MeshBasicMaterial();
  group.add(new THREE.Mesh(geom, mat));
  const bbox: BBox = {
    min: { x: -0.05, y: -0.05, z: -0.05 },
    max: { x: 0.05, y: 0.05, z: 0.05 },
    center: { x: 0, y: 0, z: 0 },
    size: { x: 0.1, y: 0.1, z: 0.1 },
  };
  const descriptor: AssetDescriptor = { id, version: 1, url: `http://test/${id}.glb`, kind: 'garment' };
  return {
    descriptor, scene: group, bbox,
    stats: { meshCount: 1, triangleCount: 12, vertexCount: 8, materialCount: 1, textureCount: 0, estimatedMemoryBytes: 384 },
    skeleton: null, activeLOD: 'high', localPath: '', loadTimeMs: 0,
  };
}

export const LODSystemTests: TestCase[] = [
  {
    id: 'lod.register_and_activate',
    name: 'LODSystem - register() activates the first variant',
    subsystem: 'LODSystem',
    async run(ctx) {
      const lod = new LODSystem();
      const asset = makeFakeAsset('test1');
      const group = lod.register('test1', 'high', asset);
      ctx.expect('LODGroup created', group !== null);
      ctx.expect('container is a THREE.Group', group.container instanceof THREE.Group);
      ctx.expect('currentLevel is "high"', group.currentLevel === 'high');
      ctx.expect('variant is active', group.variants.get('high')?.isActive === true);
      ctx.expect('variant scene added to container', group.container.children.includes(asset.scene));
    },
  },
  {
    id: 'lod.distance_switch_high_to_medium',
    name: 'LODSystem - at distance 6 -> switches to medium',
    subsystem: 'LODSystem',
    async run(ctx) {
      const lod = new LODSystem();
      lod.register('test2', 'high', makeFakeAsset('test2_high'));
      lod.register('test2', 'medium', makeFakeAsset('test2_med'));
      lod.update(new THREE.Vector3(0, 0, 0), 1 / 60);
      let group = lod.getGroups()[0];
      ctx.expect('at distance 0: high LOD', group.currentLevel === 'high', 'high', group.currentLevel);
      lod.update(new THREE.Vector3(0, 0, 6), 1 / 60);
      group = lod.getGroups()[0];
      ctx.expect('at distance 6: medium LOD', group.currentLevel === 'medium', 'medium', group.currentLevel);
    },
  },
  {
    id: 'lod.distance_switch_medium_to_low',
    name: 'LODSystem - at distance 12 -> switches to low',
    subsystem: 'LODSystem',
    async run(ctx) {
      const lod = new LODSystem();
      lod.register('test3', 'high', makeFakeAsset('test3_high'));
      lod.register('test3', 'medium', makeFakeAsset('test3_med'));
      lod.register('test3', 'low', makeFakeAsset('test3_low'));
      lod.update(new THREE.Vector3(0, 0, 12), 1 / 60);
      const group = lod.getGroups()[0];
      ctx.expect('at distance 12: low LOD', group.currentLevel === 'low', 'low', group.currentLevel);
    },
  },
  {
    id: 'lod.hysteresis',
    name: 'LODSystem - hysteresis prevents rapid flipping at boundary',
    subsystem: 'LODSystem',
    async run(ctx) {
      const lod = new LODSystem();
      lod.register('test4', 'high', makeFakeAsset('test4_high'));
      lod.register('test4', 'medium', makeFakeAsset('test4_med'));
      lod.update(new THREE.Vector3(0, 0, 3), 1 / 60);
      let group = lod.getGroups()[0];
      ctx.expect('at distance 3: high LOD', group.currentLevel === 'high');
      lod.update(new THREE.Vector3(0, 0, 4.05), 1 / 60);
      group = lod.getGroups()[0];
      ctx.expect('at distance 4.05 (hysteresis zone): still high', group.currentLevel === 'high', 'high', group.currentLevel);
      lod.update(new THREE.Vector3(0, 0, 4.7), 1 / 60);
      group = lod.getGroups()[0];
      ctx.expect('at distance 4.7 (past hysteresis): medium', group.currentLevel === 'medium', 'medium', group.currentLevel);
    },
  },
  {
    id: 'lod.force_lod',
    name: 'LODSystem - forceLOD() overrides distance-based selection',
    subsystem: 'LODSystem',
    async run(ctx) {
      const lod = new LODSystem();
      lod.register('test5', 'high', makeFakeAsset('test5_high'));
      lod.register('test5', 'medium', makeFakeAsset('test5_med'));
      lod.update(new THREE.Vector3(0, 0, 1), 1 / 60);
      lod.forceLOD('test5', 'medium');
      const group = lod.getGroups()[0];
      ctx.expect('forceLOD medium at distance 1', group.currentLevel === 'medium');
    },
  },
  {
    id: 'lod.unregister',
    name: 'LODSystem - unregister() removes the group',
    subsystem: 'LODSystem',
    async run(ctx) {
      const lod = new LODSystem();
      lod.register('test6', 'high', makeFakeAsset('test6_high'));
      ctx.expect('group registered', lod.getGroups().length === 1);
      lod.unregister('test6');
      ctx.expect('group unregistered', lod.getGroups().length === 0);
    },
  },
  {
    id: 'lod.stats_histogram',
    name: 'LODSystem - getStats() returns correct histogram',
    subsystem: 'LODSystem',
    async run(ctx) {
      const lod = new LODSystem();
      lod.register('g1', 'high', makeFakeAsset('g1_high'));
      lod.register('g2', 'high', makeFakeAsset('g2_high'));
      lod.register('g3', 'high', makeFakeAsset('g3_high'));
      lod.register('g1', 'medium', makeFakeAsset('g1_med'));
      lod.register('g2', 'medium', makeFakeAsset('g2_med'));
      lod.register('g3', 'medium', makeFakeAsset('g3_med'));
      lod.register('g1', 'low', makeFakeAsset('g1_low'));
      lod.register('g2', 'low', makeFakeAsset('g2_low'));
      lod.register('g3', 'low', makeFakeAsset('g3_low'));
      lod.update(new THREE.Vector3(0, 0, 6), 1 / 60);
      const stats = lod.getStats();
      ctx.expect('groupCount = 3', stats.groupCount === 3);
      ctx.expect('all 3 at medium', stats.histogram.medium === 3, '3', `${stats.histogram.medium}`);
      ctx.expect('totalVariants = 9', stats.totalVariants === 9);
    },
  },
];
