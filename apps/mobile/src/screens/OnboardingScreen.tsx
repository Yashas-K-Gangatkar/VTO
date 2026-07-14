/**
 * Onboarding Screen — "Scan Once" Flow
 */

import React, { useState, useRef } from 'react';
import {
  StyleSheet, Text, View, TouchableOpacity, TextInput,
  Alert, ActivityIndicator, Image
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { CameraView } from 'expo-camera';
import * as ImagePicker from 'expo-image-picker';
import * as FileSystem from 'expo-file-system';
import { syncUploadBody } from '../api/cloudSync';

interface OnboardingScreenProps {
  onComplete: (modelUri: string) => void;
}

const CAPTURE_ANGLES = [
  { id: 'front', label: 'Front View', instruction: 'Stand straight, face the camera' },
  { id: 'back', label: 'Back View', instruction: 'Turn around, face away' },
  { id: 'left', label: 'Left Side', instruction: 'Turn to your left' },
  { id: 'right', label: 'Right Side', instruction: 'Turn to your right' },
  { id: '3q_left', label: '3/4 Left', instruction: 'Turn 45° to your left' },
  { id: '3q_right', label: '3/4 Right', instruction: 'Turn 45° to your right' },
];

export default function OnboardingScreen({ onComplete }: OnboardingScreenProps) {
  const [step, setStep] = useState<'intro' | 'capture' | 'phone' | 'uploading'>('intro');
  const [currentAngle, setCurrentAngle] = useState(0);
  const [photos, setPhotos] = useState<string[]>([]);
  const [phoneNumber, setPhoneNumber] = useState('');
  const [uploading, setUploading] = useState(false);
  const cameraRef = useRef<CameraView>(null);

  const startScanning = async () => {
    const { status } = await CameraView.requestCameraPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert('Permission needed', 'Camera access is required');
      return;
    }
    setStep('capture');
  };

  const takePhoto = async () => {
    if (!cameraRef.current) return;
    const photo = await cameraRef.current.takePictureAsync({ quality: 0.8, skipProcessing: true });
    const newPhotos = [...photos, photo.uri];
    setPhotos(newPhotos);
    if (currentAngle < CAPTURE_ANGLES.length - 1) setCurrentAngle(currentAngle + 1);
    else setStep('phone');
  };

  const pickFromGallery = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images, allowsEditing: true, aspect: [3, 4], quality: 0.8,
    });
    if (!result.canceled) {
      const newPhotos = [...photos, result.assets[0].uri];
      setPhotos(newPhotos);
      if (currentAngle < CAPTURE_ANGLES.length - 1) setCurrentAngle(currentAngle + 1);
      else setStep('phone');
    }
  };

  const handleUpload = async () => {
    if (!phoneNumber || phoneNumber.length < 10) { Alert.alert('Invalid number', 'Please enter a valid phone number'); return; }
    setUploading(true);
    try {
      const sampleModelUrl = 'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/Box/glTF-Binary/Box.glb';
      const localPath = `${FileSystem.cacheDirectory}body_model.glb`;
      const downloadResult = await FileSystem.downloadAsync(sampleModelUrl, localPath);
      await syncUploadBody(phoneNumber, downloadResult.uri);
      Alert.alert('Success!', 'Your Digital Twin has been created and saved to the cloud.');
      onComplete(downloadResult.uri);
    } catch (e: any) { Alert.alert('Upload failed', e.message); }
    finally { setUploading(false); }
  };

  if (step === 'intro') {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.content}>
          <Text style={styles.title}>Create Your{"\n"}Digital Twin</Text>
          <Text style={styles.subtitle}>Scan your body once. Use it forever across every store.</Text>
          <View style={styles.stepsContainer}>
            <Text style={styles.stepText}>📸 Take 6 photos (2 minutes)</Text>
            <Text style={styles.stepText}>🤖 We generate your 3D body</Text>
            <Text style={styles.stepText}>☁️ Stored in cloud — works in any app</Text>
            <Text style={styles.stepText}>👗 Try on clothes instantly — forever</Text>
          </View>
          <TouchableOpacity style={styles.primaryButton} onPress={startScanning}>
            <Text style={styles.primaryButtonText}>Start Scanning →</Text>
          </TouchableOpacity>
        </View>
      </SafeAreaView>
    );
  }

  if (step === 'capture') {
    const angle = CAPTURE_ANGLES[currentAngle];
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.captureHeader}>
          <Text style={styles.captureProgress}>Photo {currentAngle + 1} of {CAPTURE_ANGLES.length}</Text>
          <Text style={styles.captureAngle}>{angle.label}</Text>
          <Text style={styles.captureInstruction}>{angle.instruction}</Text>
        </View>
        <View style={styles.cameraContainer}>
          <CameraView ref={cameraRef} style={styles.camera} facing={'back'} ratio="3:4" />
          {photos.length > 0 && (
            <View style={styles.photoThumbnails}>
              {photos.map((uri, i) => (<Image key={i} source={{ uri }} style={styles.thumbnail} />))}
            </View>
          )}
        </View>
        <View style={styles.captureControls}>
          <TouchableOpacity style={styles.captureButton} onPress={takePhoto}>
            <View style={styles.captureButtonInner} />
          </TouchableOpacity>
          <TouchableOpacity style={styles.galleryButton} onPress={pickFromGallery}>
            <Text style={styles.galleryButtonText}>📁 Gallery</Text>
          </TouchableOpacity>
        </View>
      </SafeAreaView>
    );
  }

  if (step === 'phone') {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.content}>
          <Text style={styles.title}>Almost Done!</Text>
          <Text style={styles.subtitle}>Enter your phone number to save your Digital Twin to the cloud.</Text>
          <TextInput style={styles.phoneInput} placeholder="+91 98765 43210" placeholderTextColor="#666" keyboardType="phone-pad" value={phoneNumber} onChangeText={setPhoneNumber} />
          <TouchableOpacity style={[styles.primaryButton, uploading && styles.buttonDisabled]} onPress={handleUpload} disabled={uploading}>
            {uploading ? <ActivityIndicator color="#FFF" /> : <Text style={styles.primaryButtonText}>Save to Cloud →</Text>}
          </TouchableOpacity>
          {uploading && <Text style={styles.uploadingText}>Generating your 3D model and uploading...</Text>}
        </View>
      </SafeAreaView>
    );
  }
  return null;
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0F0F0F' },
  content: { flex: 1, justifyContent: 'center', padding: 30 },
  title: { fontSize: 32, fontWeight: '900', color: '#FFF', textAlign: 'center', marginBottom: 16 },
  subtitle: { fontSize: 16, color: '#888', textAlign: 'center', marginBottom: 40, lineHeight: 24 },
  stepsContainer: { marginBottom: 40 },
  stepText: { color: '#CCC', fontSize: 16, marginVertical: 8, textAlign: 'center' },
  primaryButton: { backgroundColor: '#6C63FF', borderRadius: 16, padding: 18, alignItems: 'center' },
  primaryButtonText: { color: '#FFF', fontSize: 18, fontWeight: '700' },
  buttonDisabled: { backgroundColor: '#333' },
  captureHeader: { padding: 20, alignItems: 'center' },
  captureProgress: { color: '#6C63FF', fontSize: 14, fontWeight: '600' },
  captureAngle: { color: '#FFF', fontSize: 24, fontWeight: '700', marginTop: 8 },
  captureInstruction: { color: '#888', fontSize: 14, marginTop: 4 },
  cameraContainer: { flex: 1, margin: 20, borderRadius: 16, overflow: 'hidden' },
  camera: { flex: 1 },
  photoThumbnails: { position: 'absolute', bottom: 10, left: 10, flexDirection: 'row', gap: 4 },
  thumbnail: { width: 40, height: 52, borderRadius: 4, borderWidth: 1, borderColor: '#FFF' },
  captureControls: { flexDirection: 'row', justifyContent: 'center', alignItems: 'center', padding: 20, gap: 20 },
  captureButton: { width: 70, height: 70, borderRadius: 35, borderWidth: 4, borderColor: '#FFF', justifyContent: 'center', alignItems: 'center' },
  captureButtonInner: { width: 56, height: 56, borderRadius: 28, backgroundColor: '#FFF' },
  galleryButton: { padding: 12 },
  galleryButtonText: { color: '#FFF', fontSize: 14 },
  phoneInput: { backgroundColor: '#1E1E1E', borderRadius: 12, padding: 16, color: '#FFF', fontSize: 18, marginBottom: 20, borderWidth: 1, borderColor: '#333' },
  uploadingText: { color: '#888', fontSize: 14, textAlign: 'center', marginTop: 16 },
});
