/**
 * VTO App — Main Entry Point
 * 
 * Architecture: "Scan Once, Use Forever"
 * - New users go through OnboardingScreen (6 photos → 3D model → cloud upload)
 * - Returning users go to TryOnScreen (3D viewer + QR scanner + garment browsing)
 * - Cross-app sync: retrieve 3D model from cloud using phone number + OTP
 */

import React, { useState, useEffect } from 'react';
import { StatusBar } from 'expo-status-bar';
import * as FileSystem from 'expo-file-system';
import OnboardingScreen from './src/screens/OnboardingScreen';
import TryOnScreen from './src/screens/TryOnScreen';

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
    // Copy the model to persistent storage
    await FileSystem.copyAsync({ from: modelUri, to: BODY_MODEL_PATH });
    setBodyModelUri(BODY_MODEL_PATH);
    setHasBodyModel(true);
  };

  const handleReset = async () => {
    await FileSystem.deleteAsync(BODY_MODEL_PATH, { idempotent: true });
    setBodyModelUri(null);
    setHasBodyModel(false);
  };

  if (loading) {
    return null; // Splash screen placeholder
  }

  return (
    <>
      <StatusBar style="light" />
      {hasBodyModel ? (
        <TryOnScreen bodyModelUri={bodyModelUri} onReset={handleReset} />
      ) : (
        <OnboardingScreen onComplete={handleOnboardingComplete} />
      )}
    </>
  );
}
