/**
 * VTO SDK — Virtual Try-On client for web retailers + Cloud Sync.
 */

export interface VTOConfig {
  apiKey: string;
  baseUrl: string;
}

export class VTOClient {
  private config: VTOConfig;

  constructor(config: VTOConfig) {
    this.config = config;
  }

  /**
   * Upload 3D body model to Cloud Wallet (Digital Twin).
   */
  async syncUploadBody(phoneNumber: string, modelBlob: Blob): Promise<{ status: string; body_id: string }> {
    const formData = new FormData();
    formData.append('phone_number', phoneNumber);
    formData.append('model_file', modelBlob, 'body.glb');

    const res = await fetch(`${this.config.baseUrl}/api/v1/body/sync-upload`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${this.config.apiKey}` },
      body: formData,
    });

    if (!res.ok) throw new Error(`syncUploadBody failed: ${res.status}`);
    return res.json();
  }

  /**
   * Request OTP to retrieve 3D body model on a new device.
   */
  async syncRequestOtp(phoneNumber: string): Promise<{ status: string; mock_otp?: string }> {
    const formData = new FormData();
    formData.append('phone_number', phoneNumber);

    const res = await fetch(`${this.config.baseUrl}/api/v1/body/sync-request`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${this.config.apiKey}` },
      body: formData,
    });

    if (!res.ok) throw new Error(`syncRequestOtp failed: ${res.status}`);
    return res.json();
  }

  /**
   * Retrieve 3D body model from Cloud Wallet using OTP.
   */
  async syncRetrieveBody(phoneNumber: string, otp: string): Promise<{ status: string; model_base64: string }> {
    const formData = new FormData();
    formData.append('phone_number', phoneNumber);
    formData.append('otp', otp);

    const res = await fetch(`${this.config.baseUrl}/api/v1/body/sync-retrieve`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${this.config.apiKey}` },
      body: formData,
    });

    if (!res.ok) throw new Error(`syncRetrieveBody failed: ${res.status}`);
    return res.json();
  }

  /**
   * Run 2D photorealistic try-on (Premium feature).
   */
  async tryOn(
    personImage: Blob,
    garmentImage: Blob,
    options?: { width?: number; height?: number; seed?: number },
  ): Promise<{ image: string; render_time_ms: number; mode: string }> {
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
   * Check API status.
   */
  async getStatus(): Promise<{ gpu_enabled: boolean; mode: string }> {
    const res = await fetch(`${this.config.baseUrl}/api/v1/status`);
    return res.json();
  }
}

export default VTOClient;
