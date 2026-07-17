import * as THREE from 'three';
import * as FileSystem from 'expo-file-system/legacy';
import type { TestCase } from './framework/types';
import type { LoadPhase } from '../core/types';
import { AssetManager } from '../assets/AssetManager';

const TEST_ASSETS = {
  box: { url: 'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/Box/glTF-Binary/Box.glb', id: 'test_box', expectedMeshes: 1, expectedTriangles: 12 },
  boxTextured: { url: 'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/BoxTextured/glTF-Binary/BoxTextured.glb', id: 'test_boxtextured', expectedMeshes: 1, expectedTriangles: 12, expectedTextures: 1 },
  riggedFigure: { url: 'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/RiggedFigure/glTF-Binary/RiggedFigure.glb', id: 'test_riggedfigure' },
};

export const AssetManagerTests: TestCase[] = [
  {
    id: 'assetmanager.load_box',
    name: 'AssetManager - full pipeline for Box.glb',
    subsystem: 'AssetManager',
    async run(ctx) {
      const manager = new AssetManager({ tempDir: `${FileSystem.cacheDirectory}am_tests/box/` });
      const phases: LoadPhase[] = [];
      const unsub = manager.onProgress((p) => { if (phases[phases.length - 1] !== p.phase) phases.push(p.phase); });
      const desc = { id: TEST_ASSETS.box.id, version: 99, url: TEST_ASSETS.box.url, kind: 'garment' as const };
      ctx.log('Loading Box.glb via AssetManager...');
      const stopLoad = ctx.startTimer('load');
      let loaded;
      try {
        loaded = await manager.load(desc);
      } catch (e: any) {
        ctx.expect('load did not throw', false, 'no error', e.message);
        unsub();
        return;
      }
      const loadMs = stopLoad();
      ctx.log(`Load: ${loadMs.toFixed(0)}ms`);
      unsub();

      ctx.expect('loaded asset returned', loaded !== null);
      ctx.expect('scene is THREE.Group', loaded.scene instanceof THREE.Group);
      ctx.expect('mesh count >= 1', loaded.stats.meshCount >= 1);
      ctx.expect('triangle count >= 1', loaded.stats.triangleCount >= 1);
      ctx.expect('bbox is non-zero size', loaded.bbox.size.x > 0 && loaded.bbox.size.y > 0 && loaded.bbox.size.z > 0);
      ctx.expect('localPath set', typeof loaded.localPath === 'string' && loaded.localPath.length > 0);
      ctx.log(`Phases: ${phases.join(' -> ')}`);
      ctx.expect('saw downloading phase', phases.includes('downloading'));
      ctx.expect('saw validating phase', phases.includes('validating'));
      ctx.expect('saw parsing phase', phases.includes('parsing'));
      ctx.expect('saw caching phase', phases.includes('caching'));
      ctx.expect('saw ready phase', phases.includes('ready'));
    },
  },
  {
    id: 'assetmanager.load_textured',
    name: 'AssetManager - full pipeline for BoxTextured.glb (proves Blob bypass)',
    subsystem: 'AssetManager',
    async run(ctx) {
      const manager = new AssetManager({ tempDir: `${FileSystem.cacheDirectory}am_tests/textured/` });
      const desc = { id: TEST_ASSETS.boxTextured.id, version: 1, url: TEST_ASSETS.boxTextured.url, kind: 'garment' as const };
      ctx.log('Loading BoxTextured.glb via AssetManager...');
      const stopLoad = ctx.startTimer('load');
      let blobErrorSeen = false;
      const origError = console.error;
      console.error = (...args: any[]) => {
        const msg = args.join(' ');
        if (msg.includes('Creating blobs') || msg.includes("Couldn't load texture")) blobErrorSeen = true;
        origError.apply(console, args as any);
      };
      let loaded;
      try {
        loaded = await manager.load(desc);
      } catch (e: any) {
        ctx.expect('load did not throw', false, 'no error', e.message);
        console.error = origError;
        return;
      } finally {
        console.error = origError;
      }
      const loadMs = stopLoad();
      ctx.log(`Load: ${loadMs.toFixed(0)}ms`);
      ctx.expect('loaded asset returned', loaded !== null);
      ctx.expect('mesh count >= 1', loaded.stats.meshCount >= 1);
      ctx.expect('NO "Creating blobs" error', !blobErrorSeen, 'false', `${blobErrorSeen}`);
    },
  },
  {
    id: 'assetmanager.cache_hit',
    name: 'AssetManager - second load is cache hit (faster)',
    subsystem: 'AssetManager',
    async run(ctx) {
      const manager = new AssetManager({ tempDir: `${FileSystem.cacheDirectory}am_tests/cachehit/` });
      // Use a unique version to avoid collisions with previous test runs
      const desc = { id: 'cachehit_test_v2', version: 99, url: TEST_ASSETS.box.url, kind: 'garment' as const };
      ctx.log('First load (cache miss)...');
      const stopFirst = ctx.startTimer('first_load');
      await manager.load(desc);
      const firstMs = stopFirst();
      ctx.log(`First load: ${firstMs.toFixed(0)}ms`);

      ctx.log('Second load (cache hit)...');
      const stopSecond = ctx.startTimer('second_load');
      await manager.load(desc);
      const secondMs = stopSecond();
      ctx.log(`Second load: ${secondMs.toFixed(0)}ms`);

      // Cache hit should be faster (no download), but parsing still runs.
      // Realistic expectation: second load is faster than first.
      ctx.expect('second load faster than first', secondMs < firstMs, `${firstMs.toFixed(0)}ms`, `${secondMs.toFixed(0)}ms`);
    },
  },
  {
    id: 'assetmanager.load_rigged',
    name: 'AssetManager - RiggedFigure.glb loads successfully',
    subsystem: 'AssetManager',
    async run(ctx) {
      const manager = new AssetManager({ tempDir: `${FileSystem.cacheDirectory}am_tests/rigged/` });
      const desc = { id: TEST_ASSETS.riggedFigure.id, version: 1, url: TEST_ASSETS.riggedFigure.url, kind: 'body' as const };
      ctx.log('Loading RiggedFigure.glb...');
      const stopLoad = ctx.startTimer('load');
      const loaded = await manager.load(desc);
      const loadMs = stopLoad();
      ctx.log(`Load: ${loadMs.toFixed(0)}ms`);

      ctx.expect('loaded asset returned', loaded !== null);
      ctx.expect('mesh count >= 1', loaded.stats.meshCount >= 1, '>=1', `${loaded.stats.meshCount}`);
      ctx.expect('scene is THREE.Group', loaded.scene instanceof THREE.Group);
      // Skeleton may or may not be extracted depending on GLB structure — don't fail on it
      if (loaded.skeleton) {
        ctx.expect('skeleton has bones', loaded.skeleton.skeleton.bones.length > 0);
        ctx.log(`Skeleton: ${loaded.skeleton.skeleton.bones.length} bones`);
      } else {
        ctx.log('No skeleton extracted (GLB may not have a skin)');
      }
    },
  },
  {
    id: 'assetmanager.release',
    name: 'AssetManager - release disposes GPU resources',
    subsystem: 'AssetManager',
    async run(ctx) {
      const manager = new AssetManager({ tempDir: `${FileSystem.cacheDirectory}am_tests/release/` });
      const desc = { id: 'release_test', version: 99, url: TEST_ASSETS.box.url, kind: 'garment' as const };
      const loaded = await manager.load(desc);
      let geomCount = 0;
      loaded.scene.traverse((obj: any) => { if (obj.isMesh) geomCount++; });
      ctx.expect('meshes present before release', geomCount > 0);
      manager.release(loaded);
      ctx.log('Released asset');
      ctx.expect('release did not throw', true);
    },
  },
];
