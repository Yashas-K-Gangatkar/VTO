const g = global as any;
let installed = false;

export function installRNPolyfills(): void {
  if (installed) return;
  installed = true;

  // ---- navigator polyfill (CRITICAL — GLTFLoader uses navigator.userAgent.match()) ----
  if (!g.navigator) {
    g.navigator = {
      userAgent: 'Mozilla/5.0 (React Native) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36',
      platform: 'React Native',
      language: 'en-US',
      languages: ['en-US', 'en'],
      onLine: true,
      hardwareConcurrency: 4,
      maxTouchPoints: 5,
    };
  } else if (!g.navigator.userAgent) {
    g.navigator.userAgent = 'Mozilla/5.0 (React Native) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36';
  }

  // ---- Image polyfill ----
  if (!g.Image) {
    g.Image = class RNImage {
      _src = ''; width = 1; height = 1;
      onload: (() => void) | null = null;
      onerror: ((err: any) => void) | null = null;
      complete = false; naturalWidth = 1; naturalHeight = 1;
      set src(value: string) {
        this._src = value; this.complete = false;
        if (value) setTimeout(() => { this.complete = true; this.onload?.(); }, 0);
      }
      get src(): string { return this._src; }
      addEventListener(event: string, handler: any) {
        if (event === 'load') this.onload = handler;
        else if (event === 'error') this.onerror = handler;
      }
      removeEventListener(event: string, _handler: any) {
        if (event === 'load') this.onload = null;
        else if (event === 'error') this.onerror = null;
      }
    };
  }

  // ---- Canvas polyfill ----
  class RNCanvas {
    width = 1; height = 1;
    getContext() {
      return {
        drawImage: () => {},
        getImageData: (_x: number, _y: number, w: number, h: number) => ({ data: new Uint8Array(w * h * 4), width: w, height: h }),
        putImageData: () => {},
        createImageData: (w: number, h: number) => ({ data: new Uint8Array(w * h * 4), width: w, height: h }),
        fillRect: () => {}, clearRect: () => {}, save: () => {}, restore: () => {},
        translate: () => {}, rotate: () => {}, scale: () => {},
      };
    }
    toDataURL() { return ''; }
    toBlob(cb: any) { if (cb) cb(null); }
  }

  // ---- document polyfill ----
  if (!g.document) {
    g.document = {
      createElement: (tag: string) => {
        if (tag === 'img' || tag === 'image') return new g.Image();
        if (tag === 'canvas') return new RNCanvas();
        return {};
      },
      createElementNS: (_ns: string, name: string) => {
        if (name === 'img' || name === 'image') return new g.Image();
        if (name === 'canvas') return new RNCanvas();
        return {};
      },
      getElementById: () => null,
      getElementsByTagName: () => [],
      body: {}, head: {},
    };
  }

  if (!g.HTMLImageElement) g.HTMLImageElement = g.Image;
  if (!g.HTMLCanvasElement) g.HTMLCanvasElement = RNCanvas;
  if (!g.window) g.window = g;
  if (!g.self) g.self = g;

  // ---- URL polyfill ----
  if (!g.URL) {
    g.URL = { createObjectURL: () => 'blob:' + Math.random().toString(36).slice(2), revokeObjectURL: () => {} };
  } else {
    if (!g.URL.createObjectURL) g.URL.createObjectURL = () => 'blob:' + Math.random().toString(36).slice(2);
    if (!g.URL.revokeObjectURL) g.URL.revokeObjectURL = () => {};
  }

  // ---- Blob polyfill ----
  if (!g.Blob) {
    g.Blob = class RNBlob {
      size: number; type: string; _parts: any[];
      constructor(parts: any[] = [], options: any = {}) {
        this._parts = parts;
        this.size = parts.reduce((s, p) => s + (p.byteLength || p.length || 0), 0);
        this.type = options.type || '';
      }
      slice() { return this; }
      arrayBuffer() {
        const out = new Uint8Array(this.size);
        let off = 0;
        for (const p of this._parts) {
          const bytes = p instanceof Uint8Array ? p : new Uint8Array(p);
          out.set(bytes, off);
          off += bytes.length;
        }
        return Promise.resolve(out.buffer);
      }
      text() { return this.arrayBuffer().then((buf: ArrayBuffer) => new TextDecoder().decode(buf)); }
    };
  }

  // ---- createImageBitmap polyfill (GLTFLoader checks this) ----
  if (!g.createImageBitmap) {
    g.createImageBitmap = async (_blob: any) => {
      // Return a minimal bitmap-like object
      return { width: 1, height: 1, close: () => {} };
    };
  }

  console.log('[RNPolyfill] installed (with navigator.userAgent)');
}

installRNPolyfills();
