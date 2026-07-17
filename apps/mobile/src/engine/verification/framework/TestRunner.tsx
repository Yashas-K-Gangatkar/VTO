/**
 * engine/__tests__/framework/TestRunner.tsx
 *
 * On-device UI for running tests and viewing results.
 */

import React, { useState, useRef, useCallback } from 'react';
import {
  View, Text, TouchableOpacity, StyleSheet, ScrollView,
  ActivityIndicator, Share, Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import type { TestResult, TestReport, SubsystemName } from './types';
import { runTest } from './TestHarness';
import { buildReport, renderReport, reportToJson } from './TestReport';
import { getAllTests, getTestsBySubsystem, listSubsystems } from './TestRegistry';

const TAG = '[TestRunner]';

const STATUS_ICON: Record<TestResult['status'], string> = {
  pass: 'OK', fail: 'XX', skipped: 'SKIP', running: '...', pending: '-',
};

const STATUS_COLOR: Record<TestResult['status'], string> = {
  pass: '#00FF66', fail: '#FF5252', skipped: '#888', running: '#FFB74D', pending: '#666',
};

export function TestRunnerScreen() {
  const [results, setResults] = useState<Map<string, TestResult>>(new Map());
  const [running, setRunning] = useState<Set<string>>(new Set());
  const [report, setReport] = useState<TestReport | null>(null);
  const [liveLog, setLiveLog] = useState<string[]>([]);
  const scrollRef = useRef<ScrollView>(null);

  const allTests = getAllTests();
  const subsystems = listSubsystems();

  const updateResult = useCallback((id: string, result: TestResult) => {
    setResults((prev) => {
      const next = new Map(prev);
      next.set(id, result);
      return next;
    });
    setRunning((prev) => {
      const next = new Set(prev);
      next.delete(id);
      return next;
    });
  }, []);

  const runSingleTest = useCallback(async (testId: string) => {
    const test = allTests.find((t) => t.id === testId);
    if (!test) return;
    setRunning((prev) => new Set(prev).add(testId));
    setLiveLog((prev) => [...prev, `\n=== ${test.id} ===`]);

    const origLog = console.log;
    console.log = (...args: any[]) => {
      const msg = args.map((a) => typeof a === 'string' ? a : JSON.stringify(a)).join(' ');
      if (msg.includes(test.id) || msg.includes('[TestHarness]')) {
        setLiveLog((prev) => [...prev, msg]);
      }
      origLog.apply(console, args as any);
    };

    try {
      const result = await runTest(test);
      updateResult(testId, result);
      setLiveLog((prev) => [...prev, `${STATUS_ICON[result.status]} ${test.id}: ${result.status} (${result.durationMs}ms)`]);
    } finally {
      console.log = origLog;
    }
  }, [allTests, updateResult]);

  const runSubsystem = useCallback(async (subsystem: SubsystemName) => {
    const tests = getTestsBySubsystem(subsystem);
    for (const t of tests) await runSingleTest(t.id);
  }, [runSingleTest]);

  const runAll = useCallback(async () => {
    setReport(null);
    setLiveLog([]);
    for (const t of allTests) await runSingleTest(t.id);
    setResults((prevResults) => {
      const allResults = Array.from(prevResults.values());
      const r = buildReport(allResults);
      setReport(r);
      return prevResults;
    });
  }, [allTests, runSingleTest]);

  const shareReport = useCallback(async () => {
    if (!report) return;
    const text = renderReport(report);
    try { await Share.share({ message: text, title: 'VTO Engine Benchmark Report' }); }
    catch (e) { console.warn(TAG, 'share failed:', e); }
  }, [report]);

  const copyReportJson = useCallback(() => {
    if (!report) return;
    const json = reportToJson(report);
    if (Platform.OS === 'web') {
      navigator.clipboard?.writeText(json);
    } else {
      const Clipboard = require('expo-clipboard');
      Clipboard?.default?.setStringAsync?.(json) ?? Clipboard?.setStringAsync?.(json);
    }
    setLiveLog((prev) => [...prev, 'Report JSON copied to clipboard']);
  }, [report]);

  const passedCount = Array.from(results.values()).filter((r) => r.status === 'pass').length;
  const failedCount = Array.from(results.values()).filter((r) => r.status === 'fail').length;
  const totalCount = allTests.length;

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>Engine Verification</Text>
        <View style={styles.summaryRow}>
          <Text style={styles.summaryText}>
            <Text style={{ color: '#00FF66' }}>{passedCount} OK</Text>
            {'  '}
            <Text style={{ color: '#FF5252' }}>{failedCount} XX</Text>
            {'  '}
            <Text style={{ color: '#888' }}>{totalCount - passedCount - failedCount} -</Text>
            {'  /  '}
            {totalCount} total
          </Text>
        </View>
      </View>

      <View style={styles.actionRow}>
        <TouchableOpacity
          style={[styles.button, styles.primaryButton, running.size > 0 && styles.buttonDisabled]}
          onPress={runAll}
          disabled={running.size > 0}
        >
          <Text style={styles.buttonText}>Run All Tests</Text>
        </TouchableOpacity>
        <TouchableOpacity style={[styles.button, !report && styles.buttonDisabled]} onPress={shareReport} disabled={!report}>
          <Text style={styles.buttonText}>Share Report</Text>
        </TouchableOpacity>
        <TouchableOpacity style={[styles.button, !report && styles.buttonDisabled]} onPress={copyReportJson} disabled={!report}>
          <Text style={styles.buttonText}>Copy JSON</Text>
        </TouchableOpacity>
      </View>

      <ScrollView style={styles.testList}>
        {subsystems.map((subsystem) => {
          const tests = getTestsBySubsystem(subsystem);
          const subPassed = tests.filter((t) => results.get(t.id)?.status === 'pass').length;
          const subFailed = tests.filter((t) => results.get(t.id)?.status === 'fail').length;
          return (
            <View key={subsystem} style={styles.subsystemSection}>
              <View style={styles.subsystemHeader}>
                <Text style={styles.subsystemTitle}>{subsystem}</Text>
                <Text style={styles.subsystemStats}>{subPassed} OK {subFailed} XX / {tests.length}</Text>
                <TouchableOpacity style={styles.subsystemRunBtn} onPress={() => runSubsystem(subsystem)} disabled={running.size > 0}>
                  <Text style={styles.subsystemRunText}>Run</Text>
                </TouchableOpacity>
              </View>
              {tests.map((test) => {
                const result = results.get(test.id);
                const isRunning = running.has(test.id);
                return (
                  <TouchableOpacity key={test.id} style={styles.testRow} onPress={() => runSingleTest(test.id)} disabled={isRunning}>
                    <Text style={[styles.testIcon, { color: STATUS_COLOR[result?.status ?? 'pending'] }]}>
                      {isRunning ? '...' : STATUS_ICON[result?.status ?? 'pending']}
                    </Text>
                    <View style={styles.testInfo}>
                      <Text style={styles.testName}>{test.name}</Text>
                      <Text style={styles.testId}>{test.id}</Text>
                      {result && (
                        <Text style={styles.testDuration}>
                          {result.durationMs}ms | {result.assertions.length} assertions
                          {result.metrics.custom && Object.keys(result.metrics.custom).length > 0 && (
                            <> | {Object.entries(result.metrics.custom).map(([k, v]) => `${k}=${v}`).join(', ')}</>
                          )}
                        </Text>
                      )}
                      {result?.error && <Text style={styles.testError}>! {result.error}</Text>}
                    </View>
                    {isRunning && <ActivityIndicator size="small" color="#6C63FF" />}
                  </TouchableOpacity>
                );
              })}
            </View>
          );
        })}
      </ScrollView>

      {liveLog.length > 0 && (
        <View style={styles.logPanel}>
          <View style={styles.logHeader}>
            <Text style={styles.logTitle}>Live Log ({liveLog.length} lines)</Text>
            <TouchableOpacity onPress={() => setLiveLog([])}>
              <Text style={styles.logClear}>Clear</Text>
            </TouchableOpacity>
          </View>
          <ScrollView
            ref={scrollRef}
            style={styles.logScroll}
            onContentSizeChange={(_, h) => scrollRef.current?.scrollTo({ y: h, animated: false })}
          >
            {liveLog.map((line, i) => <Text key={i} style={styles.logLine}>{line}</Text>)}
          </ScrollView>
        </View>
      )}

      {report && (
        <View style={styles.reportPanel}>
          <Text style={styles.reportTitle}>Benchmark Report</Text>
          <ScrollView style={styles.reportScroll}>
            <Text style={styles.reportText}>{renderReport(report)}</Text>
          </ScrollView>
        </View>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0F0F0F' },
  header: { padding: 16, borderBottomWidth: 1, borderBottomColor: '#222' },
  title: { color: '#FFF', fontSize: 22, fontWeight: '800' },
  summaryRow: { marginTop: 4 },
  summaryText: { color: '#CCC', fontSize: 14 },
  actionRow: { flexDirection: 'row', gap: 8, padding: 12, backgroundColor: '#111' },
  button: { flex: 1, paddingVertical: 10, paddingHorizontal: 12, backgroundColor: '#1E1E1E', borderRadius: 8, alignItems: 'center', borderWidth: 1, borderColor: '#333' },
  primaryButton: { backgroundColor: '#6C63FF', borderColor: '#6C63FF' },
  buttonText: { color: '#FFF', fontSize: 13, fontWeight: '600' },
  buttonDisabled: { backgroundColor: '#222', borderColor: '#222' },
  testList: { flex: 1, padding: 12 },
  subsystemSection: { marginBottom: 16 },
  subsystemHeader: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingVertical: 6, borderBottomWidth: 1, borderBottomColor: '#222' },
  subsystemTitle: { color: '#6C63FF', fontSize: 14, fontWeight: '700', flex: 1 },
  subsystemStats: { color: '#888', fontSize: 12 },
  subsystemRunBtn: { paddingHorizontal: 10, paddingVertical: 4, backgroundColor: '#1E1E1E', borderRadius: 6 },
  subsystemRunText: { color: '#6C63FF', fontSize: 11, fontWeight: '700' },
  testRow: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 8, paddingHorizontal: 8, backgroundColor: '#1a1a1a', borderRadius: 8, marginBottom: 4 },
  testIcon: { fontSize: 14, fontWeight: '700', width: 36, textAlign: 'center', fontFamily: 'monospace' },
  testInfo: { flex: 1 },
  testName: { color: '#FFF', fontSize: 13, fontWeight: '600' },
  testId: { color: '#666', fontSize: 10, fontFamily: 'monospace', marginTop: 1 },
  testDuration: { color: '#888', fontSize: 10, fontFamily: 'monospace', marginTop: 2 },
  testError: { color: '#FF5252', fontSize: 11, marginTop: 4 },
  logPanel: { height: 180, backgroundColor: '#000', borderTopWidth: 1, borderTopColor: '#222' },
  logHeader: { flexDirection: 'row', justifyContent: 'space-between', padding: 8, borderBottomWidth: 1, borderBottomColor: '#1a1a1a' },
  logTitle: { color: '#6C63FF', fontSize: 11, fontWeight: '700' },
  logClear: { color: '#FFB74D', fontSize: 11 },
  logScroll: { flex: 1, padding: 8 },
  logLine: { color: '#AAA', fontSize: 10, fontFamily: 'monospace', lineHeight: 14 },
  reportPanel: { height: 320, backgroundColor: '#000', borderTopWidth: 1, borderTopColor: '#6C63FF' },
  reportTitle: { color: '#6C63FF', fontSize: 12, fontWeight: '700', padding: 8 },
  reportScroll: { flex: 1, padding: 8 },
  reportText: { color: '#CCC', fontSize: 10, fontFamily: 'monospace', lineHeight: 14 },
});
