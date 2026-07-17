/**
 * engine/viewer/EngineViewer.tsx
 *
 * React Native wrapper around the Engine.
 */

import React, { useState, useEffect, useRef, useCallback } from 'react';
import { View, StyleSheet, ActivityIndicator, Text } from 'react-native';
import { GLView } from 'expo-gl';

import { Engine, type EngineOptions } from '../core/Engine';
import { DebugOverlay } from '../debug/DebugOverlay';
import type { AssetDescriptor } from '../core/types';

const TAG = '[EngineViewer]';

export interface EngineViewerProps {
  bodyModelUri: string | null;
  bodyModelVersion?: string | number;
  garmentUri?: string | null;
  garmentVersion?: string | number;
  debug?: boolean;
  engineOptions?: EngineOptions;
  onBodyReady?: () => void;
  onGarmentReady?: () => void;
  onError?: (err: Error) => void;
}

export function EngineViewer(props: EngineViewerProps) {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [statusText, setStatusText] = useState('Initializing engine...');

  const engineRef = useRef<Engine | null>(null);
  const bodyLoadedRef = useRef(false);

  const onContextCreate = useCallback(async (gl: WebGLRenderingContext) => {
    console.log(TAG, 'onContextCreate fired');
    try {
      if (!engineRef.current) {
        engineRef.current = new Engine(props.engineOptions);
        console.log(TAG, 'engine created');
      }
      const engine = engineRef.current;
      engine.attachGL(gl);
      engine.start();
      setStatusText('Engine ready');

      if (props.bodyModelUri) {
        await loadBody(engine, props.bodyModelUri, props.bodyModelVersion ?? 1);
        bodyLoadedRef.current = true;
        setStatusText('Ready');
        setLoading(false);
        props.onBodyReady?.();
      } else {
        setLoading(false);
      }
    } catch (err: any) {
      console.error(TAG, 'setup error:', err);
      setError(err?.message || String(err));
      setStatusText(`Error: ${err?.message || err}`);
      setLoading(false);
      props.onError?.(err);
    }
  }, [props.bodyModelUri, props.bodyModelVersion, props.engineOptions]);

  useEffect(() => {
    if (!engineRef.current || !engineRef.current.isReady()) return;
    if (!props.bodyModelUri) return;
    if (bodyLoadedRef.current) return;

    const engine = engineRef.current;
    setLoading(true);
    setStatusText('Loading body...');
    loadBody(engine, props.bodyModelUri, props.bodyModelVersion ?? 1)
      .then(() => {
        bodyLoadedRef.current = true;
        setStatusText('Ready');
        setLoading(false);
        props.onBodyReady?.();
      })
      .catch((err) => {
        console.error(TAG, 'body load failed:', err);
        setError(err?.message || String(err));
        setStatusText(`Error: ${err?.message || err}`);
        setLoading(false);
        props.onError?.(err);
      });
  }, [props.bodyModelUri, props.bodyModelVersion]);

  useEffect(() => {
    const engine = engineRef.current;
    if (!engine || !bodyLoadedRef.current) return;

    if (props.garmentUri) {
      setLoading(true);
      setStatusText('Loading garment...');
      const desc: AssetDescriptor = {
        id: 'current_garment',
        version: props.garmentVersion ?? 1,
        url: props.garmentUri,
        kind: 'garment',
      };
      engine.loadGarment(desc)
        .then(() => {
          setStatusText('Ready');
          setLoading(false);
          props.onGarmentReady?.();
        })
        .catch((err: any) => {
          console.error(TAG, 'garment load failed:', err);
          setStatusText(`Garment error: ${err?.message || err}`);
          setLoading(false);
        });
    } else {
      engine.clearGarments();
      setStatusText('Ready');
    }
  }, [props.garmentUri, props.garmentVersion]);

  useEffect(() => {
    return () => {
      if (engineRef.current) {
        engineRef.current.dispose();
        engineRef.current = null;
      }
    };
  }, []);

  if (!props.bodyModelUri) {
    return (
      <View style={styles.placeholder}>
        <Text style={styles.placeholderText}>No 3D model loaded</Text>
      </View>
    );
  }

  const engine = engineRef.current;

  return (
    <View style={styles.container}>
      <GLView
        style={styles.glView}
        onContextCreate={onContextCreate}
        {...(engine ? engine.gestures.getPanHandlers() : {})}
      />
      <View style={styles.statusChip}>
        <Text style={styles.statusText}>{statusText}</Text>
      </View>
      <View style={styles.hintChip} pointerEvents="none">
        <Text style={styles.hintText}>Drag to rotate | Pinch to zoom | Double-tap to reset</Text>
      </View>
      {loading && (
        <View style={styles.loadingOverlay} pointerEvents="none">
          <ActivityIndicator size="large" color="#6C63FF" />
          <Text style={styles.loadingText}>Loading 3D Model...</Text>
        </View>
      )}
      {error && (
        <View style={styles.errorOverlay}>
          <Text style={styles.errorTitle}>3D Load Failed</Text>
          <Text style={styles.errorText}>{error}</Text>
        </View>
      )}
      {props.debug && engine && engine.profiler && (
        <DebugOverlay
          profiler={engine.profiler}
          assetManager={engine.assets}
          lodSystem={engine.lod}
          materialSystem={engine.materials}
          cameraController={engine.camera}
        />
      )}
    </View>
  );
}

async function loadBody(engine: Engine, uri: string, version: string | number): Promise<void> {
  const desc: AssetDescriptor = { id: 'body_default', version, url: uri, kind: 'body' };
  await engine.loadBody(desc);
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#1a1a1a', borderRadius: 16, overflow: 'hidden' },
  glView: { flex: 1, width: '100%' },
  statusChip: { position: 'absolute', top: 8, left: 8, backgroundColor: 'rgba(0,0,0,0.6)', paddingHorizontal: 8, paddingVertical: 4, borderRadius: 8, zIndex: 5 },
  statusText: { color: '#AAA', fontSize: 10, fontWeight: '500' },
  hintChip: { position: 'absolute', bottom: 12, left: 0, right: 0, alignItems: 'center', zIndex: 5 },
  hintText: { color: 'rgba(170, 170, 170, 0.7)', fontSize: 10, fontWeight: '500', backgroundColor: 'rgba(0,0,0,0.4)', paddingHorizontal: 10, paddingVertical: 4, borderRadius: 10, overflow: 'hidden' },
  loadingOverlay: { ...StyleSheet.absoluteFillObject, justifyContent: 'center', alignItems: 'center', backgroundColor: 'rgba(0,0,0,0.3)', zIndex: 10 },
  loadingText: { color: '#FFF', marginTop: 10, fontSize: 14 },
  errorOverlay: { ...StyleSheet.absoluteFillObject, justifyContent: 'center', alignItems: 'center', backgroundColor: 'rgba(0,0,0,0.85)', padding: 24, zIndex: 20 },
  errorTitle: { color: '#FF6B6B', fontSize: 16, fontWeight: '700', marginBottom: 8 },
  errorText: { color: '#FFF', fontSize: 12, textAlign: 'center', lineHeight: 18 },
  placeholder: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#1a1a1a', borderRadius: 16 },
  placeholderText: { color: '#666', fontSize: 14 },
});
