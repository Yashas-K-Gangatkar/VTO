/**
 * engine/__tests__/framework/TestHarness.ts
 */

import { Platform, PixelRatio, Dimensions } from 'react-native';
import type {
  TestContext, TestResult, AssertionResult, BenchmarkMetrics,
  DeviceInfo, MemorySample, TestCase,
} from './types';

const TAG = '[TestHarness]';

export class TestCollector {
  logs: string[] = [];
  assertions: AssertionResult[] = [];
  metrics: BenchmarkMetrics = {};
  timers = new Map<string, number>();

  addLog(msg: string): void {
    const line = `[${new Date().toISOString()}] ${msg}`;
    this.logs.push(line);
    console.log(TAG, msg);
  }

  addAssertion(a: AssertionResult): void {
    this.assertions.push(a);
    if (!a.passed) console.warn(TAG, `EXPECT FAIL: ${a.label}${a.expected ? ` (expected ${a.expected}, got ${a.actual})` : ''}`);
  }

  setMetric<K extends keyof BenchmarkMetrics>(key: K, value: BenchmarkMetrics[K]): void {
    this.metrics[key] = value;
  }

  startTimer(name: string): () => number {
    this.timers.set(name, performance.now());
    return () => {
      const start = this.timers.get(name);
      if (start === undefined) return 0;
      const elapsed = performance.now() - start;
      this.timers.delete(name);
      this.metrics.custom = this.metrics.custom ?? {};
      this.metrics.custom[`timer_${name}_ms`] = Math.round(elapsed * 100) / 100;
      return elapsed;
    };
  }
}

export function createTestContext(): { ctx: TestContext; collector: TestCollector } {
  const collector = new TestCollector();
  const ctx: TestContext = {
    log: (msg: string) => collector.addLog(msg),
    expect: (label: string, condition: boolean, expected?: string, actual?: string) => {
      collector.addAssertion({ label, passed: condition, expected, actual });
    },
    startTimer: (name: string) => collector.startTimer(name),
    getDeviceInfo,
    sampleMemory: (): MemorySample => {
      // @ts-ignore
      const mem = (typeof performance !== 'undefined' && (performance as any).memory)
        // @ts-ignore
        ? (performance as any).memory
        : null;
      return {
        jsHeapUsedMB: mem ? mem.usedJSHeapSize / (1024 * 1024) : 0,
        jsHeapTotalMB: mem ? mem.totalJSHeapSize / (1024 * 1024) : 0,
        timestamp: Date.now(),
      };
    },
  };
  return { ctx, collector };
}

export function buildResult(
  testCase: TestCase, collector: TestCollector, startMs: number,
  deviceInfo: DeviceInfo, error?: string,
): TestResult {
  const allPassed = collector.assertions.every((a) => a.passed);
  const status: TestResult['status'] = error ? 'fail' : (allPassed ? 'pass' : 'fail');
  return {
    id: testCase.id, name: testCase.name, subsystem: testCase.subsystem,
    status, durationMs: Math.round(performance.now() - startMs),
    timestamp: Date.now(), assertions: [...collector.assertions],
    metrics: { ...collector.metrics }, error, deviceInfo, logs: [...collector.logs],
  };
}

export async function runTest(testCase: TestCase): Promise<TestResult> {
  if (testCase.skipReason) {
    return {
      id: testCase.id, name: testCase.name, subsystem: testCase.subsystem,
      status: 'skipped', durationMs: 0, timestamp: Date.now(),
      assertions: [], metrics: {}, deviceInfo: await getDeviceInfo(),
      logs: [`SKIPPED: ${testCase.skipReason}`],
    };
  }

  const { ctx, collector } = createTestContext();
  const startMs = performance.now();
  ctx.log(`> starting test: ${testCase.id}`);

  try {
    await testCase.run(ctx);
    const deviceInfo = await getDeviceInfo();
    const result = buildResult(testCase, collector, startMs, deviceInfo);
    ctx.log(`= finished: ${result.status} (${result.durationMs}ms, ${result.assertions.length} assertions)`);
    return result;
  } catch (e: any) {
    const deviceInfo = await getDeviceInfo();
    const errMsg = e?.message || String(e) || 'Unknown error';
    ctx.log(`x threw: ${errMsg}`);
    return buildResult(testCase, collector, startMs, deviceInfo, errMsg);
  }
}

export async function getDeviceInfo(): Promise<DeviceInfo> {
  let expoSdkVersion = 'unknown';
  try {
    const Constants = require('expo-constants');
    expoSdkVersion = Constants?.default?.expoConfig?.sdkVersion ?? Constants?.expoConfig?.sdkVersion ?? 'unknown';
  } catch { /* not installed */ }

  const info: DeviceInfo = {
    platform: Platform.OS as 'android' | 'ios',
    osVersion: Platform.Version?.toString() ?? 'unknown',
    expoSdkVersion,
    reactNativeVersion: getRNVersion(),
    devicePixelRatio: PixelRatio.get(),
    screenDimensions: { width: Dimensions.get('window').width, height: Dimensions.get('window').height },
  };

  if (Platform.OS === 'android') {
    info.manufacturer = (Platform as any).constants?.Manufacturer;
    info.model = (Platform as any).constants?.Model;
  }
  return info;
}

function getRNVersion(): string {
  try {
    const v = (Platform as any).constants?.reactNativeVersion;
    if (v) return `${v.major}.${v.minor}.${v.patch}`;
  } catch { /* ignore */ }
  return 'unknown';
}
