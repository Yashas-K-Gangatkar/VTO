import * as FileSystem from 'expo-file-system/legacy';
import type { AssetDescriptor, AssetKind, CacheEntry, CacheManifest } from '../core/types';

const TAG = '[CacheManager]';
const MANIFEST_SCHEMA_VERSION = 1;
const DEFAULT_KIND_BUDGETS: Record<AssetKind, number> = {
  body: Number.MAX_SAFE_INTEGER, garment: 200 * 1024 * 1024,
  accessory: 50 * 1024 * 1024, environment: 100 * 1024 * 1024, animation: 20 * 1024 * 1024,
};

export interface ICacheManager {
  get(descriptor: AssetDescriptor): Promise<CacheEntry | null>;
  put(descriptor: AssetDescriptor, sourcePath: string): Promise<CacheEntry>;
  invalidate(id: string): Promise<void>;
  invalidateAll(): Promise<void>;
  getManifest(): Promise<CacheManifest>;
  prune(): Promise<{ evictedIds: string[]; freedBytes: number }>;
  subscribe(listener: (m: CacheManifest) => void): () => void;
}
export interface CacheManagerOptions { cacheDirectory?: string; manifestPath?: string; kindBudgets?: Partial<Record<AssetKind, number>>; }

export class CacheManager implements ICacheManager {
  private cacheDir: string; private manifestPath: string; private kindBudgets: Record<AssetKind, number>;
  private manifest: CacheManifest | null = null;
  private listeners = new Set<(m: CacheManifest) => void>();
  private initPromise: Promise<void> | null = null;

  constructor(opts: CacheManagerOptions = {}) {
    const baseDir = opts.cacheDirectory ?? `${FileSystem.documentDirectory}asset_cache/`;
    this.cacheDir = baseDir.endsWith('/') ? baseDir : baseDir + '/';
    this.manifestPath = opts.manifestPath ?? `${this.cacheDir}manifest.json`;
    this.kindBudgets = { ...DEFAULT_KIND_BUDGETS, ...(opts.kindBudgets ?? {}) };
  }

  private async ensureDir(dirPath: string): Promise<void> {
    if (!dirPath) return;
    const normalized = dirPath.endsWith('/') ? dirPath.slice(0, -1) : dirPath;
    if (!normalized) return;
    const info = await FileSystem.getInfoAsync(normalized);
    if (info.exists && (info as any).isDirectory !== false) return;
    const parent = normalized.substring(0, normalized.lastIndexOf('/'));
    if (parent && parent.length > 0 && parent !== normalized) await this.ensureDir(parent);
    try { await FileSystem.makeDirectoryAsync(normalized, { intermediates: true }); }
    catch (e: any) { if (!String(e?.message||'').includes('already exists')) console.warn(TAG, `ensureDir ${normalized}:`, e); }
  }

  private async init(): Promise<void> { if (!this.initPromise) this.initPromise = this._init(); return this.initPromise; }

  private async _init(): Promise<void> {
    await this.ensureDir(this.cacheDir);
    try {
      const mi = await FileSystem.getInfoAsync(this.manifestPath);
      if (mi.exists) {
        const parsed = JSON.parse(await FileSystem.readAsStringAsync(this.manifestPath)) as CacheManifest;
        this.manifest = parsed.schemaVersion === MANIFEST_SCHEMA_VERSION ? parsed : this.emptyManifest();
      } else this.manifest = this.emptyManifest();
    } catch (e) { console.warn(TAG, 'manifest load failed:', e); this.manifest = this.emptyManifest(); }
    await this.gcOrphans();
  }

  private emptyManifest(): CacheManifest { return { schemaVersion: MANIFEST_SCHEMA_VERSION, entries: {}, totalBytes: 0, maxBytes: Number.MAX_SAFE_INTEGER }; }

  async get(descriptor: AssetDescriptor): Promise<CacheEntry | null> {
    await this.init();
    const entry = this.manifest!.entries[descriptor.id];
    if (!entry) return null;
    if (entry.descriptor.version !== descriptor.version) { await this.invalidate(descriptor.id); return null; }
    if (descriptor.checksum && entry.validatedChecksum !== descriptor.checksum) { await this.invalidate(descriptor.id); return null; }
    const info = await FileSystem.getInfoAsync(entry.localPath);
    if (!info.exists) { await this.invalidate(descriptor.id); return null; }
    entry.lastAccessedAt = Date.now(); entry.accessCount += 1; this.notifyListeners();
    return entry;
  }

  async put(descriptor: AssetDescriptor, sourcePath: string): Promise<CacheEntry> {
    await this.init();
    const existing = this.manifest!.entries[descriptor.id];
    if (existing) await this.safeDelete(existing.localPath);
    const url = descriptor?.url || sourcePath || '';
    const ext = this.extractExt(url) || this.extractExt(sourcePath) || 'glb';
    const localPath = `${this.cacheDir}${descriptor.id}__v${descriptor.version}.${ext}`;
    const sourceInfo = await FileSystem.getInfoAsync(sourcePath);
    if (!sourceInfo.exists) throw new Error(`CacheManager.put: source missing: ${sourcePath}`);
    await this.ensureDir(this.cacheDir);
    await FileSystem.copyAsync({ from: sourcePath, to: localPath });
    const sizeBytes = sourceInfo.size ?? 0;
    const entry: CacheEntry = { descriptor, localPath, sizeBytes, downloadedAt: Date.now(), lastAccessedAt: Date.now(), accessCount: 1, validatedChecksum: descriptor.checksum };
    this.manifest!.entries[descriptor.id] = entry;
    this.manifest!.totalBytes += sizeBytes;
    this.notifyListeners(); await this.persistManifest();
    this.prune().catch((e) => console.warn(TAG, 'prune failed:', e));
    return entry;
  }

  async invalidate(id: string): Promise<void> {
    await this.init();
    const entry = this.manifest!.entries[id]; if (!entry) return;
    await this.safeDelete(entry.localPath);
    delete this.manifest!.entries[id];
    this.manifest!.totalBytes -= entry.sizeBytes;
    if (this.manifest!.totalBytes < 0) this.manifest!.totalBytes = 0;
    await this.persistManifest(); this.notifyListeners();
  }

  async invalidateAll(): Promise<void> { await this.init(); await Promise.all(Object.keys(this.manifest!.entries).map((id) => this.invalidate(id))); }
  async getManifest(): Promise<CacheManifest> { await this.init(); return { ...this.manifest!, entries: { ...this.manifest!.entries } }; }

  async prune(): Promise<{ evictedIds: string[]; freedBytes: number }> {
    await this.init();
    const evictedIds: string[] = []; let freedBytes = 0;
    const byKind: Record<string, CacheEntry[]> = {};
    for (const e of Object.values(this.manifest!.entries)) (byKind[e.descriptor.kind] ??= []).push(e);
    for (const [kind, entries] of Object.entries(byKind)) {
      const budget = this.kindBudgets[kind as AssetKind] ?? Number.MAX_SAFE_INTEGER;
      let used = entries.reduce((s, e) => s + e.sizeBytes, 0);
      if (used <= budget) continue;
      entries.sort((a, b) => a.lastAccessedAt - b.lastAccessedAt);
      for (const entry of entries) {
        if (used <= budget) break;
        if (entry.descriptor.kind === 'body') continue;
        await this.safeDelete(entry.localPath);
        delete this.manifest!.entries[entry.descriptor.id];
        this.manifest!.totalBytes -= entry.sizeBytes; used -= entry.sizeBytes; freedBytes += entry.sizeBytes;
        evictedIds.push(entry.descriptor.id);
      }
    }
    if (evictedIds.length > 0) { await this.persistManifest(); this.notifyListeners(); }
    return { evictedIds, freedBytes };
  }

  subscribe(l: (m: CacheManifest) => void): () => void { this.listeners.add(l); return () => this.listeners.delete(l); }

  private async gcOrphans(): Promise<void> {
    if (!this.manifest) return;
    try {
      const listed = await FileSystem.readDirectoryAsync(this.cacheDir);
      const known = new Set(Object.values(this.manifest.entries).map((e) => e.localPath));
      for (const f of listed) { const full = `${this.cacheDir}${f}`; if (f !== 'manifest.json' && !known.has(full)) await this.safeDelete(full); }
    } catch (e) { console.warn(TAG, 'gcOrphans failed:', e); }
  }

  private async persistManifest(): Promise<void> {
    if (!this.manifest) return;
    const tmp = `${this.manifestPath}.tmp`;
    try { await this.ensureDir(this.cacheDir); await FileSystem.writeAsStringAsync(tmp, JSON.stringify(this.manifest, null, 2)); await FileSystem.moveAsync({ from: tmp, to: this.manifestPath }); }
    catch (e) { console.error(TAG, 'persist failed:', e); try { await FileSystem.deleteAsync(tmp, { idempotent: true }); } catch {} }
  }

  private async safeDelete(p: string): Promise<void> { try { await FileSystem.deleteAsync(p, { idempotent: true }); } catch (e) { console.warn(TAG, `delete ${p}:`, e); } }

  private extractExt(url: string | undefined | null): string | null {
    if (!url || typeof url !== 'string') return null;
    const m = url.match(/\.([a-zA-Z0-9]+)(?:$|\?)/);
    return m ? m[1].toLowerCase() : null;
  }

  private notifyListeners(): void {
    if (!this.manifest) return;
    const snap: CacheManifest = { ...this.manifest, entries: { ...this.manifest.entries } };
    for (const l of this.listeners) { try { l(snap); } catch (e) { console.warn(TAG, 'listener:', e); } }
  }
}
