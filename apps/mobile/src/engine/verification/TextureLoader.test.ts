/**
 * engine/__tests__/TextureLoader.test.ts
 *
 * THE MOST CRITICAL TEST. Proves the Blob bypass works on Android.
 */

import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader';
import * as FileSystem from 'expo-file-system/legacy';

import type { TestCase } from './framework/types';
import { TextureLoader } from '../textures/TextureLoader';

const TEST_ASSET_URL = 'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/BoxTextured/glTF-Binary/BoxTextured.glb';
const TEST_ASSET_ID = 'boxtextured_test';
const TEST_TEMP_DIR = `${FileSystem.cacheDirectory}test_textures/`;

export const TextureLoaderTests: TestCase[] = [
  {
    id: 'textureloader.extract',
    name: 'TextureLoader.extractFromGLB - extracts textures to file:// URIs',
    subsystem: 'TextureLoader',
    async run(ctx) {
      ctx.log('Downloading test asset: BoxTextured.glb');
      const stopDownload = ctx.startTimer('download');
      const localPath = `${FileSystem.cacheDirectory}${TEST_ASSET_ID}.glb`;
      const info = await FileSystem.getInfoAsync(localPath);
      if (!info.exists) {
        const result = await FileSystem.downloadAsync(TEST_ASSET_URL, localPath);
        if (result.status !== 200) {
          ctx.expect('download succeeded', false, 'HTTP 200', `HTTP ${result.status}`);
          return;
        }
      }
      const downloadMs = stopDownload();
      ctx.log(`Download/cache: ${downloadMs.toFixed(0)}ms`);

      ctx.log('Reading GLB as base64 -> ArrayBuffer');
      const stopRead = ctx.startTimer('read');
      const b64 = await FileSystem.readAsStringAsync(localPath, { encoding: 'base64' });
      const buf = base64ToArrayBuffer(b64);
      const readMs = stopRead();
      ctx.log(`Read: ${readMs.toFixed(0)}ms, ${buf.byteLength} bytes`);

      ctx.expect('GLB is non-empty', buf.byteLength > 100, '>100 bytes', `${buf.byteLength} bytes`);

      ctx.log('Running TextureLoader.extractFromGLB()');
      const loader = new TextureLoader();
      const stopExtract = ctx.startTimer('extract');

      let extracted;
      try {
        extracted = await loader.extractFromGLB(buf, TEST_TEMP_DIR);
      } catch (e: any) {
        ctx.expect('extractFromGLB did not throw', false, 'no error', e.message);
        return;
      }
      const extractMs = stopExtract();
      ctx.log(`Extract: ${extractMs.toFixed(0)}ms`);

      ctx.expect('extraction returned a result', extracted !== null && extracted !== undefined);
      ctx.expect('patched JSON is non-null', extracted.patchedJson !== null);

      const imageCount = Object.keys(extracted.imageUris).length;
      ctx.log(`Extracted ${imageCount} texture(s), total ${extracted.totalBytes} bytes`);
      ctx.expect('at least 1 texture extracted', imageCount >= 1, '>=1', `${imageCount}`);

      let allFileUris = true;
      for (const [idx, uri] of Object.entries(extracted.imageUris)) {
        if (!uri.startsWith('file://')) {
          allFileUris = false;
          ctx.log(`image[${idx}] URI is not file://: ${uri}`);
        }
      }
      ctx.expect('all image URIs are file://', allFileUris);

      const patchedImages = extracted.patchedJson?.images ?? [];
      let allPatchedHaveUri = true;
      for (let i = 0; i < patchedImages.length; i++) {
        const img = patchedImages[i];
        if (!img.uri) { allPatchedHaveUri = false; ctx.log(`patched images[${i}] is missing uri`); }
        if (img.bufferView !== undefined) { allPatchedHaveUri = false; ctx.log(`patched images[${i}] still has bufferView`); }
      }
      ctx.expect('patched images[] all have uri, no bufferView', allPatchedHaveUri);

      let filesExist = true;
      for (const uri of Object.values(extracted.imageUris)) {
        const path = uri.replace('file://', '');
        const finfo = await FileSystem.getInfoAsync(path);
        if (!finfo.exists) { filesExist = false; ctx.log(`temp file does not exist: ${path}`); }
      }
      ctx.expect('all temp texture files exist on disk', filesExist);

      try {
        JSON.stringify(extracted.patchedJson);
        ctx.expect('patched JSON re-serializes', true);
      } catch (e: any) {
        ctx.expect('patched JSON re-serializes', false, 'no error', e.message);
      }

      ctx.expect('extraction time <5s', extractMs < 5000, '<5000ms', `${extractMs.toFixed(0)}ms`);
    },
  },

  {
    id: 'textureloader.parse_no_blob_error',
    name: 'GLTFLoader.parse - does NOT throw "Creating blobs" error',
    subsystem: 'TextureLoader',
    async run(ctx) {
      ctx.log('Downloading test asset: BoxTextured.glb');
      const localPath = `${FileSystem.cacheDirectory}${TEST_ASSET_ID}.glb`;
      const info = await FileSystem.getInfoAsync(localPath);
      if (!info.exists) await FileSystem.downloadAsync(TEST_ASSET_URL, localPath);

      const b64 = await FileSystem.readAsStringAsync(localPath, { encoding: 'base64' });
      const buf = base64ToArrayBuffer(b64);

      ctx.log('Extracting textures (to bypass Blob)');
      const loader = new TextureLoader();
      const extracted = await loader.extractFromGLB(buf, TEST_TEMP_DIR + 'parse_test/');

      ctx.log('Rebuilding GLB with patched JSON');
      const stopRebuild = ctx.startTimer('rebuild');
      const rebuilt = rebuildGlb(extracted.patchedJson, buf);
      const rebuildMs = stopRebuild();
      ctx.log(`Rebuild: ${rebuildMs.toFixed(0)}ms, ${rebuilt.byteLength} bytes`);

      ctx.log('Calling GLTFLoader.parse() - watching for Blob error');
      const gltfLoader = new GLTFLoader();
      const stopParse = ctx.startTimer('parse');

      let blobErrorSeen = false;
      let parseError: any = null;
      let gltf: any = null;

      const originalConsoleError = console.error;
      console.error = (...args: any[]) => {
        const msg = args.join(' ');
        if (msg.includes('Creating blobs') || msg.includes("Couldn't load texture")) blobErrorSeen = true;
        originalConsoleError.apply(console, args as any);
      };

      try {
        gltf = await new Promise<any>((resolve, reject) => {
          gltfLoader.parse(rebuilt, '', resolve, reject);
        });
      } catch (e: any) {
        parseError = e;
      } finally {
        console.error = originalConsoleError;
      }

      const parseMs = stopParse();
      ctx.log(`Parse: ${parseMs.toFixed(0)}ms`);

      ctx.expect('parse did not throw', parseError === null, 'no error', parseError?.message ?? 'none');
      ctx.expect('no "Creating blobs" error in logs', !blobErrorSeen, 'false', `${blobErrorSeen}`);
      ctx.expect('gltf object was returned', gltf !== null && gltf !== undefined);
      ctx.expect('gltf.scene is a THREE.Group', gltf?.scene instanceof THREE.Group);

      if (gltf?.scene) {
        let meshCount = 0;
        gltf.scene.traverse((obj: any) => { if (obj.isMesh) meshCount++; });
        ctx.log(`Parsed scene has ${meshCount} mesh(es)`);
        ctx.expect('parsed scene has >=1 mesh', meshCount >= 1, '>=1', `${meshCount}`);
      }
    },
  },
];

function base64ToArrayBuffer(base64: string): ArrayBuffer {
  try {
    // @ts-ignore
    if (typeof Buffer !== 'undefined') {
      // @ts-ignore
      const buf = Buffer.from(base64, 'base64');
      return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
    }
  } catch { /* fall through */ }
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function rebuildGlb(patchedJson: any, originalBuffer: ArrayBuffer): ArrayBuffer {
  if (!patchedJson) return originalBuffer;
  const jsonBytes = new TextEncoder().encode(JSON.stringify(patchedJson));
  const jsonPaddedLen = Math.ceil(jsonBytes.length / 4) * 4;
  const jsonPadded = new Uint8Array(jsonPaddedLen).fill(0x20);
  jsonPadded.set(jsonBytes);

  const origBytes = new Uint8Array(originalBuffer);
  const dv = new DataView(originalBuffer);
  let offset = 12;
  let binOffset = 0;
  let binLength = 0;
  while (offset + 8 <= origBytes.length) {
    const chunkLength = dv.getUint32(offset, true);
    const chunkType = dv.getUint32(offset + 4, true);
    if (chunkType === 0x004e4942) { binOffset = offset + 8; binLength = chunkLength; }
    offset = offset + 8 + chunkLength;
  }
  const binPaddedLen = Math.ceil(binLength / 4) * 4;
  const totalLength = 12 + 8 + jsonPaddedLen + (binLength > 0 ? 8 + binPaddedLen : 0);
  const out = new ArrayBuffer(totalLength);
  const outBytes = new Uint8Array(out);
  const outDv = new DataView(out);
  outDv.setUint32(0, 0x46546c67, true);
  outDv.setUint32(4, 2, true);
  outDv.setUint32(8, totalLength, true);
  let w = 12;
  outDv.setUint32(w, jsonPaddedLen, true);
  outDv.setUint32(w + 4, 0x4e4f534a, true);
  outBytes.set(jsonPadded, w + 8);
  w += 8 + jsonPaddedLen;
  if (binLength > 0) {
    outDv.setUint32(w, binPaddedLen, true);
    outDv.setUint32(w + 4, 0x004e4942, true);
    outBytes.set(origBytes.subarray(binOffset, binOffset + binLength), w + 8);
  }
  return out;
}
