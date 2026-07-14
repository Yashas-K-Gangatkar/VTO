/**
 * VTO App — Main Entry Point
 * 
 * Uses lazy loading to prevent expo-gl from crashing on startup.
 * TryOnScreen (which uses 3D) is only loaded when the user has a body model.
 */

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
