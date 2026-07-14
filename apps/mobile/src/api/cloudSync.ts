/**
 * Cloud Sync API Client
 */

const API_URL = 'http://Yashass-MacBook-Pro.local:8000';

export interface SyncUploadResult {
  status: string;
  body_id: string;
}

export interface SyncOtpResult {
  status: string;
  mock_otp?: string;
}

export interface SyncRetrieveResult {
  status: string;
  body_id: string;
  model_base64: string;
}

export async function syncUploadBody(
  phoneNumber: string,
  modelUri: string
): Promise<SyncUploadResult> {
  const formData = new FormData();
  formData.append('phone_number', phoneNumber);
  formData.append('model_file', {
    uri: modelUri,
    type: 'model/gltf-binary',
    name: 'body.glb',
  } as any);

  const res = await fetch(`${API_URL}/api/v1/body/sync-upload`, {
    method: 'POST',
    body: formData,
  });

  if (!res.ok) throw new Error(`Upload failed: ${res.status}`);
  return res.json();
}

export async function syncRequestOtp(
  phoneNumber: string
): Promise<SyncOtpResult> {
  const formData = new FormData();
  formData.append('phone_number', phoneNumber);

  const res = await fetch(`${API_URL}/api/v1/body/sync-request`, {
    method: 'POST',
    body: formData,
  });

  if (!res.ok) throw new Error(`OTP request failed: ${res.status}`);
  return res.json();
}

export async function syncRetrieveBody(
  phoneNumber: string,
  otp: string
): Promise<SyncRetrieveResult> {
  const formData = new FormData();
  formData.append('phone_number', phoneNumber);
  formData.append('otp', otp);

  const res = await fetch(`${API_URL}/api/v1/body/sync-retrieve`, {
    method: 'POST',
    body: formData,
  });

  if (!res.ok) throw new Error(`Retrieve failed: ${res.status}`);
  return res.json();
}

export async function getStatus(): Promise<{ gpu_enabled: boolean; mode: string }> {
  try {
    const res = await fetch(`${API_URL}/api/v1/status`);
    return res.json();
  } catch {
    return { gpu_enabled: false, mode: 'offline' };
  }
}
