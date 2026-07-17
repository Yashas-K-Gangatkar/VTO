/**
 * engine/streaming/AssetStreamer.ts
 *
 * Progressive asset streaming — shows a tiny placeholder immediately
 * while the full-quality asset downloads in the background.
 */

import * as THREE from 'three';
import type {
  AssetDescriptor, LoadedAsset,
} from '../core/types';
import type { IAssetManager } from '../assets/AssetManager';
import type { ILODSystem } from '../geometry/LODSystem';

const TAG = '[AssetStreamer]';

export interface StreamResult {
  preview: LoadedAsset;
  fullReady: Promise<LoadedAsset>;
  cancel: () => void;
}

export interface IAssetStreamer {
  stream(descriptor: AssetDescriptor, opts?: StreamOptions): Promise<StreamResult>;
  getActiveStreams(): StreamStatus[];
}

export interface StreamOptions {
  groupId?: string;
  previewUrl?: string;
  fullUrl?: string;
  crossFadeSec?: number;
  generatePlaceholder?: boolean;
  priority?: number;
}

export interface StreamStatus {
  descriptorId: string;
  phase: 'preview-ready' | 'downloading-full' | 'parsing-full' | 'swapping' | 'complete' | 'cancelled' | 'error';
  progress: number;
  bytesLoaded?: number;
  bytesTotal?: number;
  startedAt: number;
}

export class AssetStreamer implements IAssetStreamer {
  private assetManager: IAssetManager;
  private lodSystem?: ILODSystem;
  private activeStreams = new Map<string, StreamStatus>();
  private maxConcurrentStreams = 2;
  private queue: Array<{ descriptor: AssetDescriptor; opts?: StreamOptions; resolve: (r: StreamResult) => void; reject: (e: any) => void }> = [];

  constructor(assetManager: IAssetManager, lodSystem?: ILODSystem) {
    this.assetManager = assetManager;
    this.lodSystem = lodSystem;
  }

  async stream(descriptor: AssetDescriptor, opts: StreamOptions = {}): Promise<StreamResult> {
    const generatePlaceholder = opts.generatePlaceholder ?? true;

    let preview: LoadedAsset;
    const previewDesc: AssetDescriptor = {
      ...descriptor,
      id: `${descriptor.id}__preview`,
      url: opts.previewUrl ?? (descriptor as any).previewUrl ?? '',
      kind: descriptor.kind,
    };

    if (previewDesc.url) {
      try {
        preview = await this.assetManager.load(previewDesc, { lod: 'preview' });
      } catch (e) {
        console.warn(TAG, `preview load failed for ${descriptor.id}: ${e}`);
        preview = this.generatePlaceholderAsset(descriptor);
      }
    } else if (generatePlaceholder) {
      preview = this.generatePlaceholderAsset(descriptor);
    } else {
      throw new Error(`No previewUrl for ${descriptor.id} and generatePlaceholder=false`);
    }

    const groupId = opts.groupId ?? descriptor.id;
    if (this.lodSystem) {
      this.lodSystem.register(groupId, 'preview', preview);
    }

    let cancelled = false;
    const status: StreamStatus = {
      descriptorId: descriptor.id,
      phase: 'downloading-full',
      progress: 0,
      startedAt: Date.now(),
    };
    this.activeStreams.set(descriptor.id, status);

    const fullReady = new Promise<LoadedAsset>((resolve, reject) => {
      if (this.activeStreams.size > this.maxConcurrentStreams) {
        this.queue.push({ descriptor, opts, resolve, reject });
        return;
      }

      const fullDesc: AssetDescriptor = {
        ...descriptor,
        url: opts.fullUrl ?? descriptor.url,
      };

      this.assetManager.load(fullDesc, { lod: 'high' })
        .then((full) => {
          if (cancelled) {
            this.assetManager.release(full);
            status.phase = 'cancelled';
            return;
          }

          if (this.lodSystem) {
            this.lodSystem.register(groupId, 'high', full, {
              onSwap: (from, to) => {
                if (to === 'high') {
                  status.phase = 'complete';
                  status.progress = 1;
                }
              },
            });

            setTimeout(() => {
              if (!cancelled) {
                this.lodSystem!.forceLOD(groupId, 'high');
                status.phase = 'swapping';
              }
            }, 50);
          }

          status.phase = 'parsing-full';
          status.progress = 0.95;
          resolve(full);
        })
        .catch((e) => {
          status.phase = 'error';
          console.error(TAG, `full load failed for ${descriptor.id}:`, e);
          reject(e);
        });
    });

    const cancel = () => {
      cancelled = true;
      status.phase = 'cancelled';
      this.activeStreams.delete(descriptor.id);
      this.processQueue();
    };

    return { preview, fullReady, cancel };
  }

  getActiveStreams(): StreamStatus[] {
    return Array.from(this.activeStreams.values());
  }

  private processQueue(): void {
    while (this.queue.length > 0 && this.activeStreams.size < this.maxConcurrentStreams) {
      const item = this.queue.shift()!;
      this.stream(item.descriptor, item.opts)
        .then(item.resolve)
        .catch(item.reject);
    }
  }

  private generatePlaceholderAsset(descriptor: AssetDescriptor): LoadedAsset {
    const geom = new THREE.BoxGeometry(0.6, 1.7, 0.3);
    const mat = new THREE.MeshBasicMaterial({
      color: 0x6C63FF, wireframe: true, transparent: true, opacity: 0.4,
    });
    const mesh = new THREE.Mesh(geom, mat);
    const group = new THREE.Group();
    group.add(mesh);

    const box = new THREE.Box3().setFromObject(group);
    const size = box.getSize(new THREE.Vector3());
    const center = box.getCenter(new THREE.Vector3());

    return {
      descriptor: { ...descriptor, id: `${descriptor.id}__placeholder` },
      scene: group,
      bbox: {
        min: { x: box.min.x, y: box.min.y, z: box.min.z },
        max: { x: box.max.x, y: box.max.y, z: box.max.z },
        center: { x: center.x, y: center.y, z: center.z },
        size: { x: size.x, y: size.y, z: size.z },
      },
      stats: {
        meshCount: 1, triangleCount: 12, vertexCount: 8,
        materialCount: 1, textureCount: 0, estimatedMemoryBytes: 384,
      },
      skeleton: null,
      activeLOD: 'preview',
      localPath: '',
      loadTimeMs: 0,
    };
  }
}
