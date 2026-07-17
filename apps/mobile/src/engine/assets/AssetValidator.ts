/**
 * engine/assets/AssetValidator.ts
 *
 * Validates GLB files before they reach GLTFLoader.
 */

const GLB_MAGIC = 0x46546c67; // 'glTF' little-endian
const GLB_VERSION_SUPPORTED = 2;
const CHUNK_TYPE_JSON = 0x4e4f534a;
const CHUNK_TYPE_BIN = 0x004e4942;

export interface ValidationResult {
  valid: boolean;
  errors: string[];
  warnings: string[];
  stats: {
    fileSizeBytes: number;
    jsonChunkBytes: number;
    binChunkBytes: number;
    meshCount: number;
    materialCount: number;
    textureCount: number;
    accessorCount: number;
    bufferViewCount: number;
    usesExtensions: string[];
  };
}

export interface IAssetValidator {
  validate(buf: ArrayBuffer): ValidationResult;
  validateBytes(bytes: Uint8Array): ValidationResult;
}

export class AssetValidator implements IAssetValidator {
  validate(buf: ArrayBuffer): ValidationResult {
    return this.validateBytes(new Uint8Array(buf));
  }

  validateBytes(bytes: Uint8Array): ValidationResult {
    const errors: string[] = [];
    const warnings: string[] = [];
    const stats = {
      fileSizeBytes: bytes.byteLength,
      jsonChunkBytes: 0,
      binChunkBytes: 0,
      meshCount: 0,
      materialCount: 0,
      textureCount: 0,
      accessorCount: 0,
      bufferViewCount: 0,
      usesExtensions: [] as string[],
    };

    if (bytes.byteLength < 12) {
      errors.push('File too small to be a GLB (need >=12 byte header)');
      return { valid: false, errors, warnings, stats };
    }

    const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const magic = dv.getUint32(0, true);
    const version = dv.getUint32(4, true);
    const length = dv.getUint32(8, true);

    if (magic !== GLB_MAGIC) {
      errors.push(`Invalid GLB magic: 0x${magic.toString(16)} (expected 0x${GLB_MAGIC.toString(16)})`);
    }
    if (version !== GLB_VERSION_SUPPORTED) {
      errors.push(`Unsupported GLB version: ${version} (only version ${GLB_VERSION_SUPPORTED} supported)`);
    }
    if (length !== bytes.byteLength) {
      errors.push(`Header length ${length} != actual file size ${bytes.byteLength} (truncated?)`);
    }

    if (errors.length > 0) {
      return { valid: false, errors, warnings, stats };
    }

    let offset = 12;
    let jsonStr = '';
    let binOffset = 0;
    let binLength = 0;
    let chunkIndex = 0;

    while (offset + 8 <= bytes.byteLength) {
      const chunkLength = dv.getUint32(offset, true);
      const chunkType = dv.getUint32(offset + 4, true);
      const chunkDataStart = offset + 8;
      const chunkDataEnd = chunkDataStart + chunkLength;

      if (chunkDataEnd > bytes.byteLength) {
        errors.push(`Chunk ${chunkIndex} extends past end of file (offset=${offset}, length=${chunkLength})`);
        break;
      }

      if (chunkType === CHUNK_TYPE_JSON) {
        if (chunkIndex !== 0) {
          warnings.push('JSON chunk is not first (spec violation, attempting anyway)');
        }
        const jsonBytes = bytes.subarray(chunkDataStart, chunkDataEnd);
        const trimmed = this.trimTrailingNulls(jsonBytes);
        try {
          jsonStr = new TextDecoder().decode(trimmed);
        } catch (e: any) {
          errors.push(`Failed to decode JSON chunk as UTF-8: ${e.message}`);
        }
        stats.jsonChunkBytes = chunkLength;
      } else if (chunkType === CHUNK_TYPE_BIN) {
        if (chunkIndex !== 1) {
          warnings.push(`BIN chunk is at index ${chunkIndex} (expected 1)`);
        }
        binOffset = chunkDataStart;
        binLength = chunkLength;
        stats.binChunkBytes = chunkLength;
      } else {
        warnings.push(`Unknown chunk type 0x${chunkType.toString(16)} at index ${chunkIndex}`);
      }

      offset = chunkDataEnd;
      chunkIndex += 1;
    }

    if (chunkIndex === 0) {
      errors.push('GLB has no chunks');
      return { valid: false, errors, warnings, stats };
    }

    let gltfJson: any = null;
    try {
      gltfJson = JSON.parse(jsonStr);
    } catch (e: any) {
      errors.push(`JSON chunk is not valid JSON: ${e.message}`);
      return { valid: false, errors, warnings, stats };
    }

    if (!gltfJson.asset || gltfJson.asset.version !== '2.0') {
      errors.push(`glTF asset.version is "${gltfJson.asset?.version}" (expected "2.0")`);
    }

    stats.meshCount = gltfJson.meshes?.length ?? 0;
    stats.materialCount = gltfJson.materials?.length ?? 0;
    stats.textureCount = gltfJson.textures?.length ?? 0;
    stats.accessorCount = gltfJson.accessors?.length ?? 0;
    stats.bufferViewCount = gltfJson.bufferViews?.length ?? 0;
    stats.usesExtensions = gltfJson.extensionsUsed ?? [];

    if (stats.meshCount === 0) {
      warnings.push('glTF has 0 meshes — nothing to render');
    }
    if (stats.accessorCount === 0) {
      warnings.push('glTF has 0 accessors — geometry data missing');
    }

    const unsupported = stats.usesExtensions.filter((ext) =>
      !['KHR_materials_pbrSpecularGlossiness', 'KHR_materials_unlit',
         'KHR_texture_transform', 'KHR_mesh_quantization',
         'KHR_draco_mesh_compression', 'KHR_materials_clearcoat',
         'KHR_materials_transmission', 'KHR_materials_ior',
         'KHR_materials_sheen', 'KHR_materials_specular',
         'KHR_materials_volume', 'KHR_lights_punctual',
         'KHR_materials_emissive_strength'].includes(ext)
    );
    if (unsupported.length > 0) {
      warnings.push(`Unsupported extensions (may render incorrectly): ${unsupported.join(', ')}`);
    }

    if (gltfJson.buffers?.[0]) {
      const declaredLength = gltfJson.buffers[0].byteLength ?? 0;
      if (declaredLength > binLength) {
        errors.push(`Buffer declares byteLength=${declaredLength} but BIN chunk is only ${binLength} bytes`);
      }
    }

    return {
      valid: errors.length === 0,
      errors,
      warnings,
      stats,
    };
  }

  private trimTrailingNulls(bytes: Uint8Array): Uint8Array {
    let end = bytes.byteLength;
    while (end > 0 && bytes[end - 1] === 0) end -= 1;
    return bytes.subarray(0, end);
  }
}
