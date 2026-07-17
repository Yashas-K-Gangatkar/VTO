/**
 * engine/__tests__/framework/TestReport.ts
 */

import type { TestResult, TestReport } from './types';

export function buildReport(results: TestResult[]): TestReport {
  const totalTests = results.length;
  const passed = results.filter((r) => r.status === 'pass').length;
  const failed = results.filter((r) => r.status === 'fail').length;
  const skipped = results.filter((r) => r.status === 'skipped').length;
  const totalDurationMs = results.reduce((sum, r) => sum + r.durationMs, 0);

  const deviceInfo = results[0]?.deviceInfo ?? {
    platform: 'unknown' as any, osVersion: 'unknown',
    expoSdkVersion: 'unknown', reactNativeVersion: 'unknown',
  };

  const bySubsystem: TestReport['bySubsystem'] = {};
  for (const r of results) {
    const s = r.subsystem;
    if (!bySubsystem[s]) bySubsystem[s] = { total: 0, passed: 0, failed: 0, skipped: 0 };
    bySubsystem[s].total += 1;
    if (r.status === 'pass') bySubsystem[s].passed += 1;
    else if (r.status === 'fail') bySubsystem[s].failed += 1;
    else if (r.status === 'skipped') bySubsystem[s].skipped += 1;
  }

  const findings: string[] = [];
  for (const r of results) {
    if (r.status === 'fail') {
      findings.push(`FAIL ${r.id}: ${r.error ?? 'assertions failed'}`);
      for (const a of r.assertions) {
        if (!a.passed) findings.push(`     - ${a.label}${a.expected ? ` (expected ${a.expected}, got ${a.actual})` : ''}`);
      }
    }
  }

  const notes: string[] = [];
  for (const r of results) {
    const m = r.metrics;
    if (m.loadTimeMs && m.loadTimeMs > 3000) notes.push(`WARN ${r.id}: loadTime=${m.loadTimeMs.toFixed(0)}ms (>3s, slow)`);
    if (m.frameTimeAvgMs && m.frameTimeAvgMs > 20) notes.push(`WARN ${r.id}: frameTime=${m.frameTimeAvgMs.toFixed(1)}ms (>20ms = <50fps)`);
    if (m.drawCalls && m.drawCalls > 100) notes.push(`WARN ${r.id}: drawCalls=${m.drawCalls} (>100, high)`);
    if (r.id.includes('meshoptimizer') && m.custom?.timer_optimize_ms) {
      const t = m.custom.timer_optimize_ms as number;
      if (t > 1000) notes.push(`CRIT ${r.id}: MeshOptimizer took ${t.toFixed(0)}ms - recommend removing from runtime path`);
      else if (t > 200) notes.push(`WARN ${r.id}: MeshOptimizer took ${t.toFixed(0)}ms - slow but tolerable`);
    }
    if (r.id.includes('textureloader') && m.custom?.timer_extract_ms) {
      notes.push(`INFO ${r.id}: texture extraction took ${(m.custom.timer_extract_ms as number).toFixed(0)}ms`);
    }
    if (m.cacheHits !== undefined && m.cacheMisses !== undefined) {
      const total = m.cacheHits + m.cacheMisses;
      if (total > 0) notes.push(`INFO ${r.id}: cache hit rate ${((m.cacheHits / total) * 100).toFixed(1)}% (${m.cacheHits}/${total})`);
    }
  }

  return {
    generatedAt: Date.now(), deviceInfo, totalTests, passed, failed, skipped,
    totalDurationMs, results, bySubsystem, findings, notes,
  };
}

export function renderReport(report: TestReport): string {
  const lines: string[] = [];
  lines.push('===============================================================');
  lines.push('  VTO ENGINE - VERIFICATION SPRINT BENCHMARK REPORT');
  lines.push('===============================================================');
  lines.push('');
  lines.push(`Generated: ${new Date(report.generatedAt).toISOString()}`);
  lines.push(`Device:    ${report.deviceInfo.manufacturer ?? ''} ${report.deviceInfo.model ?? ''}`.trim());
  lines.push(`Platform:  ${report.deviceInfo.platform} ${report.deviceInfo.osVersion}`);
  lines.push(`Expo SDK:  ${report.deviceInfo.expoSdkVersion}`);
  lines.push(`RN:        ${report.deviceInfo.reactNativeVersion}`);
  lines.push(`Screen:    ${report.deviceInfo.screenDimensions?.width}x${report.deviceInfo.screenDimensions?.height} @${report.deviceInfo.devicePixelRatio}x`);
  lines.push('');
  lines.push('- SUMMARY -----------------------------------------------------');
  lines.push(`  Total:  ${report.totalTests}`);
  lines.push(`  Pass:   ${report.passed}`);
  lines.push(`  Fail:   ${report.failed}`);
  lines.push(`  Skip:   ${report.skipped}`);
  lines.push(`  Time:   ${(report.totalDurationMs / 1000).toFixed(1)}s`);
  lines.push('');

  lines.push('- BY SUBSYSTEM ------------------------------------------------');
  const subsystemNames = Object.keys(report.bySubsystem).sort();
  for (const s of subsystemNames) {
    const stats = report.bySubsystem[s];
    const passRate = stats.total > 0 ? ((stats.passed / stats.total) * 100).toFixed(0) : '0';
    lines.push(`  ${s.padEnd(25)} ${stats.passed}/${stats.total} (${passRate}%)`);
  }
  lines.push('');

  if (report.findings.length > 0) {
    lines.push('- CRITICAL FINDINGS -------------------------------------------');
    for (const f of report.findings) lines.push(`  ${f}`);
    lines.push('');
  } else {
    lines.push('- CRITICAL FINDINGS -------------------------------------------');
    lines.push('  (none)');
    lines.push('');
  }

  if (report.notes.length > 0) {
    lines.push('- PERFORMANCE NOTES -------------------------------------------');
    for (const n of report.notes) lines.push(`  ${n}`);
    lines.push('');
  }

  lines.push('- PER-TEST DETAILS --------------------------------------------');
  for (const r of report.results) {
    const icon = r.status === 'pass' ? 'OK' : r.status === 'fail' ? 'XX' : 'SKIP';
    lines.push(`  [${icon}] ${r.id.padEnd(40)} ${r.durationMs.toString().padStart(6)}ms  [${r.subsystem}]`);
    if (r.metrics.custom) {
      for (const [k, v] of Object.entries(r.metrics.custom)) {
        lines.push(`       ${k}: ${v}`);
      }
    }
  }
  lines.push('');
  lines.push('===============================================================');
  return lines.join('\n');
}

export function reportToJson(report: TestReport): string {
  return JSON.stringify(report, null, 2);
}
