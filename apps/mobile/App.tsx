import React, { useState, useEffect } from 'react';
import {
  StyleSheet,
  Text,
  View,
  TouchableOpacity,
  Image,
  ScrollView,
  ActivityIndicator,
  Alert,
  StatusBar,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import * as ImagePicker from 'expo-image-picker';
import { tryOn, getStatus } from './src/api/client';

type Screen = 'home' | 'result';

export default function App() {
  const [screen, setScreen] = useState<Screen>('home');
  const [personPhoto, setPersonPhoto] = useState<string | null>(null);
  const [garmentPhoto, setGarmentPhoto] = useState<string | null>(null);
  const [resultImage, setResultImage] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [mode, setMode] = useState<string>('');

  useEffect(() => {
    getStatus().then(s => setMode(s.mode)).catch(() => setMode('offline'));
  }, []);

  const pickPersonPhoto = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      allowsEditing: true,
      aspect: [3, 4],
      quality: 0.8,
    });
    if (!result.canceled) {
      setPersonPhoto(result.assets[0].uri);
    }
  };

  const takePersonPhoto = async () => {
    const { status } = await ImagePicker.requestCameraPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert('Permission needed', 'Camera access is required');
      return;
    }
    const result = await ImagePicker.launchCameraAsync({
      allowsEditing: true,
      aspect: [3, 4],
      quality: 0.8,
    });
    if (!result.canceled) {
      setPersonPhoto(result.assets[0].uri);
    }
  };

  const pickGarmentPhoto = async () => {
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      allowsEditing: true,
      aspect: [3, 4],
      quality: 0.8,
    });
    if (!result.canceled) {
      setGarmentPhoto(result.assets[0].uri);
    }
  };

  const runTryOn = async () => {
    if (!personPhoto || !garmentPhoto) {
      Alert.alert('Missing photos', 'Please select both person and garment photos');
      return;
    }
    setLoading(true);
    setResultImage(null);
    try {
      const result = await tryOn(personPhoto, garmentPhoto);
      setResultImage(`data:image/png;base64,${result.image}`);
      setScreen('result');
    } catch (e: any) {
      Alert.alert('Error', e.message || 'Try-on failed');
    } finally {
      setLoading(false);
    }
  };

  // ============================================================
  // Home Screen
  // ============================================================
  if (screen === 'home') {
    return (
      <SafeAreaView style={styles.container}>
        <StatusBar barStyle="light-content" />
        <ScrollView contentContainerStyle={styles.scrollContent}>
          {/* Header */}
          <View style={styles.header}>
            <Text style={styles.title}>VTO</Text>
            <Text style={styles.subtitle}>Virtual Try-On</Text>
            <View style={[styles.badge, mode === 'real' ? styles.badgeReal : styles.badgeMock]}>
              <Text style={styles.badgeText}>{mode === 'real' ? 'GPU Active' : mode === 'mock' ? 'Demo Mode' : 'Offline'}</Text>
            </View>
          </View>

          {/* Person Photo */}
          <Text style={styles.sectionTitle}>1. Your Photo</Text>
          <View style={styles.photoRow}>
            <TouchableOpacity style={styles.photoButton} onPress={takePersonPhoto}>
              <Text style={styles.photoButtonText}>📷 Camera</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.photoButton} onPress={pickPersonPhoto}>
              <Text style={styles.photoButtonText}>🖼 Gallery</Text>
            </TouchableOpacity>
          </View>
          {personPhoto && (
            <Image source={{ uri: personPhoto }} style={styles.preview} resizeMode="contain" />
          )}

          {/* Garment Photo */}
          <Text style={styles.sectionTitle}>2. Garment</Text>
          <TouchableOpacity style={styles.photoButton} onPress={pickGarmentPhoto}>
            <Text style={styles.photoButtonText}>🖼 Select Garment</Text>
          </TouchableOpacity>
          {garmentPhoto && (
            <Image source={{ uri: garmentPhoto }} style={styles.preview} resizeMode="contain" />
          )}

          {/* Try-On Button */}
          <TouchableOpacity
            style={[styles.tryOnButton, (!personPhoto || !garmentPhoto || loading) && styles.tryOnButtonDisabled]}
            onPress={runTryOn}
            disabled={!personPhoto || !garmentPhoto || loading}
          >
            {loading ? (
              <ActivityIndicator color="#FFF" />
            ) : (
              <Text style={styles.tryOnButtonText}>Try It On →</Text>
            )}
          </TouchableOpacity>
        </ScrollView>
      </SafeAreaView>
    );
  }

  // ============================================================
  // Result Screen
  // ============================================================
  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" />
      <View style={styles.resultHeader}>
        <TouchableOpacity onPress={() => setScreen('home')}>
          <Text style={styles.backButton}>← Back</Text>
        </TouchableOpacity>
        <Text style={styles.resultTitle}>Try-On Result</Text>
      </View>
      {resultImage && (
        <Image
          source={{ uri: resultImage }}
          style={styles.resultImage}
          resizeMode="contain"
        />
      )}
      <TouchableOpacity
        style={styles.tryOnButton}
        onPress={() => setScreen('home')}
      >
        <Text style={styles.tryOnButtonText}>Try Another</Text>
      </TouchableOpacity>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0F0F0F',
  },
  scrollContent: {
    padding: 20,
  },
  header: {
    alignItems: 'center',
    marginBottom: 30,
    marginTop: 20,
  },
  title: {
    fontSize: 48,
    fontWeight: '900',
    color: '#FFF',
    letterSpacing: -2,
  },
  subtitle: {
    fontSize: 16,
    color: '#888',
    marginTop: 4,
  },
  badge: {
    marginTop: 12,
    paddingHorizontal: 12,
    paddingVertical: 4,
    borderRadius: 12,
  },
  badgeReal: {
    backgroundColor: '#00C853',
  },
  badgeMock: {
    backgroundColor: '#FF6B35',
  },
  badgeText: {
    color: '#FFF',
    fontSize: 12,
    fontWeight: '600',
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '700',
    color: '#FFF',
    marginBottom: 10,
  },
  photoRow: {
    flexDirection: 'row',
    gap: 10,
    marginBottom: 10,
  },
  photoButton: {
    flex: 1,
    backgroundColor: '#1E1E1E',
    borderRadius: 12,
    padding: 16,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#333',
  },
  photoButtonText: {
    color: '#FFF',
    fontSize: 16,
    fontWeight: '600',
  },
  preview: {
    width: '100%',
    height: 250,
    borderRadius: 12,
    marginBottom: 20,
    backgroundColor: '#1E1E1E',
  },
  tryOnButton: {
    backgroundColor: '#6C63FF',
    borderRadius: 16,
    padding: 18,
    alignItems: 'center',
    marginTop: 10,
  },
  tryOnButtonDisabled: {
    backgroundColor: '#333',
  },
  tryOnButtonText: {
    color: '#FFF',
    fontSize: 18,
    fontWeight: '700',
  },
  resultHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 20,
    gap: 20,
  },
  backButton: {
    color: '#6C63FF',
    fontSize: 16,
    fontWeight: '600',
  },
  resultTitle: {
    fontSize: 20,
    fontWeight: '700',
    color: '#FFF',
  },
  resultImage: {
    flex: 1,
    width: '100%',
  },
});
