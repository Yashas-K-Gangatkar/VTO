/**
 * 3D Viewer Component - Renders .glb models on phone GPU.
 * Cost per render: $0.00
 */

import React, { useState, useEffect, useRef } from 'react';
import { View, StyleSheet, ActivityIndicator, Text } from 'react-native';
import { GLView } from 'expo-gl';
import { Renderer } from 'expo-three';
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader';
import * as FileSystem from 'expo-file-system';

interface ThreeDViewerProps {
  modelUri: string | null;
  garmentUri?: string | null;
  autoRotate?: boolean;
  onReady?: () => void;
}

export default function ThreeDViewer({
  modelUri,
  garmentUri,
  autoRotate = true,
  onReady,
}: ThreeDViewerProps) {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const animationRef = useRef<number | null>(null);

  const onContextCreate = async (gl: WebGLRenderingContext) => {
    if (!modelUri) {
      setError('No 3D model provided');
      setLoading(false);
      return;
    }

    try {
      const { drawingBufferWidth: width, drawingBufferHeight: height } = gl;
      const scene = new THREE.Scene();
      scene.background = new THREE.Color(0x1a1a1a);

      const camera = new THREE.PerspectiveCamera(50, width / height, 0.1, 1000);
      camera.position.set(0, 1, 4);
      camera.lookAt(0, 0.5, 0);

      const renderer = new Renderer({ gl });
      renderer.setSize(width, height);
      renderer.setPixelRatio(window.devicePixelRatio);

      const ambientLight = new THREE.AmbientLight(0xffffff, 0.6);
      scene.add(ambientLight);

      const dirLight1 = new THREE.DirectionalLight(0xffffff, 1.2);
      dirLight1.position.set(2, 4, 3);
      scene.add(dirLight1);

      const dirLight2 = new THREE.DirectionalLight(0xffffff, 0.4);
      dirLight2.position.set(-2, 2, -1);
      scene.add(dirLight2);

      const loader = new GLTFLoader();

      const loadModel = (url: string): Promise<any> => {
        return new Promise((resolve, reject) => {
          if (url.startsWith('file://') || url.startsWith('content://')) {
            FileSystem.readAsStringAsync(url, {
              encoding: FileSystem.EncodingType.Base64,
            }).then((b64) => {
              const buf = base64ToArrayBuffer(b64);
              loader.parse(buf, '', resolve, reject);
            }).catch(reject);
          } else {
            loader.load(url, resolve, undefined, reject);
          }
        });
      };

      const gltf = await loadModel(modelUri);
      const model = gltf.scene;

      const box = new THREE.Box3().setFromObject(model);
      const size = box.getSize(new THREE.Vector3());
      const center = box.getCenter(new THREE.Vector3());
      const maxDim = Math.max(size.x, size.y, size.z);
      const scale = 2 / maxDim;
      model.scale.setScalar(scale);
      model.position.x = -center.x * scale;
      model.position.y = -center.y * scale;
      model.position.z = -center.z * scale;
      scene.add(model);

      if (garmentUri) {
        try {
          const gltf2 = await loadModel(garmentUri);
          const garment = gltf2.scene;
          garment.scale.setScalar(scale);
          garment.position.copy(model.position);
          scene.add(garment);
        } catch (e) {
          console.warn('Garment load failed:', e);
        }
      }

      setLoading(false);
      onReady?.();

      const animate = () => {
        animationRef.current = requestAnimationFrame(animate);
        if (autoRotate) model.rotation.y += 0.005;
        renderer.render(scene, camera);
        gl.endFrameEXP();
      };
      animate();
    } catch (err: any) {
      console.error('3D setup error:', err);
      setError(err.message || 'Failed to initialize 3D');
      setLoading(false);
    }
  };

  useEffect(() => {
    return () => { if (animationRef.current) cancelAnimationFrame(animationRef.current); };
  }, []);

  if (!modelUri) {
    return (
      <View style={styles.placeholder}>
        <Text style={styles.placeholderText}>No 3D model loaded</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      {loading && (
        <View style={styles.loadingOverlay}>
          <ActivityIndicator size="large" color="#6C63FF" />
          <Text style={styles.loadingText}>Loading 3D Model...</Text>
        </View>
      )}
      {error && (
        <View style={styles.loadingOverlay}>
          <Text style={styles.errorText}>{error}</Text>
        </View>
      )}
      <GLView style={styles.glView} onContextCreate={onContextCreate} />
    </View>
  );
}

function base64ToArrayBuffer(base64: string): ArrayBuffer {
  const binaryString = atob(base64);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes.buffer;
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#1a1a1a', borderRadius: 16, overflow: 'hidden' },
  glView: { flex: 1, width: '100%' },
  loadingOverlay: { ...StyleSheet.absoluteFillObject, justifyContent: 'center', alignItems: 'center', zIndex: 10 },
  loadingText: { color: '#FFF', marginTop: 10, fontSize: 14 },
  errorText: { color: '#FF6B6B', fontSize: 14, textAlign: 'center', padding: 20 },
  placeholder: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#1a1a1a', borderRadius: 16 },
  placeholderText: { color: '#666', fontSize: 14 },
});
