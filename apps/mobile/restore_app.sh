#!/bin/bash
set -e
cd /Users/yashas/VTO/apps/mobile

echo "=== Restoring App.tsx to use the real 3D viewer ==="

cat > App.tsx << 'APPEOF'
import React, { useState, useEffect, Suspense } from 'react';
import { StatusBar } from 'expo-status-bar';
import { ActivityIndicator, View } from 'react-native';
import * as FileSystem from 'expo-file-system/legacy';
import OnboardingScreen from './src/screens/OnboardingScreen';

// Lazy load TryOnScreen to prevent expo-gl crash on startup
const TryOnScreen = React.lazy(() => import('./src/screens/TryOnScreen'));

const BODY_MODEL_PATH = `${FileSystem.documentDirectory}vto_body_model.glb`;

export default function App() {
  const [hasBodyModel, setHasBodyModel] = useState(false);
  const [bodyModelUri, setBodyModelUri] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    checkForExistingModel();
  }, []);

  const checkForExistingModel = async () => {
    try {
      const info = await FileSystem.getInfoAsync(BODY_MODEL_PATH);
      if (info.exists) {
        setBodyModelUri(BODY_MODEL_PATH);
        setHasBodyModel(true);
      }
    } catch (e) {
      console.log('No existing model found');
    } finally {
      setLoading(false);
    }
  };

  const handleOnboardingComplete = async (modelUri: string) => {
    try {
      await FileSystem.copyAsync({ from: modelUri, to: BODY_MODEL_PATH });
      setBodyModelUri(BODY_MODEL_PATH);
      setHasBodyModel(true);
    } catch (e) {
      console.error('Failed to save model:', e);
    }
  };

  const handleReset = async () => {
    try {
      await FileSystem.deleteAsync(BODY_MODEL_PATH, { idempotent: true });
    } catch (e) {
      console.error('Failed to delete model:', e);
    }
    setBodyModelUri(null);
    setHasBodyModel(false);
  };

  if (loading) {
    return (
      <View style={{ flex: 1, backgroundColor: '#0F0F0F', justifyContent: 'center', alignItems: 'center' }}>
        <ActivityIndicator size="large" color="#6C63FF" />
      </View>
    );
  }

  return (
    <>
      <StatusBar style="light" />
      {hasBodyModel ? (
        <Suspense fallback={<View style={{ flex: 1, backgroundColor: '#0F0F0F', justifyContent: 'center' }}><ActivityIndicator size="large" color="#6C63FF" /></View>}>
          <TryOnScreen bodyModelUri={bodyModelUri} onReset={handleReset} />
        </Suspense>
      ) : (
        <OnboardingScreen onComplete={handleOnboardingComplete} />
      )}
    </>
  );
}
APPEOF
echo "✓ App.tsx restored to real app"

echo ""
echo "=== Done ==="
echo ""
echo "Now run:"
echo "  rm -rf node_modules/.cache .metro-cache"
echo "  npx expo start --clear"
echo ""
echo "The app will open into the Onboarding screen."
echo "Tap 'Start Scanning' and complete the flow to see your 3D body model."
echo ""
echo "To enable the debug overlay (FPS, draw calls, etc.),"
echo "open src/components/ThreeDViewer.tsx and set debug={true} on the EngineViewer."
