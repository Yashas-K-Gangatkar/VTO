/**
 * VTO API client for mobile app.
 * Change API_URL to your deployed API URL.
 */

const API_URL = 'http://Yashass-MacBook-Pro.local:8000'; // Mac local network
// const API_URL = 'http://localhost:8000'; // iOS simulator
// const API_URL = 'https://your-api.onrender.com'; // Production

export interface BodyProfile {
  body_id: string;
  body_measurements: Record<string, any>;
  validation_status: string;
  validation_errors: string[];
  mode?: string;
}

export interface GarmentProfile {
  garment_id: string;
  category: string;
  color: { name: string; primary: string };
  fabric: { type: string; confidence: number };
  mode?: string;
}

export interface TryOnResult {
  image: string;
  render_time_ms: number;
  quality_score: number;
  mode: string;
}

export async function scanBody(photos: { uri: string; angle: string }[]): Promise<BodyProfile> {
  const formData = new FormData();
  const angles = photos.map(p => p.angle).join(',');
  formData.append('angles', angles);

  photos.forEach(p => {
    const filename = `${p.angle}.jpg`;
    formData.append('photos', {
      uri: p.uri,
      type: 'image/jpeg',
      name: filename,
    } as any);
  });

  const res = await fetch(`${API_URL}/api/v1/body/scan`, {
    method: 'POST',
    body: formData,
  });

  if (!res.ok) throw new Error(`scanBody failed: ${res.status}`);
  return res.json();
}

export async function analyzeGarment(uri: string): Promise<GarmentProfile> {
  const formData = new FormData();
  formData.append('front_image', {
    uri,
    type: 'image/jpeg',
    name: 'front.jpg',
  } as any);

  const res = await fetch(`${API_URL}/api/v1/garment/analyze`, {
    method: 'POST',
    body: formData,
  });

  if (!res.ok) throw new Error(`analyzeGarment failed: ${res.status}`);
  return res.json();
}

export async function tryOn(personUri: string, garmentUri: string): Promise<TryOnResult> {
  const formData = new FormData();
  formData.append('person_image', {
    uri: personUri,
    type: 'image/jpeg',
    name: 'person.jpg',
  } as any);
  formData.append('garment_image', {
    uri: garmentUri,
    type: 'image/jpeg',
    name: 'garment.jpg',
  } as any);

  const res = await fetch(`${API_URL}/api/v1/tryon`, {
    method: 'POST',
    body: formData,
  });

  if (!res.ok) throw new Error(`tryOn failed: ${res.status}`);
  return res.json();
}

export async function getStatus(): Promise<{ gpu_enabled: boolean; mode: string }> {
  const res = await fetch(`${API_URL}/api/v1/status`);
  return res.json();
}
