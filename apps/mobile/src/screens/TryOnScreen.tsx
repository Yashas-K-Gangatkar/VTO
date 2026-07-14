/**
 * Try-On Screen — The In-Store Experience
 */

import React, { useState, useEffect } from 'react';
import {
  StyleSheet, Text, View, TouchableOpacity, ScrollView,
  Alert, Modal, TextInput
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { CameraView } from 'expo-camera';
import ThreeDViewer from '../components/ThreeDViewer';
import { syncRequestOtp, syncRetrieveBody } from '../api/cloudSync';
import * as FileSystem from 'expo-file-system';

interface TryOnScreenProps {
  bodyModelUri: string | null;
  onReset: () => void;
}

const MOCK_GARMENTS = [
  { id: '1', name: 'Cotton T-Shirt', color: '#4A90D9', qr: 'VTO-GARMENT-001' },
  { id: '2', name: 'Denim Jacket', color: '#4A6FA5', qr: 'VTO-GARMENT-002' },
  { id: '3', name: 'Summer Dress', color: '#E91E63', qr: 'VTO-GARMENT-003' },
  { id: '4', name: 'Hoodie', color: '#4CAF50', qr: 'VTO-GARMENT-004' },
  { id: '5', name: 'Formal Shirt', color: '#FFF', qr: 'VTO-GARMENT-005' },
];

export default function TryOnScreen({ bodyModelUri, onReset }: TryOnScreenProps) {
  const [scannerOpen, setScannerOpen] = useState(false);
  const [hasPermission, setHasPermission] = useState<boolean | null>(null);
  const [syncModalOpen, setSyncModalOpen] = useState(false);
  const [phoneNumber, setPhoneNumber] = useState('');
  const [otp, setOtp] = useState('');
  const [syncing, setSyncing] = useState(false);

  useEffect(() => {
    (async () => {
      const { status } = await CameraView.requestCameraPermissionsAsync();
      setHasPermission(status === 'granted');
    })();
  }, []);

  const handleBarCodeScanned = ({ data }: { data: string }) => {
    setScannerOpen(false);
    Alert.alert('Garment Scanned!', `QR: ${data}\n\nLoading 3D garment...`);
  };

  const handleSyncRetrieve = async () => {
    if (!phoneNumber || !otp) { Alert.alert('Missing info', 'Please enter phone number and OTP'); return; }
    setSyncing(true);
    try {
      const result = await syncRetrieveBody(phoneNumber, otp);
      const localPath = `${FileSystem.cacheDirectory}body_model.glb`;
      await FileSystem.writeAsStringAsync(localPath, result.model_base64, { encoding: FileSystem.EncodingType.Base64 });
      setSyncModalOpen(false);
      Alert.alert('Success!', 'Your Digital Twin has been loaded from the cloud.');
    } catch (e: any) { Alert.alert('Sync failed', e.message); }
    finally { setSyncing(false); }
  };

  const handleRequestOtp = async () => {
    if (!phoneNumber) { Alert.alert('Enter number', 'Please enter your phone number first'); return; }
    try {
      const result = await syncRequestOtp(phoneNumber);
      if (result.mock_otp) Alert.alert('Demo OTP', `Your OTP is: ${result.mock_otp}`);
      else Alert.alert('OTP Sent', 'Check your phone for the OTP');
    } catch (e: any) { Alert.alert('Failed', e.message); }
  };

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Virtual Try-On</Text>
        <TouchableOpacity onPress={onReset}><Text style={styles.resetButton}>Reset</Text></TouchableOpacity>
      </View>
      <View style={styles.viewerSection}>
        <ThreeDViewer modelUri={bodyModelUri} autoRotate={true} />
        <View style={styles.viewerBadge}><Text style={styles.viewerBadgeText}>3D Digital Twin • $0.00 per render</Text></View>
      </View>
      <View style={styles.actionsRow}>
        <TouchableOpacity style={styles.scanButton} onPress={() => setScannerOpen(true)}><Text style={styles.scanButtonText}>📷 Scan QR</Text></TouchableOpacity>
        <TouchableOpacity style={styles.syncButton} onPress={() => setSyncModalOpen(true)}><Text style={styles.syncButtonText}>☁️ Sync from Cloud</Text></TouchableOpacity>
      </View>
      <Text style={styles.sectionTitle}>Browse Garments</Text>
      <ScrollView horizontal style={styles.garmentList} showsHorizontalScrollIndicator={false}>
        {MOCK_GARMENTS.map((garment) => (
          <TouchableOpacity key={garment.id} style={styles.garmentCard} onPress={() => Alert.alert('Try-On', `Loading ${garment.name} on 3D model...`)}>
            <View style={[styles.garmentImage, { backgroundColor: garment.color }]} />
            <Text style={styles.garmentName}>{garment.name}</Text>
          </TouchableOpacity>
        ))}
      </ScrollView>
      <Modal visible={scannerOpen} animationType="slide">
        <SafeAreaView style={styles.scannerContainer}>
          <Text style={styles.scannerTitle}>Scan Garment QR Code</Text>
          {hasPermission ? (
            <CameraView 
              style={styles.scanner} 
              onBarcodeScanned={scannerOpen ? handleBarCodeScanned : undefined}
              ratio="16:9"
            />
          ) : <Text style={styles.scannerError}>Camera permission required</Text>}
          <TouchableOpacity style={styles.closeButton} onPress={() => setScannerOpen(false)}><Text style={styles.closeButtonText}>Cancel</Text></TouchableOpacity>
        </SafeAreaView>
      </Modal>
      <Modal visible={syncModalOpen} animationType="slide" transparent={true}>
        <View style={styles.syncModalOverlay}>
          <View style={styles.syncModalContent}>
            <Text style={styles.syncTitle}>Retrieve Your Digital Twin</Text>
            <Text style={styles.syncSubtitle}>Enter your phone number to access your 3D body from any app.</Text>
            <TextInput style={styles.syncInput} placeholder="Phone Number (+91...)" placeholderTextColor="#666" keyboardType="phone-pad" value={phoneNumber} onChangeText={setPhoneNumber} />
            <TouchableOpacity style={styles.otpButton} onPress={handleRequestOtp}><Text style={styles.otpButtonText}>Request OTP</Text></TouchableOpacity>
            <TextInput style={styles.syncInput} placeholder="Enter OTP" placeholderTextColor="#666" keyboardType="number-pad" value={otp} onChangeText={setOtp} />
            <TouchableOpacity style={[styles.syncConfirmButton, syncing && styles.buttonDisabled]} onPress={handleSyncRetrieve} disabled={syncing}>
              <Text style={styles.syncConfirmText}>{syncing ? 'Syncing...' : 'Retrieve 3D Model'}</Text>
            </TouchableOpacity>
            <TouchableOpacity onPress={() => setSyncModalOpen(false)}><Text style={styles.cancelText}>Cancel</Text></TouchableOpacity>
          </View>
        </View>
      </Modal>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0F0F0F' },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', padding: 16 },
  headerTitle: { color: '#FFF', fontSize: 20, fontWeight: '700' },
  resetButton: { color: '#FF6B6B', fontSize: 14 },
  viewerSection: { flex: 1, margin: 16, borderRadius: 16, overflow: 'hidden' },
  viewerBadge: { position: 'absolute', bottom: 8, left: 8, backgroundColor: 'rgba(0,0,0,0.6)', paddingHorizontal: 8, paddingVertical: 4, borderRadius: 8 },
  viewerBadgeText: { color: '#00C853', fontSize: 10, fontWeight: '600' },
  actionsRow: { flexDirection: 'row', gap: 10, paddingHorizontal: 16, marginBottom: 16 },
  scanButton: { flex: 1, backgroundColor: '#6C63FF', borderRadius: 12, padding: 14, alignItems: 'center' },
  scanButtonText: { color: '#FFF', fontSize: 14, fontWeight: '600' },
  syncButton: { flex: 1, backgroundColor: '#1E1E1E', borderRadius: 12, padding: 14, alignItems: 'center', borderWidth: 1, borderColor: '#333' },
  syncButtonText: { color: '#FFF', fontSize: 14, fontWeight: '600' },
  sectionTitle: { color: '#FFF', fontSize: 16, fontWeight: '700', paddingHorizontal: 16, marginBottom: 10 },
  garmentList: { paddingLeft: 16, paddingBottom: 20 },
  garmentCard: { marginRight: 12, width: 100 },
  garmentImage: { width: 100, height: 120, borderRadius: 12, marginBottom: 6 },
  garmentName: { color: '#CCC', fontSize: 12, textAlign: 'center' },
  scannerContainer: { flex: 1, backgroundColor: '#0F0F0F', padding: 20 },
  scannerTitle: { color: '#FFF', fontSize: 20, fontWeight: '700', textAlign: 'center', marginBottom: 20 },
  scanner: { flex: 1, borderRadius: 16, overflow: 'hidden' },
  scannerError: { color: '#FF6B6B', textAlign: 'center', marginTop: 40 },
  closeButton: { marginTop: 20, padding: 16, alignItems: 'center' },
  closeButtonText: { color: '#6C63FF', fontSize: 16 },
  syncModalOverlay: { flex: 1, justifyContent: 'center', backgroundColor: 'rgba(0,0,0,0.8)', padding: 20 },
  syncModalContent: { backgroundColor: '#1E1E1E', borderRadius: 20, padding: 24 },
  syncTitle: { color: '#FFF', fontSize: 22, fontWeight: '700', textAlign: 'center', marginBottom: 8 },
  syncSubtitle: { color: '#888', fontSize: 14, textAlign: 'center', marginBottom: 24, lineHeight: 20 },
  syncInput: { backgroundColor: '#0F0F0F', borderRadius: 12, padding: 14, color: '#FFF', fontSize: 16, marginBottom: 12, borderWidth: 1, borderColor: '#333' },
  otpButton: { padding: 10, alignItems: 'center', marginBottom: 12 },
  otpButtonText: { color: '#6C63FF', fontSize: 14, fontWeight: '600' },
  syncConfirmButton: { backgroundColor: '#6C63FF', borderRadius: 12, padding: 16, alignItems: 'center', marginBottom: 12 },
  syncConfirmText: { color: '#FFF', fontSize: 16, fontWeight: '700' },
  buttonDisabled: { backgroundColor: '#333' },
  cancelText: { color: '#666', fontSize: 14, textAlign: 'center' },
});
