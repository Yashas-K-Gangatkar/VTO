/**
 * engine/__tests__/AssetValidator.test.ts
 */

import * as FileSystem from 'expo-file-system/legacy';
import type { TestCase } from './framework/types';
import { AssetValidator } from '../assets/AssetValidator';

const TEST_DIR = `${FileSystem.cacheDirectory}validator_tests/`;
const VALID_GLB_URL = 'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/Box/glTF-Binary/Box.glb';
const TEXTURED_GLB_URL = 'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/BoxTextured/glTF-Binary/BoxTextured.glb';

export const AssetValidatorTests: TestCase[] = [
  {
    id: 'validator.valid_box',
    name: 'AssetValidator - accepts valid Box.glb',
    subsystem: 'AssetValidator',
    async run(ctx) {
      const buf = await fetchTestAsset(ctx, VALID_GLB_URL, 'Box.glb');
      if (!buf) return;
      const validator = new AssetValidator();
      const stopValidate = ctx.startTimer('validate');
      const result = validator.validate(buf);
      const validateMs = stopValidate();
      ctx.log(`Validate: ${validateMs.toFixed(2)}ms`);
      ctx.expect('valid=true', result.valid === true, 'true', `${result.valid}`);
      ctx.expect('no errors', result.errors.length === 0, '0 errors', `${result.errors.length} errors`);
      ctx.expect('1 mesh detected', result.stats.meshCount === 1, '1', `${result.stats.meshCount}`);
      ctx.expect('JSON chunk non-zero', result.stats.jsonChunkBytes > 0);
      ctx.expect('validation time <50ms', validateMs < 50, '<50ms', `${validateMs.toFixed(2)}ms`);
    },
  },
  {
    id: 'validator.valid_textured',
    name: 'AssetValidator - accepts valid BoxTextured.glb',
    subsystem: 'AssetValidator',
    async run(ctx) {
      const buf = await fetchTestAsset(ctx, TEXTURED_GLB_URL, 'BoxTextured.glb');
      if (!buf) return;
      const validator = new AssetValidator();
      const result = validator.validate(buf);
      ctx.expect('valid=true', result.valid === true);
      ctx.expect('no errors', result.errors.length === 0);
      ctx.expect('1 mesh detected', result.stats.meshCount === 1);
      ctx.expect('>=1 texture detected', result.stats.textureCount >= 1, '>=1', `${result.stats.textureCount}`);
      ctx.expect('BIN chunk non-zero', result.stats.binChunkBytes > 0);
    },
  },
  {
    id: 'validator.bad_magic',
    name: 'AssetValidator - rejects file with wrong magic bytes',
    subsystem: 'AssetValidator',
    async run(ctx) {
      const fake = new ArrayBuffer(20);
      const dv = new DataView(fake);
      dv.setUint32(0, 0xDEADBEEF, true);
      dv.setUint32(4, 2, true);
      dv.setUint32(8, 20, true);
      const validator = new AssetValidator();
      const result = validator.validate(fake);
      ctx.expect('valid=false', result.valid === false);
      ctx.expect('at least 1 error', result.errors.length >= 1);
      ctx.expect('error mentions magic', result.errors.some((e) => e.toLowerCase().includes('magic')));
    },
  },
  {
    id: 'validator.truncated',
    name: 'AssetValidator - rejects truncated GLB',
    subsystem: 'AssetValidator',
    async run(ctx) {
      const buf = await fetchTestAsset(ctx, VALID_GLB_URL, 'Box.glb');
      if (!buf) return;
      const truncated = buf.slice(0, buf.byteLength - 100);
      const validator = new AssetValidator();
      const result = validator.validate(truncated);
      ctx.expect('valid=false', result.valid === false);
      ctx.expect('error mentions length or chunk', result.errors.some((e) => e.toLowerCase().includes('length') || e.toLowerCase().includes('chunk')));
    },
  },
  {
    id: 'validator.too_small',
    name: 'AssetValidator - rejects file too small to be a GLB',
    subsystem: 'AssetValidator',
    async run(ctx) {
      const tiny = new ArrayBuffer(5);
      const validator = new AssetValidator();
      const result = validator.validate(tiny);
      ctx.expect('valid=false', result.valid === false);
      ctx.expect('error mentions too small', result.errors.some((e) => e.toLowerCase().includes('small')));
    },
  },
  {
    id: 'validator.unsupported_extension',
    name: 'AssetValidator - warns on unsupported extensions',
    subsystem: 'AssetValidator',
    async run(ctx) {
      const gltfJson = {
        asset: { version: '2.0' },
        extensionsUsed: ['KHR_materials_unlit', 'FAKE_unknown_extension'],
        meshes: [{ primitives: [{ attributes: { POSITION: 0 } }] }],
        accessors: [{ bufferView: 0, componentType: 5126, count: 3, type: 'VEC3' }],
        bufferViews: [{ buffer: 0, byteOffset: 0, byteLength: 36 }],
        buffers: [{ byteLength: 36 }],
      };
      const binChunk = new ArrayBuffer(36);
      const glb = buildGlb(gltfJson, binChunk);
      const validator = new AssetValidator();
      const result = validator.validate(glb);
      ctx.expect('valid=true (warnings only)', result.valid === true);
      ctx.expect('>=1 warning about unsupported extension', result.warnings.some((w) => w.toLowerCase().includes('unsupported') || w.toLowerCase().includes('fake')));
      ctx.expect('usesExtensions includes both', result.stats.usesExtensions.length === 2);
    },
  },
];

async function fetchTestAsset(ctx: any, url: string, filename: string): Promise<ArrayBuffer | null> {
  ctx.log(`Fetching ${filename}...`);
  const localPath = `${TEST_DIR}${filename}`;
  const dirInfo = await FileSystem.getInfoAsync(TEST_DIR);
  if (!dirInfo.exists) await FileSystem.makeDirectoryAsync(TEST_DIR, { intermediates: true });
  const info = await FileSystem.getInfoAsync(localPath);
  if (!info.exists) {
    const result = await FileSystem.downloadAsync(url, localPath);
    if (result.status !== 200) {
      ctx.expect(`${filename} download succeeded`, false, 'HTTP 200', `HTTP ${result.status}`);
      return null;
    }
  }
  const b64 = await FileSystem.readAsStringAsync(localPath, { encoding: 'base64' });
  try {
    // @ts-ignore
    if (typeof Buffer !== 'undefined') {
      // @ts-ignore
      const buf = Buffer.from(b64, 'base64');
      return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
    }
  } catch { /* fall through */ }
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function buildGlb(json: any, binChunk: ArrayBuffer): ArrayBuffer {
  const jsonBytes = new TextEncoder().encode(JSON.stringify(json));
  const jsonPaddedLen = Math.ceil(jsonBytes.length / 4) * 4;
  const jsonPadded = new Uint8Array(jsonPaddedLen);
  jsonPadded.set(jsonBytes);
  const binPaddedLen = Math.ceil(binChunk.byteLength / 4) * 4;
  const totalLength = 12 + 8 + jsonPaddedLen + 8 + binPaddedLen;
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
  outDv.setUint32(w, binPaddedLen, true);
  outDv.setUint32(w + 4, 0x004e4942, true);
  outBytes.set(new Uint8Array(binChunk), w + 8);
  return out;
}
