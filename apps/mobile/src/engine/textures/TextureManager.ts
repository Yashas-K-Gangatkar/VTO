import "./RNPolyfill";
import * as THREE from 'three';
import type { TextureRef } from '../core/types';
import { TextureLoader, type ITextureLoader } from './TextureLoader';

const TAG = '[TextureManager]';

export interface TextureManagerOptions {
  maxTotalBytes?: number;
  defaultMaxResolution?: number;
  loader?: ITextureLoader;
}

interface CachedTexture {
  texture: THREE.Texture;
  refCount: number;
  bytes: number;
  createdAt: number;
}

export interface ITextureManager {
  acquire(ref: TextureRef): Promise<THREE.Texture>;
  release(ref: TextureRef): void;
  getMemoryUsage(): { bytes: number; count: number; maxBytes: number };
  disposeAll(): void;
}

export class TextureManager implements ITextureManager {
  private loader: ITextureLoader;
  private maxBytes: number;
  private defaultMaxRes: number;
  private cache = new Map<string, CachedTexture>();
  private inFlight = new Map<string, Promise<THREE.Texture>>();

  constructor(opts: TextureManagerOptions = {}) {
    this.loader = opts.loader ?? new TextureLoader();
    this.maxBytes = opts.maxTotalBytes ?? 256 * 1024 * 1024;
    this.defaultMaxRes = opts.defaultMaxResolution ?? 1024;
  }

  async acquire(ref: TextureRef): Promise<THREE.Texture> {
    const normalized: TextureRef = {
      ...ref,
      maxResolution: ref.maxResolution ?? this.defaultMaxRes,
      colorSpace: ref.colorSpace ?? 'srgb',
      wrapS: ref.wrapS ?? 'clamp',
      wrapT: ref.wrapT ?? 'clamp',
    };

    // Check cache first
    const cached = this.cache.get(normalized.cacheKey);
    if (cached) {
      cached.refCount += 1;
      return cached.texture;
    }

    // Check in-flight — dedupe concurrent requests
    let loadPromise = this.inFlight.get(normalized.cacheKey);
    if (!loadPromise) {
      loadPromise = this.loader.loadTexture(normalized);
      this.inFlight.set(normalized.cacheKey, loadPromise);
    }

    const texture = await loadPromise;

    // After await, check if another acquire already cached it
    const nowCached = this.cache.get(normalized.cacheKey);
    if (nowCached) {
      nowCached.refCount += 1;
      return nowCached.texture;
    }

    // First to cache — create entry with refCount 1
    const img = texture.image as any;
    const w = img?.width ?? 256;
    const h = img?.height ?? 256;
    const bytes = Math.round(w * h * 4 * 1.33);

    this.cache.set(normalized.cacheKey, {
      texture, refCount: 1, bytes, createdAt: Date.now(),
    });

    // Clean up in-flight
    this.inFlight.delete(normalized.cacheKey);

    return texture;
  }

  release(ref: TextureRef): void {
    const entry = this.cache.get(ref.cacheKey);
    if (!entry) {
      console.warn(TAG, `release: ${ref.cacheKey} not in cache`);
      return;
    }
    entry.refCount -= 1;
    if (entry.refCount <= 0) {
      entry.texture.dispose();
      this.cache.delete(ref.cacheKey);
    }
  }

  getMemoryUsage(): { bytes: number; count: number; maxBytes: number } {
    let bytes = 0;
    for (const entry of this.cache.values()) bytes += entry.bytes;
    return { bytes, count: this.cache.size, maxBytes: this.maxBytes };
  }

  disposeAll(): void {
    for (const entry of this.cache.values()) {
      entry.texture.dispose();
    }
    this.cache.clear();
    this.inFlight.clear();
    console.log(TAG, 'disposed all textures');
  }
}
