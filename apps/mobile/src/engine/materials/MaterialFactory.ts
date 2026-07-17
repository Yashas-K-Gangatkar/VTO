/**
 * engine/materials/MaterialFactory.ts
 *
 * Creates MaterialDescriptor objects from various sources:
 *   - GLTF material JSON (pbrMetallicRoughness, KHR extensions)
 *   - Preset names ("cotton_red", "denim_blue", "silk_black")
 *   - Raw parameters (color, roughness, etc.)
 */

import * as THREE from 'three';
import type { MaterialDescriptor, Color, TextureRef } from '../core/types';

const TAG = '[MaterialFactory]';

export interface MaterialPreset {
  name: string;
  descriptor: MaterialDescriptor;
}

export const FABRIC_PRESETS: Record<string, MaterialPreset> = {
  cotton_white: {
    name: 'cotton_white',
    descriptor: {
      id: 'cotton_white',
      type: 'standard',
      baseColor: { r: 0.95, g: 0.95, b: 0.92 },
      roughness: 0.85,
      metalness: 0.0,
      alphaMode: 'OPAQUE',
      doubleSided: false,
    },
  },
  cotton_red: {
    name: 'cotton_red',
    descriptor: {
      id: 'cotton_red',
      type: 'standard',
      baseColor: { r: 0.78, g: 0.12, b: 0.12 },
      roughness: 0.85,
      metalness: 0.0,
      alphaMode: 'OPAQUE',
      doubleSided: false,
    },
  },
  denim_blue: {
    name: 'denim_blue',
    descriptor: {
      id: 'denim_blue',
      type: 'standard',
      baseColor: { r: 0.20, g: 0.30, b: 0.55 },
      roughness: 0.75,
      metalness: 0.0,
      alphaMode: 'OPAQUE',
      doubleSided: false,
    },
  },
  silk_black: {
    name: 'silk_black',
    descriptor: {
      id: 'silk_black',
      type: 'physical',
      baseColor: { r: 0.05, g: 0.05, b: 0.05 },
      roughness: 0.25,
      metalness: 0.0,
      alphaMode: 'OPAQUE',
      doubleSided: true,
    },
  },
  leather_brown: {
    name: 'leather_brown',
    descriptor: {
      id: 'leather_brown',
      type: 'physical',
      baseColor: { r: 0.25, g: 0.15, b: 0.08 },
      roughness: 0.45,
      metalness: 0.0,
      alphaMode: 'OPAQUE',
      doubleSided: false,
    },
  },
  chiffon_white: {
    name: 'chiffon_white',
    descriptor: {
      id: 'chiffon_white',
      type: 'physical',
      baseColor: { r: 0.95, g: 0.95, b: 0.95 },
      roughness: 0.35,
      metalness: 0.0,
      alphaMode: 'BLEND',
      doubleSided: true,
    },
  },
};

export class MaterialFactory {
  static fromPreset(name: string): MaterialDescriptor | null {
    const preset = FABRIC_PRESETS[name];
    if (!preset) {
      console.warn(TAG, `unknown preset: ${name}`);
      return null;
    }
    return JSON.parse(JSON.stringify(preset.descriptor));
  }

  static fromParams(params: {
    id: string;
    type?: 'standard' | 'physical' | 'basic' | 'phong';
    color?: Color;
    roughness?: number;
    metalness?: number;
    alphaMode?: 'OPAQUE' | 'BLEND' | 'MASK';
    alphaCutoff?: number;
    doubleSided?: boolean;
    baseColorMap?: TextureRef;
    normalMap?: TextureRef;
    roughnessMap?: TextureRef;
    metalnessMap?: TextureRef;
  }): MaterialDescriptor {
    return {
      id: params.id,
      type: params.type ?? 'standard',
      baseColor: params.color ?? { r: 0.8, g: 0.8, b: 0.8 },
      roughness: params.roughness,
      metalness: params.metalness,
      alphaMode: params.alphaMode,
      alphaCutoff: params.alphaCutoff,
      doubleSided: params.doubleSided,
      baseColorMap: params.baseColorMap,
      normalMap: params.normalMap,
      roughnessMap: params.roughnessMap,
      metalnessMap: params.metalnessMap,
    };
  }

  static fromGLTF(
    gltfMaterial: any,
    textureRefResolver: (gltfTextureIndex: number, slot: TextureSlot) => TextureRef | null
  ): MaterialDescriptor {
    const id = `gltf_${Math.random().toString(36).slice(2, 10)}`;
    const isUnlit = !!(gltfMaterial.extensions?.KHR_materials_unlit);
    const isSpecGloss = !!gltfMaterial.extensions?.KHR_materials_pbrSpecularGlossiness;

    const pbr = gltfMaterial.pbrMetallicRoughness ?? {};
    const baseColorFactor = pbr.baseColorFactor ?? [1, 1, 1, 1];

    let type: MaterialDescriptor['type'];
    if (isUnlit) type = 'basic';
    else if (isSpecGloss) type = 'standard';
    else type = 'standard';

    const baseColor: Color = {
      r: baseColorFactor[0] ?? 1,
      g: baseColorFactor[1] ?? 1,
      b: baseColorFactor[2] ?? 1,
    };

    let roughness: number | undefined = pbr.roughnessFactor;
    let metalness: number | undefined = pbr.metallicFactor;

    if (isSpecGloss) {
      const sg = gltfMaterial.extensions.KHR_materials_pbrSpecularGlossiness;
      const spec = sg.specularFactor ?? [1, 1, 1];
      const avgSpec = (spec[0] + spec[1] + spec[2]) / 3;
      roughness = 1 - avgSpec;
      metalness = 0;
    }

    const baseColorMap = pbr.baseColorTexture
      ? textureRefResolver(pbr.baseColorTexture.index, 'baseColor')
      : null;
    const normalMap = gltfMaterial.normalTexture
      ? textureRefResolver(gltfMaterial.normalTexture.index, 'normal')
      : null;
    const metallicRoughnessMap = pbr.metallicRoughnessTexture
      ? textureRefResolver(pbr.metallicRoughnessTexture.index, 'metallicRoughness')
      : null;
    const roughnessMap = metallicRoughnessMap;
    const metalnessMap = metallicRoughnessMap;

    return {
      id,
      type,
      baseColor,
      roughness,
      metalness,
      alphaMode: gltfMaterial.alphaMode ?? 'OPAQUE',
      alphaCutoff: gltfMaterial.alphaCutoff ?? 0.5,
      doubleSided: gltfMaterial.doubleSided ?? false,
      baseColorMap,
      normalMap,
      roughnessMap,
      metalnessMap,
    };
  }

  static threeColorToColor(c: THREE.Color): Color {
    return { r: c.r, g: c.g, b: c.b };
  }

  static colorToThreeColor(c: Color): THREE.Color {
    return new THREE.Color(c.r, c.g, c.b);
  }

  static listPresets(): string[] {
    return Object.keys(FABRIC_PRESETS);
  }
}

export type TextureSlot =
  | 'baseColor'
  | 'normal'
  | 'metallicRoughness'
  | 'roughness'
  | 'metalness'
  | 'emissive'
  | 'occlusion';
