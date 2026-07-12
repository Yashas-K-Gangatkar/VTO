/**
 * VTO SDK — Virtual Try-On client for web retailers.
 *
 * Usage:
 *   import { VTOClient } from '@vto/sdk';
 *   const client = new VTOClient({ apiKey: 'your-key', baseUrl: 'https://your-api.com' });
 *   const profile = await client.scanBody(photos);
 *   const garment = await client.analyzeGarment(frontPhoto);
 *   const result = await client.tryOn(personPhoto, garmentPhoto);
 */

export interface VTOConfig {
  apiKey: string;
  baseUrl: string;
}

export interface BodyProfile {
  body_id: string;
  version: number;
  body_measurements: Record<string, {
    value: number;
    unit: string;
    confidence: number;
    source_photos: string[];
    method: string;
  }>;
  validation_status: 'approved' | 'rejected' | 'pending';
  validation_errors: string[];
  mode?: string;
}

export interface GarmentProfile {
  garment_id: string;
  version: number;
  retailer_id: string;
  sku: string;
  category: string;
  subcategory: string;
  color: { primary: string; secondary: string | null; name: string };
  pattern: string;
  sleeve_length: string;
  collar_type: string;
  fabric: { type: string; confidence: number };
  measurements: Record<string, number | null>;
  mode?: string;
}

export interface TryOnResult {
  image: string;  // base64 PNG
  render_time_ms: number;
  quality_score: number;
  mode: string;
}

export class VTOClient {
  private config: VTOConfig;

  constructor(config: VTOConfig) {
    this.config = config;
  }

  /**
   * Scan body from 6 photos.
   * Returns persistent BodyProfile with measurements.
   */
  async scanBody(photos: { image: Blob; angle: string }[]): Promise<BodyProfile> {
    const formData = new FormData();
    const angles = photos.map(p => p.angle).join(',');
    formData.append('angles', angles);
    photos.forEach(p => formData.append('photos', p.image, `${p.angle}.jpg`));

    const res = await fetch(`${this.config.baseUrl}/api/v1/body/scan`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${this.config.apiKey}` },
      body: formData,
    });

    if (!res.ok) throw new Error(`scanBody failed: ${res.status}`);
    return res.json();
  }

  /**
   * Analyze garment from photos.
   * Returns GarmentProfile with category, color, fabric, etc.
   */
  async analyzeGarment(
    frontImage: Blob,
    backImage?: Blob,
    retailerId?: string,
    sku?: string,
  ): Promise<GarmentProfile> {
    const formData = new FormData();
    formData.append('front_image', frontImage, 'front.jpg');
    if (backImage) formData.append('back_image', backImage, 'back.jpg');
    if (retailerId) formData.append('retailer_id', retailerId);
    if (sku) formData.append('sku', sku);

    const res = await fetch(`${this.config.baseUrl}/api/v1/garment/analyze`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${this.config.apiKey}` },
      body: formData,
    });

    if (!res.ok) throw new Error(`analyzeGarment failed: ${res.status}`);
    return res.json();
  }

  /**
   * Run virtual try-on.
   * Returns result image as base64 PNG.
   */
  async tryOn(
    personImage: Blob,
    garmentImage: Blob,
    options?: { width?: number; height?: number; seed?: number },
  ): Promise<TryOnResult> {
    const formData = new FormData();
    formData.append('person_image', personImage, 'person.jpg');
    formData.append('garment_image', garmentImage, 'garment.jpg');
    if (options?.width) formData.append('width', String(options.width));
    if (options?.height) formData.append('height', String(options.height));
    if (options?.seed) formData.append('seed', String(options.seed));

    const res = await fetch(`${this.config.baseUrl}/api/v1/tryon`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${this.config.apiKey}` },
      body: formData,
    });

    if (!res.ok) throw new Error(`tryOn failed: ${res.status}`);
    return res.json();
  }

  /**
   * Check API status (GPU enabled or mock mode).
   */
  async getStatus(): Promise<{ gpu_enabled: boolean; mode: string }> {
    const res = await fetch(`${this.config.baseUrl}/api/v1/status`);
    return res.json();
  }
}

export default VTOClient;
