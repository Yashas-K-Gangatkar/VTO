import * as FileSystem from 'expo-file-system/legacy';
import type { TestCase } from './framework/types';
import { CacheManager } from '../assets/CacheManager';

const TEST_CACHE_DIR = `${FileSystem.cacheDirectory}test_cache_${Date.now()}/`;

async function ensureDir(dirPath: string): Promise<void> {
  const info = await FileSystem.getInfoAsync(dirPath);
  if (info.exists && (info as any).isDirectory !== false) return;
  try { await FileSystem.makeDirectoryAsync(dirPath, { intermediates: true }); }
  catch (e: any) { if (!String(e?.message||'').includes('already exists')) throw e; }
}

async function makeTestFile(path: string, content: string): Promise<void> {
  const parentDir = path.substring(0, path.lastIndexOf('/'));
  if (parentDir) await ensureDir(parentDir);
  await FileSystem.writeAsStringAsync(path, content);
}

async function fileExists(path: string): Promise<boolean> {
  const info = await FileSystem.getInfoAsync(path);
  return info.exists;
}

export const CacheManagerTests: TestCase[] = [
  {
    id: 'cache.put_get', name: 'CacheManager - put + get roundtrip', subsystem: 'CacheManager',
    async run(ctx) {
      const cache = new CacheManager({ cacheDirectory: TEST_CACHE_DIR + 'test1/', manifestPath: TEST_CACHE_DIR + 'test1/manifest.json' });
      const sourcePath = `${TEST_CACHE_DIR}test1_source.txt`;
      await makeTestFile(sourcePath, 'hello world');
      const descriptor = { id: 'test_asset_1', version: 1, url: 'http://example.com/test.glb', kind: 'garment' as const };
      const entry = await cache.put(descriptor, sourcePath);
      ctx.expect('entry returned', entry !== null);
      ctx.expect('file exists at localPath', await fileExists(entry.localPath));
      ctx.expect('entry size > 0', entry.sizeBytes > 0);
      const got = await cache.get(descriptor);
      ctx.expect('cache hit', got !== null);
      ctx.expect('accessCount incremented', got?.accessCount === 2, '2', `${got?.accessCount}`);
    },
  },
  {
    id: 'cache.version_invalidation', name: 'CacheManager - version bump invalidates', subsystem: 'CacheManager',
    async run(ctx) {
      const cache = new CacheManager({ cacheDirectory: TEST_CACHE_DIR + 'test2/', manifestPath: TEST_CACHE_DIR + 'test2/manifest.json' });
      const sourcePath = `${TEST_CACHE_DIR}test2_source.txt`;
      await makeTestFile(sourcePath, 'version 1 content');
      const descV1 = { id: 'versioned_asset', version: 1, url: 'http://example.com/test.glb', kind: 'garment' as const };
      const entryV1 = await cache.put(descV1, sourcePath);
      ctx.expect('v1 file exists', await fileExists(entryV1.localPath));
      const gotV1 = await cache.get(descV1);
      ctx.expect('v1 cache hit', gotV1 !== null);
      const descV2 = { ...descV1, version: 2 };
      const gotV2 = await cache.get(descV2);
      ctx.expect('v2 cache miss', gotV2 === null);
      const v1StillExists = await fileExists(entryV1.localPath);
      ctx.expect('v1 file deleted', v1StillExists === false);
    },
  },
  {
    id: 'cache.checksum_invalidation', name: 'CacheManager - checksum mismatch', subsystem: 'CacheManager',
    async run(ctx) {
      const cache = new CacheManager({ cacheDirectory: TEST_CACHE_DIR + 'test3/', manifestPath: TEST_CACHE_DIR + 'test3/manifest.json' });
      const sourcePath = `${TEST_CACHE_DIR}test3_source.txt`;
      await makeTestFile(sourcePath, 'checksum test');
      const descA = { id: 'checksummed_asset', version: 1, url: 'http://example.com/test.glb', kind: 'garment' as const, checksum: 'aaa' };
      await cache.put(descA, sourcePath);
      ctx.expect('cache hit with matching checksum', await cache.get(descA) !== null);
      const descB = { ...descA, checksum: 'bbb' };
      ctx.expect('cache miss with different checksum', await cache.get(descB) === null);
    },
  },
  {
    id: 'cache.lru_eviction', name: 'CacheManager - LRU evicts oldest', subsystem: 'CacheManager',
    async run(ctx) {
      const cache = new CacheManager({ cacheDirectory: TEST_CACHE_DIR + 'test4/', manifestPath: TEST_CACHE_DIR + 'test4/manifest.json', kindBudgets: { garment: 100, body: Number.MAX_SAFE_INTEGER, accessory: 50, environment: 100, animation: 20 } });
      const s1 = `${TEST_CACHE_DIR}test4_src1.txt`; const s2 = `${TEST_CACHE_DIR}test4_src2.txt`; const s3 = `${TEST_CACHE_DIR}test4_src3.txt`;
      await makeTestFile(s1, 'a'.repeat(50)); await makeTestFile(s2, 'b'.repeat(50)); await makeTestFile(s3, 'c'.repeat(50));
      await cache.put({ id: 'g1', version: 1, url: 'http://e/1.glb', kind: 'garment' }, s1);
      await cache.put({ id: 'g2', version: 1, url: 'http://e/2.glb', kind: 'garment' }, s2);
      await cache.put({ id: 'g3', version: 1, url: 'http://e/3.glb', kind: 'garment' }, s3);
      const pruneResult = await cache.prune();
      ctx.expect('at least 1 entry evicted', pruneResult.evictedIds.length >= 1);
      ctx.expect('g1 evicted (oldest)', pruneResult.evictedIds.includes('g1'));
      ctx.expect('g3 still in cache', await cache.get({ id: 'g3', version: 1, url: 'http://e/3.glb', kind: 'garment' }) !== null);
    },
  },
  {
    id: 'cache.body_never_evicted', name: 'CacheManager - body never evicted', subsystem: 'CacheManager',
    async run(ctx) {
      const cache = new CacheManager({ cacheDirectory: TEST_CACHE_DIR + 'test5/', manifestPath: TEST_CACHE_DIR + 'test5/manifest.json', kindBudgets: { body: 50, garment: 50, accessory: 50, environment: 50, animation: 20 } });
      const sourcePath = `${TEST_CACHE_DIR}test5_body.txt`;
      await makeTestFile(sourcePath, 'x'.repeat(200));
      const entry = await cache.put({ id: 'body_main', version: 1, url: 'http://e/body.glb', kind: 'body' }, sourcePath);
      const pruneResult = await cache.prune();
      ctx.expect('body NOT evicted', pruneResult.evictedIds.length === 0);
      ctx.expect('body file still on disk', await fileExists(entry.localPath));
    },
  },
  {
    id: 'cache.manifest_persists', name: 'CacheManager - manifest persists', subsystem: 'CacheManager',
    async run(ctx) {
      const dir = TEST_CACHE_DIR + 'test6/'; const manifestPath = `${dir}manifest.json`;
      const cache1 = new CacheManager({ cacheDirectory: dir, manifestPath });
      const sourcePath = `${TEST_CACHE_DIR}test6_source.txt`;
      await makeTestFile(sourcePath, 'persist test');
      await cache1.put({ id: 'persistent_asset', version: 1, url: 'http://e/p.glb', kind: 'garment' }, sourcePath);
      ctx.expect('manifest.json exists', await fileExists(manifestPath));
      const cache2 = new CacheManager({ cacheDirectory: dir, manifestPath });
      const manifest = await cache2.getManifest();
      ctx.expect('manifest loaded by cache2', manifest.entries['persistent_asset'] !== undefined);
    },
  },
  {
    id: 'cache.orphan_gc', name: 'CacheManager - orphan GC', subsystem: 'CacheManager',
    async run(ctx) {
      const dir = TEST_CACHE_DIR + 'test7/';
      const cache = new CacheManager({ cacheDirectory: dir, manifestPath: `${dir}manifest.json` });
      const sourcePath = `${TEST_CACHE_DIR}test7_source.txt`;
      await makeTestFile(sourcePath, 'gc test');
      await cache.put({ id: 'tracked', version: 1, url: 'http://e/t.glb', kind: 'garment' }, sourcePath);
      const orphanPath = `${dir}orphan.glb`;
      await makeTestFile(orphanPath, 'i am an orphan');
      ctx.expect('orphan exists before GC', await fileExists(orphanPath));
      const cache2 = new CacheManager({ cacheDirectory: dir, manifestPath: `${dir}manifest.json` });
      await cache2.getManifest();
      ctx.expect('orphan removed after GC', !(await fileExists(orphanPath)));
    },
  },
];
