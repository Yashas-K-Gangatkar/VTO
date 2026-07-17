/**
 * engine/debug/DebugOverlay.tsx
 *
 * On-screen HUD showing live engine stats.
 */

import React, { useState, useEffect, useRef } from 'react';
import {
  View, Text, TouchableOpacity, StyleSheet, PanResponder,
  GestureResponderEvent,
} from 'react-native';
import type {
  IPerformanceProfiler, FrameStats, RollingStats,
} from './PerformanceProfiler';
import type { IAssetManager } from '../assets/AssetManager';
import type { ILODSystem } from '../geometry/LODSystem';
import type { IMaterialSystem } from '../materials/MaterialSystem';
import type { ICameraController } from '../camera/CameraController';

const TAG = '[DebugOverlay]';

export interface DebugOverlayProps {
  profiler: IPerformanceProfiler;
  assetManager?: IAssetManager;
  lodSystem?: ILODSystem;
  materialSystem?: IMaterialSystem;
  cameraController?: ICameraController;
  initialPosition?: { x: number; y: number };
  startCollapsed?: boolean;
  updateEveryNFrames?: number;
}

export function DebugOverlay(props: DebugOverlayProps) {
  const [collapsed, setCollapsed] = useState(props.startCollapsed ?? false);
  const [position, setPosition] = useState(props.initialPosition ?? { x: 240, y: 80 });
  const [stats, setStats] = useState<FrameStats | null>(null);
  const [rolling, setRolling] = useState<RollingStats | null>(null);
  const panRef = useRef({ x: 0, y: 0 });

  useEffect(() => {
    const unsub = props.profiler.subscribe((s) => {
      setStats(s);
      setRolling(props.profiler.getRollingStats());
    }, props.updateEveryNFrames ?? 30);
    return unsub;
  }, [props.profiler, props.updateEveryNFrames]);

  const panResponder = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => true,
      onMoveShouldSetPanResponder: (_, g) => Math.abs(g.dx) > 2 || Math.abs(g.dy) > 2,
      onPanResponderGrant: () => {
        panRef.current = { ...position };
      },
      onPanResponderMove: (_, g) => {
        setPosition({
          x: Math.max(0, panRef.current.x + g.dx),
          y: Math.max(0, panRef.current.y + g.dy),
        });
      },
    })
  ).current;

  if (!stats) return null;

  const fpsColor = (fps: number): string => {
    if (fps >= 55) return '#00FF66';
    if (fps >= 30) return '#FFB74D';
    return '#FF5252';
  };

  const fmt = (n: number, decimals: number = 0): string => {
    return n.toLocaleString(undefined, { maximumFractionDigits: decimals, minimumFractionDigits: 0 });
  };

  return (
    <View
      style={[styles.container, { left: position.x, top: position.y }]}
      pointerEvents="box-none"
    >
      <View style={styles.panel} {...panResponder.panHandlers}>
        <View style={styles.header}>
          <Text style={[styles.fps, { color: fpsColor(stats.fps) }]}>
            {fmt(stats.fps)} FPS
          </Text>
          <Text style={styles.frameTime}>
            {fmt(stats.frameTimeMs, 1)}ms
          </Text>
          <TouchableOpacity
            style={styles.collapseBtn}
            onPress={() => setCollapsed(!collapsed)}
            hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
          >
            <Text style={styles.collapseBtnText}>{collapsed ? 'v' : '^'}</Text>
          </TouchableOpacity>
        </View>

        {!collapsed && (
          <View style={styles.body}>
            <Section title="Frame">
              <Row label="Frame #" value={fmt(stats.frameNumber)} />
              <Row label="Render" value={`${fmt(stats.renderTimeMs, 2)}ms`} />
              <Row label="Animation" value={`${fmt(stats.animationTimeMs, 2)}ms`} />
              <Row label="Avg" value={`${fmt(rolling?.frameTimeAvgMs ?? 0, 2)}ms`} />
              <Row label="Min/Max" value={`${fmt(rolling?.frameTimeMinMs ?? 0, 1)}/${fmt(rolling?.frameTimeMaxMs ?? 0, 1)}ms`} />
            </Section>

            <Section title="GPU">
              <Row label="Draw calls" value={fmt(stats.drawCalls)} />
              <Row label="Triangles" value={fmt(stats.triangles)} />
              <Row label="Geometries" value={fmt(stats.geometries)} />
              <Row label="Textures" value={fmt(stats.textures)} />
              <Row label="Programs" value={fmt(stats.programs)} />
              <Row label="GPU mem" value={`${fmt(stats.estimatedGpuMemoryMB, 1)} MB`} />
            </Section>

            <Section title="Memory">
              <Row label="JS heap" value={`${fmt(stats.jsHeapUsedMB, 1)} / ${fmt(stats.jsHeapTotalMB, 1)} MB`} />
            </Section>

            {props.cameraController && (
              <Section title="Camera">
                <Row label="Yaw" value={`${((props.cameraController.getState().yaw * 180) / Math.PI).toFixed(0)}deg`} />
                <Row label="Pitch" value={`${((props.cameraController.getState().pitch * 180) / Math.PI).toFixed(0)}deg`} />
                <Row label="Distance" value={props.cameraController.getState().distance.toFixed(2)} />
              </Section>
            )}

            {props.lodSystem && (
              <Section title="LOD">
                {(() => {
                  const lodStats = props.lodSystem!.getStats();
                  return (
                    <>
                      <Row label="Groups" value={fmt(lodStats.groupCount)} />
                      <Row label="Variants" value={fmt(lodStats.totalVariants)} />
                      <Row label="Swaps" value={fmt(lodStats.swapsTotal)} />
                      <Row label="High" value={fmt(lodStats.histogram.high)} />
                      <Row label="Med" value={fmt(lodStats.histogram.medium)} />
                      <Row label="Low" value={fmt(lodStats.histogram.low)} />
                    </>
                  );
                })()}
              </Section>
            )}

            {props.materialSystem && (
              <Section title="Materials">
                {(() => {
                  const m = props.materialSystem!.getStats();
                  return (
                    <>
                      <Row label="Instances" value={fmt(m.materials.count)} />
                      <Row label="Refs" value={fmt(m.materials.totalRefs)} />
                      <Row label="Hits/Miss" value={`${m.materials.hits}/${m.materials.misses}`} />
                      <Row label="Tex bytes" value={`${fmt(m.textures.bytes / 1024 / 1024, 1)} MB`} />
                      <Row label="Tex count" value={fmt(m.textures.count)} />
                    </>
                  );
                })()}
              </Section>
            )}

            {props.assetManager && (
              <Section title="Loads">
                {(() => {
                  const loads = props.assetManager!.getActiveLoads();
                  if (loads.length === 0) return <Row label="Active" value="0" />;
                  return loads.map((load) => (
                    <Row
                      key={load.descriptor.id}
                      label={load.descriptor.id.slice(0, 14)}
                      value={`${load.phase} ${(load.overallProgress * 100).toFixed(0)}%`}
                    />
                  ));
                })()}
              </Section>
            )}
          </View>
        )}
      </View>
    </View>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle}>{title}</Text>
      {children}
    </View>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.row}>
      <Text style={styles.rowLabel}>{label}</Text>
      <Text style={styles.rowValue}>{value}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { position: 'absolute', zIndex: 100, minWidth: 180 },
  panel: {
    backgroundColor: 'rgba(0, 0, 0, 0.85)',
    borderRadius: 8,
    borderWidth: 1,
    borderColor: 'rgba(108, 99, 255, 0.4)',
    padding: 8,
  },
  header: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  fps: { fontSize: 16, fontWeight: '700', fontFamily: 'monospace' },
  frameTime: { color: '#AAA', fontSize: 12, fontFamily: 'monospace', flex: 1 },
  collapseBtn: { paddingHorizontal: 6, paddingVertical: 2 },
  collapseBtnText: { color: '#FFF', fontSize: 14 },
  body: { marginTop: 6, gap: 8 },
  section: { borderTopWidth: 1, borderTopColor: 'rgba(255,255,255,0.1)', paddingTop: 4 },
  sectionTitle: {
    color: '#6C63FF', fontSize: 10, fontWeight: '700',
    textTransform: 'uppercase', marginBottom: 2,
  },
  row: { flexDirection: 'row', justifyContent: 'space-between' },
  rowLabel: { color: '#BBB', fontSize: 11, fontFamily: 'monospace' },
  rowValue: { color: '#FFF', fontSize: 11, fontFamily: 'monospace', fontWeight: '600' },
});
