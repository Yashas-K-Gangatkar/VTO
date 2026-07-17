import "./RNPolyfill";
import * as FileSystem from 'expo-file-system/legacy';
import { TextureLoader as ThreeTextureLoader } from 'three';
import * as THREE from 'three';
import type { TextureRef } from '../core/types';

const TAG = '[TextureLoader]';
const CHUNK_TYPE_JSON = 0x4e4f534a;
const CHUNK_TYPE_BIN = 0x004e4942;

export interface ExtractedTextures {
  imageUris: Record<number, string>;
  patchedJson: any;
  totalBytes: number;
}

export interface ITextureLoader {
  extractFromGLB(glbBuffer: ArrayBuffer, tempDir: string): Promise<ExtractedTextures>;
  loadTexture(ref: TextureRef): Promise<THREE.Texture>;
  disposeAll(): void;
  getCacheStats(): { count: number; estimatedBytes: number };
}

export class TextureLoader implements ITextureLoader {
  private textureCache = new Map<string, THREE.Texture>();
  private threeLoader = new ThreeTextureLoader();

  constructor() {
    // @ts-ignore
    if (this.threeLoader.setCrossOrigin) this.threeLoader.setCrossOrigin('anonymous');
  }

  async extractFromGLB(glbBuffer: ArrayBuffer, tempDir: string): Promise<ExtractedTextures> {
    const bytes = new Uint8Array(glbBuffer);
    const dv = new DataView(glbBuffer);

    const dirInfo = await FileSystem.getInfoAsync(tempDir);
    if (!dirInfo.exists) {
      await FileSystem.makeDirectoryAsync(tempDir, { intermediates: true });
    }

    if (bytes.byteLength < 12 || dv.getUint32(0, true) !== 0x46546c67) {
      throw new Error('Not a valid GLB file (bad magic)');
    }

    let offset = 12;
    let jsonStr = '';
    let binOffset = 0;
    let binLength = 0;

    while (offset + 8 <= bytes.byteLength) {
      const chunkLength = dv.getUint32(offset, true);
      const chunkType = dv.getUint32(offset + 4, true);
      const dataStart = offset + 8;
      if (chunkType === CHUNK_TYPE_JSON) {
        const jsonBytes = bytes.subarray(dataStart, dataStart + chunkLength);
        let end = jsonBytes.byteLength;
        while (end > 0 && jsonBytes[end - 1] === 0) end -= 1;
        jsonStr = new TextDecoder().decode(jsonBytes.subarray(0, end));
      } else if (chunkType === CHUNK_TYPE_BIN) {
        binOffset = dataStart;
        binLength = chunkLength;
      }
      offset = dataStart + chunkLength;
    }

    if (!jsonStr) {
      return { imageUris: {}, patchedJson: null, totalBytes: 0 };
    }

    let gltfJson: any;
    try {
      gltfJson = JSON.parse(jsonStr);
    } catch (e) {
      throw new Error(`GLB JSON chunk parse failed: ${e}`);
    }

    const images = gltfJson.images ?? [];
    const bufferViews = gltfJson.bufferViews ?? [];
    const imageUris: Record<number, string> = {};
    let totalBytes = 0;

    for (let i = 0; i < images.length; i++) {
      const img = images[i];
      if (img.uri) continue;
      if (img.bufferView === undefined) {
        console.warn(TAG, `image[${i}] has no uri and no bufferView — skipping`);
        continue;
      }
      const bv = bufferViews[img.bufferView];
      if (!bv) {
        console.warn(TAG, `image[${i}] references missing bufferView ${img.bufferView}`);
        continue;
      }

      const start = binOffset + (bv.byteOffset ?? 0);
      const end = start + bv.byteLength;
      if (end > binOffset + binLength) {
        console.warn(TAG, `image[${i}] extends past BIN chunk`);
        continue;
      }
      const imageBytes = bytes.subarray(start, end);

      const mime = img.mimeType ?? 'image/png';
      const ext = mime === 'image/jpeg' ? 'jpg' : 'png';
      const filePath = `${tempDir}img_${i}.${ext}`;

      const b64 = this.uint8ToBase64(imageBytes);
      await FileSystem.writeAsStringAsync(filePath, b64, { encoding: 'base64' });

      imageUris[i] = `file://${filePath}`;
      totalBytes += imageBytes.byteLength;

      // CRITICAL FIX: Set uri AND delete bufferView, KEEP mimeType
      // GLTFLoader's uri path uses mimeType.match() to determine format.
      // If mimeType is deleted, mimeType.match() throws "Cannot read property 'match' of undefined".
      img.uri = `file://${filePath}`;
      delete img.bufferView;
      // DO NOT delete img.mimeType — GLTFLoader needs it
    }

    if (Object.keys(imageUris).length > 0) {
      console.log(TAG, `extracted ${Object.keys(imageUris).length} textures (${(totalBytes / 1024).toFixed(1)} KB)`);
    }

    return { imageUris, patchedJson: gltfJson, totalBytes };
  }

  async loadTexture(ref: TextureRef): Promise<THREE.Texture> {
    const cached = this.textureCache.get(ref.cacheKey);
    if (cached) return cached;

    return new Promise<THREE.Texture>((resolve, reject) => {
      this.threeLoader.load(
        ref.uri,
        (texture) => {
          if (ref.colorSpace === 'srgb') {
            texture.colorSpace = THREE.SRGBColorSpace;
          }
          if (ref.wrapS === 'repeat') texture.wrapS = THREE.RepeatWrapping;
          else if (ref.wrapS === 'mirror') texture.wrapS = THREE.MirroredRepeatWrapping;
          else texture.wrapS = THREE.ClampToEdgeWrapping;
          if (ref.wrapT === 'repeat') texture.wrapT = THREE.RepeatWrapping;
          else if (ref.wrapT === 'mirror') texture.wrapT = THREE.MirroredRepeatWrapping;
          else texture.wrapT = THREE.ClampToEdgeWrapping;
          texture.needsUpdate = true;
          this.textureCache.set(ref.cacheKey, texture);
          resolve(texture);
        },
        undefined,
        (err) => reject(new Error(`TextureLoader.load failed for ${ref.uri}: ${err?.message || err}`))
      );
    });
  }

  disposeAll(): void {
    for (const tex of this.textureCache.values()) {
      tex.dispose();
    }
    this.textureCache.clear();
  }

  getCacheStats(): { count: number; estimatedBytes: number } {
    let bytes = 0;
    for (const tex of this.textureCache.values()) {
      const img = tex.image as any;
      if (img?.width && img?.height) {
        bytes += img.width * img.height * 4 * 1.33;
      }
    }
    return { count: this.textureCache.size, estimatedBytes: bytes };
  }

  private uint8ToBase64(bytes: Uint8Array): string {
    try {
      // @ts-ignore
      if (typeof Buffer !== 'undefined') {
        // @ts-ignore
        const buf = Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength);
        return buf.toString('base64');
      }
    } catch { /* fall through */ }
    let binary = '';
    const chunkSize = 0x8000;
    for (let i = 0; i < bytes.length; i += chunkSize) {
      const chunk = bytes.subarray(i, i + chunkSize);
      binary += String.fromCharCode.apply(null, Array.from(chunk) as any);
    }
    return btoa(binary);
  }
}
