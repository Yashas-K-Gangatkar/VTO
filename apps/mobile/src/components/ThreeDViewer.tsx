/**
 * components/ThreeDViewer.tsx
 *
 * THIN WRAPPER around EngineViewer.
 * Preserves the existing ThreeDViewerProps API.
 */

import React from 'react';
import { EngineViewer, type EngineViewerProps } from '../engine';

export interface ThreeDViewerProps {
  modelUri: string | null;
  garmentUri?: string | null;
  autoRotate?: boolean;
  onReady?: () => void;
  debug?: boolean;
  modelVersion?: string | number;
  garmentVersion?: string | number;
}

export default function ThreeDViewer({
  modelUri,
  garmentUri,
  autoRotate: _autoRotate = true,
  onReady,
  debug = false,
  modelVersion = 1,
  garmentVersion = 1,
}: ThreeDViewerProps) {
  const engineViewerProps: EngineViewerProps = {
    bodyModelUri: modelUri,
    bodyModelVersion: modelVersion,
    garmentUri,
    garmentVersion,
    debug,
    onBodyReady: onReady,
    onGarmentReady: undefined,
    onError: (err) => console.error('[ThreeDViewer]', err),
  };
  return <EngineViewer {...engineViewerProps} />;
}
