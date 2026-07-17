import React from 'react';
import { StatusBar } from 'expo-status-bar';
import { TestRunnerScreen } from './src/engine/verification/framework/TestRunner';

export default function App() {
  return (
    <>
      <StatusBar style="light" />
      <TestRunnerScreen />
    </>
  );
}
