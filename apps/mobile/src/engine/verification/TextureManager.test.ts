import * as THREE from 'three';
import * as FileSystem from 'expo-file-system/legacy';
import type { TestCase } from './framework/types';
import { TextureManager } from '../textures/TextureManager';
import type { TextureRef } from '../core/types';

const TINY_PNG_BASE64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';
const TEST_FILE_PATH = `${FileSystem.cacheDirectory}test_texture.png`;

async function ensureTestFile(): Promise<string> {
  const info = await FileSystem.getInfoAsync(TEST_FILE_PATH);
  if (!info.exists) await FileSystem.writeAsStringAsync(TEST_FILE_PATH, TINY_PNG_BASE64, { encoding: 'base64' });
  return `file://${TEST_FILE_PATH}`;
}

function makeTextureRef(cacheKey: string, uri: string): TextureRef {
  return { cacheKey, uri, maxResolution: 64, colorSpace: 'srgb', wrapS: 'clamp', wrapT: 'clamp' };
}

export const TextureManagerTests: TestCase[] = [
  {
    id: 'texturemgr.acquire_release', name: 'TextureManager - acquire + release', subsystem: 'TextureManager',
    async run(ctx) {
      const uri = await ensureTestFile();
      const mgr = new TextureManager({ maxTotalBytes: 100 * 1024 * 1024 });
      const ref = makeTextureRef('test1', uri);
      let tex1: THREE.Texture;
      try { tex1 = await mgr.acquire(ref); }
      catch (e: any) { ctx.expect('acquire did not throw', false, 'texture', e?.message); return; }
      ctx.expect('texture returned', tex1 instanceof THREE.Texture);
      ctx.expect('count = 1', mgr.getMemoryUsage().count === 1);
      mgr.release(ref);
      ctx.expect('count = 0 after release', mgr.getMemoryUsage().count === 0);
    },
  },
  {
    id: 'texturemgr.refcount_shared', name: 'TextureManager - refcount shared', subsystem: 'TextureManager',
    async run(ctx) {
      const uri = await ensureTestFile();
      const mgr = new TextureManager();
      const ref = makeTextureRef('shared_test', uri);
      const tex1 = await mgr.acquire(ref);
      const tex2 = await mgr.acquire(ref);
      const tex3 = await mgr.acquire(ref);
      ctx.expect('same instance', tex1 === tex2 && tex2 === tex3);
      mgr.release(ref); mgr.release(ref);
      ctx.expect('count = 1 after 2 releases', mgr.getMemoryUsage().count === 1);
      mgr.release(ref);
      ctx.expect('count = 0 after 3rd release', mgr.getMemoryUsage().count === 0);
    },
  },
  {
    id: 'texturemgr.dedupe_concurrent', name: 'TextureManager - dedupe concurrent', subsystem: 'TextureManager',
    async run(ctx) {
      const uri = await ensureTestFile();
      const mgr = new TextureManager();
      const ref = makeTextureRef('concurrent_test', uri);
      const textures = await Promise.all([mgr.acquire(ref), mgr.acquire(ref), mgr.acquire(ref), mgr.acquire(ref), mgr.acquire(ref)]);
      ctx.expect('all 5 resolved', textures.length === 5);
      ctx.expect('all same instance', textures.every((t) => t === textures[0]));
      ctx.expect('count = 1', mgr.getMemoryUsage().count === 1);
      for (let i = 0; i < 5; i++) mgr.release(ref);
    },
  },
  {
    id: 'texturemgr.dispose_all', name: 'TextureManager - disposeAll', subsystem: 'TextureManager',
    async run(ctx) {
      const uri = await ensureTestFile();
      const mgr = new TextureManager();
      await mgr.acquire(makeTextureRef('a', uri));
      await mgr.acquire(makeTextureRef('b', uri));
      await mgr.acquire(makeTextureRef('c', uri));
      ctx.expect('count = 3', mgr.getMemoryUsage().count === 3);
      mgr.disposeAll();
      ctx.expect('count = 0 after disposeAll', mgr.getMemoryUsage().count === 0);
    },
  },
];
