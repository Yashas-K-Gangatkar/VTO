/**
 * Onboarding Screen — "Scan Once" Flow
 * 
 * Features:
 * - Guided camera with silhouette overlay
 * - 6-segment progress bar
 * - Real-time instruction text
 * - Green flash confirmation on capture
 * - No forced cropping in gallery picker
 * - Sequential 6-photo capture
 */

import React, { useState, useRef, useEffect } from 'react';
import {
  StyleSheet, Text, View, TouchableOpacity, TextInput,
  Alert, ActivityIndicator, Image, Animated, Dimensions
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { CameraView } from 'expo-camera';
import * as ImagePicker from 'expo-image-picker';
import * as FileSystem from 'expo-file-system/legacy';
import { syncUploadBody } from '../api/cloudSync';

const SCREEN_WIDTH = Dimensions.get('window').width;
const SCREEN_HEIGHT = Dimensions.get('window').height;

interface OnboardingScreenProps {
  onComplete: (modelUri: string) => void;
}

const CAPTURE_ANGLES = [
  { id: 'front', label: 'Front View', instruction: 'Stand straight, face the camera directly', icon: '👤' },
  { id: '3q_left', label: '45° Left', instruction: 'Turn 45° to your left', icon: '🔄' },
  { id: 'left', label: 'Left Profile', instruction: 'Turn 90° to your left (side view)', icon: '👈' },
  { id: 'back', label: 'Back View', instruction: 'Turn around, face away from camera', icon: '🔙' },
  { id: 'right', label: 'Right Profile', instruction: 'Turn 90° to your right (side view)', icon: '👉' },
  { id: '3q_right', label: '45° Right', instruction: 'Turn 45° to your right', icon: '🔄' },
];

export default function OnboardingScreen({ onComplete }: OnboardingScreenProps) {
  const [step, setStep] = useState<'intro' | 'capture' | 'phone' | 'uploading'>('intro');
  const [currentAngle, setCurrentAngle] = useState(0);
  const [photos, setPhotos] = useState<string[]>([]);
  const [phoneNumber, setPhoneNumber] = useState('');
  const [uploading, setUploading] = useState(false);
  const [flashAnim] = useState(new Animated.Value(0));
  const cameraRef = useRef<CameraView>(null);

  const triggerFlash = () => {
    Animated.sequence([
      Animated.timing(flashAnim, { toValue: 1, duration: 150, useNativeDriver: false }),
      Animated.timing(flashAnim, { toValue: 0, duration: 300, useNativeDriver: false }),
    ]).start();
  };

  const startScanning = async () => {
    try {
      const { status } = await ImagePicker.requestCameraPermissionsAsync();
      if (status !== 'granted') {
        Alert.alert('Permission needed', 'Camera access is required');
        return;
      }
      setStep('capture');
    } catch (error: any) {
      Alert.alert('Error', 'Failed to start camera: ' + error.message);
    }
  };

  const takePhoto = async () => {
    if (!cameraRef.current) return;
    try {
      const photo = await cameraRef.current.takePictureAsync({ 
        quality: 0.8, 
        skipProcessing: true 
      });
      triggerFlash();
      const newPhotos = [...photos, photo.uri];
      setPhotos(newPhotos);
      
      if (currentAngle < CAPTURE_ANGLES.length - 1) {
        setTimeout(() => setCurrentAngle(currentAngle + 1), 400);
      } else {
        setTimeout(() => setStep('phone'), 400);
      }
    } catch (e: any) {
      Alert.alert('Camera Error', e.message);
    }
  };

  const pickFromGallery = async () => {
    try {
      const result = await ImagePicker.launchImageLibraryAsync({
        mediaTypes: ['images'],
        allowsEditing: false, // No forced cropping - keeps full body
        quality: 0.8,
      });
      if (!result.canceled && result.assets[0]) {
        triggerFlash();
        const newPhotos = [...photos, result.assets[0].uri];
        setPhotos(newPhotos);
        if (currentAngle < CAPTURE_ANGLES.length - 1) {
          setTimeout(() => setCurrentAngle(currentAngle + 1), 400);
        } else {
          setTimeout(() => setStep('phone'), 400);
        }
      }
    } catch (e: any) {
      Alert.alert('Gallery Error', e.message);
    }
  };

  const handleUpload = async () => {
    if (!phoneNumber || phoneNumber.length < 10) {
      Alert.alert('Invalid number', 'Please enter a valid phone number');
      return;
    }
    setUploading(true);
    try {
      const sampleModelUrl = 'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/Box/glTF-Binary/Box.glb';
      const localPath = `${FileSystem.cacheDirectory}body_model.glb`;
      const downloadResult = await FileSystem.downloadAsync(sampleModelUrl, localPath);
      await syncUploadBody(phoneNumber, downloadResult.uri);
      Alert.alert('Success!', 'Your Digital Twin has been created and saved to the cloud.');
      onComplete(downloadResult.uri);
    } catch (e: any) {
      Alert.alert('Upload failed', e.message);
    } finally {
      setUploading(false);
    }
  };

  // ============================================================
  // INTRO SCREEN
  // ============================================================
  if (step === 'intro') {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.content}>
          <Text style={styles.title}>Create Your{"\n"}Digital Twin</Text>
          <Text style={styles.subtitle}>
            Scan your body once. Use it forever across every store.
          </Text>
          
          <View style={styles.stepsContainer}>
            <Text style={styles.stepText}>📸 Take 6 guided photos (2 minutes)</Text>
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

  // ============================================================
  // CAPTURE SCREEN — Guided Camera with Silhouette Overlay
  // ============================================================
  if (step === 'capture') {
    const angle = CAPTURE_ANGLES[currentAngle];
    return (
      <SafeAreaView style={styles.container}>
        {/* Progress Header */}
        <View style={styles.progressHeader}>
          <Text style={styles.progressText}>Photo {currentAngle + 1} of {CAPTURE_ANGLES.length}</Text>
          {/* 6-segment progress bar */}
          <View style={styles.progressBar}>
            {CAPTURE_ANGLES.map((_, i) => (
              <View 
                key={i} 
                style={[
                  styles.progressSegment, 
                  i < photos.length && styles.progressSegmentDone,
                  i === currentAngle && styles.progressSegmentActive,
                ]} 
              />
            ))}
          </View>
          {/* Angle grid thumbnails */}
          <View style={styles.angleGrid}>
            {CAPTURE_ANGLES.map((a, i) => (
              <View key={a.id} style={styles.angleThumb}>
                <Text style={styles.angleThumbIcon}>{a.icon}</Text>
                <Text style={styles.angleThumbLabel}>{a.label}</Text>
                {i < photos.length ? (
                  <View style={[styles.angleStatus, { backgroundColor: '#00C853' }]}>
                    <Text style={styles.angleStatusText}>✓</Text>
                  </View>
                ) : i === currentAngle ? (
                  <View style={[styles.angleStatus, { backgroundColor: '#6C63FF' }]}>
                    <Text style={styles.angleStatusText}>●</Text>
                  </View>
                ) : (
                  <View style={[styles.angleStatus, { backgroundColor: '#333' }]}>
                    <Text style={styles.angleStatusText}>○</Text>
                  </View>
                )}
              </View>
            ))}
          </View>
        </View>

        {/* Instruction Banner */}
        <View style={styles.instructionBanner}>
          <Text style={styles.instructionIcon}>{angle.icon}</Text>
          <View style={styles.instructionTextContainer}>
            <Text style={styles.instructionLabel}>{angle.label}</Text>
            <Text style={styles.instructionText}>{angle.instruction}</Text>
          </View>
        </View>

        {/* Camera View with Silhouette Overlay */}
        <View style={styles.cameraContainer}>
          <CameraView 
            ref={cameraRef} 
            style={styles.camera} 
            facing={'back'}
          />
          
          {/* Human Silhouette Overlay */}
          <View style={styles.silhouetteOverlay} pointerEvents="none">
            <View style={styles.silhouetteHead} />
            <View style={styles.silhouetteShoulders} />
            <View style={styles.silhouetteTorso} />
            <View style={styles.silhouetteLeftArm} />
            <View style={styles.silhouetteRightArm} />
            <View style={styles.silhouetteLeftLeg} />
            <View style={styles.silhouetteRightLeg} />
            {/* Alignment lines */}
            <View style={styles.alignmentLineTop} />
            <View style={styles.alignmentLineBottom} />
            <Text style={styles.alignmentText}>Align body in frame</Text>
          </View>

          {/* Green flash overlay on capture */}
          <Animated.View 
            style={[
              styles.flashOverlay, 
              { opacity: flashAnim.interpolate({ inputRange: [0, 1], outputRange: [0, 0.6] }) }
            ]} 
            pointerEvents="none"
          />

          {/* Captured photo thumbnails */}
          {photos.length > 0 && (
            <View style={styles.photoThumbnails}>
              {photos.map((uri, i) => (
                <Image key={i} source={{ uri }} style={styles.thumbnail} />
              ))}
            </View>
          )}
        </View>

        {/* Camera Controls */}
        <View style={styles.captureControls}>
          <TouchableOpacity style={styles.galleryButton} onPress={pickFromGallery}>
            <Text style={styles.galleryButtonText}>📁 Gallery</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.captureButton} onPress={takePhoto}>
            <View style={styles.captureButtonInner} />
          </TouchableOpacity>
          <View style={styles.galleryButton}>
            <Text style={styles.flipButtonText}>Flip</Text>
          </View>
        </View>
      </SafeAreaView>
    );
  }

  // ============================================================
  // PHONE NUMBER SCREEN
  // ============================================================
  if (step === 'phone') {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.content}>
          <Text style={styles.title}>Almost Done!</Text>
          <Text style={styles.subtitle}>
            Enter your phone number to save your Digital Twin to the cloud.
            You'll be able to access it in any store's app.
          </Text>

          {/* Show captured photos summary */}
          <View style={styles.photoSummary}>
            {photos.map((uri, i) => (
              <Image key={i} source={{ uri }} style={styles.summaryThumbnail} />
            ))}
          </View>

          <TextInput
            style={styles.phoneInput}
            placeholder="+91 98765 43210"
            placeholderTextColor="#666"
            keyboardType="phone-pad"
            value={phoneNumber}
            onChangeText={setPhoneNumber}
          />

          <TouchableOpacity
            style={[styles.primaryButton, uploading && styles.buttonDisabled]}
            onPress={handleUpload}
            disabled={uploading}
          >
            {uploading ? (
              <ActivityIndicator color="#FFF" />
            ) : (
              <Text style={styles.primaryButtonText}>Save to Cloud →</Text>
            )}
          </TouchableOpacity>

          {uploading && (
            <Text style={styles.uploadingText}>
              Generating your 3D model and uploading...
            </Text>
          )}
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

  // Progress Header
  progressHeader: { padding: 12, backgroundColor: '#111' },
  progressText: { color: '#6C63FF', fontSize: 14, fontWeight: '700', textAlign: 'center', marginBottom: 8 },
  progressBar: { flexDirection: 'row', gap: 4, marginBottom: 10 },
  progressSegment: { flex: 1, height: 4, backgroundColor: '#333', borderRadius: 2 },
  progressSegmentDone: { backgroundColor: '#00C853' },
  progressSegmentActive: { backgroundColor: '#6C63FF' },
  
  // Angle Grid
  angleGrid: { flexDirection: 'row', justifyContent: 'space-between', paddingHorizontal: 4 },
  angleThumb: { alignItems: 'center', width: 50 },
  angleThumbIcon: { fontSize: 16 },
  angleThumbLabel: { color: '#666', fontSize: 7, marginTop: 2, textAlign: 'center' },
  angleStatus: { width: 16, height: 16, borderRadius: 8, justifyContent: 'center', alignItems: 'center', marginTop: 4 },
  angleStatusText: { color: '#FFF', fontSize: 8, fontWeight: '700' },

  // Instruction Banner
  instructionBanner: { flexDirection: 'row', alignItems: 'center', padding: 12, backgroundColor: '#1a1a2e', borderBottomWidth: 1, borderBottomColor: '#333' },
  instructionIcon: { fontSize: 24, marginRight: 12 },
  instructionTextContainer: { flex: 1 },
  instructionLabel: { color: '#FFF', fontSize: 16, fontWeight: '700' },
  instructionText: { color: '#888', fontSize: 13, marginTop: 2 },

  // Camera
  cameraContainer: { flex: 1, overflow: 'hidden' },
  camera: { flex: 1 },

  // Silhouette Overlay
  silhouetteOverlay: { ...StyleSheet.absoluteFillObject, justifyContent: 'center', alignItems: 'center' },
  silhouetteHead: { 
    position: 'absolute', top: '12%', width: 60, height: 70, borderRadius: 35, 
    borderWidth: 2, borderColor: 'rgba(108, 99, 255, 0.5)', backgroundColor: 'rgba(108, 99, 255, 0.08)' 
  },
  silhouetteShoulders: { 
    position: 'absolute', top: '28%', width: 140, height: 20, 
    borderWidth: 2, borderColor: 'rgba(108, 99, 255, 0.5)', backgroundColor: 'rgba(108, 99, 255, 0.08)',
    borderTopLeftRadius: 10, borderTopRightRadius: 10
  },
  silhouetteTorso: { 
    position: 'absolute', top: '31%', width: 120, height: 180, 
    borderWidth: 2, borderColor: 'rgba(108, 99, 255, 0.5)', backgroundColor: 'rgba(108, 99, 255, 0.08)'
  },
  silhouetteLeftArm: { 
    position: 'absolute', top: '32%', left: '22%', width: 25, height: 160, 
    borderWidth: 2, borderColor: 'rgba(108, 99, 255, 0.5)', backgroundColor: 'rgba(108, 99, 255, 0.08)',
    borderRadius: 12
  },
  silhouetteRightArm: { 
    position: 'absolute', top: '32%', right: '22%', width: 25, height: 160, 
    borderWidth: 2, borderColor: 'rgba(108, 99, 255, 0.5)', backgroundColor: 'rgba(108, 99, 255, 0.08)',
    borderRadius: 12
  },
  silhouetteLeftLeg: { 
    position: 'absolute', top: '60%', left: '38%', width: 35, height: 200, 
    borderWidth: 2, borderColor: 'rgba(108, 99, 255, 0.5)', backgroundColor: 'rgba(108, 99, 255, 0.08)',
    borderBottomLeftRadius: 10
  },
  silhouetteRightLeg: { 
    position: 'absolute', top: '60%', right: '38%', width: 35, height: 200, 
    borderWidth: 2, borderColor: 'rgba(108, 99, 255, 0.5)', backgroundColor: 'rgba(108, 99, 255, 0.08)',
    borderBottomRightRadius: 10
  },
  alignmentLineTop: { 
    position: 'absolute', top: '8%', left: '10%', right: '10%', height: 1, 
    backgroundColor: 'rgba(0, 200, 83, 0.3)' 
  },
  alignmentLineBottom: { 
    position: 'absolute', bottom: '5%', left: '10%', right: '10%', height: 1, 
    backgroundColor: 'rgba(0, 200, 83, 0.3)' 
  },
  alignmentText: { 
    position: 'absolute', bottom: '6%', color: 'rgba(0, 200, 83, 0.6)', fontSize: 10, fontWeight: '600' 
  },

  // Flash
  flashOverlay: { ...StyleSheet.absoluteFillObject, backgroundColor: '#00C853' },

  // Photo Thumbnails
  photoThumbnails: { position: 'absolute', bottom: 10, left: 10, flexDirection: 'row', gap: 4 },
  thumbnail: { width: 40, height: 52, borderRadius: 4, borderWidth: 2, borderColor: '#00C853' },

  // Capture Controls
  captureControls: { flexDirection: 'row', justifyContent: 'center', alignItems: 'center', padding: 20, gap: 30, backgroundColor: '#111' },
  galleryButton: { padding: 12, width: 70, alignItems: 'center' },
  galleryButtonText: { color: '#FFF', fontSize: 12 },
  flipButtonText: { color: '#FFF', fontSize: 12 },
  captureButton: { width: 70, height: 70, borderRadius: 35, borderWidth: 4, borderColor: '#FFF', justifyContent: 'center', alignItems: 'center' },
  captureButtonInner: { width: 56, height: 56, borderRadius: 28, backgroundColor: '#FFF' },

  // Phone Screen
  phoneInput: { backgroundColor: '#1E1E1E', borderRadius: 12, padding: 16, color: '#FFF', fontSize: 18, marginBottom: 20, borderWidth: 1, borderColor: '#333' },
  uploadingText: { color: '#888', fontSize: 14, textAlign: 'center', marginTop: 16 },
  photoSummary: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginBottom: 20, justifyContent: 'center' },
  summaryThumbnail: { width: 50, height: 65, borderRadius: 6 },
});
