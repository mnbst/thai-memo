/**
 * genNotifyGolden.ts — notifyUtcHour の期待値を JS 実装から書き出す。
 *
 * Go 版 internal/notify との差分テスト（functions/go/internal/notify/golden_test.go）に使う。
 * 出力先: functions/javascript/scripts/notify_golden.json
 */
import * as fs from 'fs';
import * as path from 'path';
import { notifyUtcHour } from '../src/utils/notifyUtcHour';

const ZONES = [
  'Asia/Tokyo', 'Asia/Bangkok', 'Asia/Kolkata', 'Asia/Kathmandu',
  'Asia/Seoul', 'Asia/Shanghai', 'Asia/Jakarta', 'Asia/Yangon',
  'Asia/Tehran', 'Asia/Kabul', 'Australia/Adelaide', 'Australia/Sydney',
  'Australia/Eucla', 'Pacific/Chatham', 'Pacific/Kiritimati', 'Pacific/Auckland',
  'Pacific/Marquesas', 'Pacific/Honolulu', 'America/Los_Angeles', 'America/New_York',
  'America/St_Johns', 'America/Sao_Paulo', 'America/Santiago', 'America/Havana',
  'Europe/London', 'Europe/Berlin', 'Europe/Lisbon', 'Europe/Dublin',
  'Africa/Cairo', 'Africa/Lagos', 'Atlantic/Azores', 'UTC',
  'Not/AZone', '',
];

// DST 切り替え日を含む基準日（春・秋の両方を各半球で踏む）
const BASES = [
  '2026-01-15T00:00:00Z', '2026-03-08T00:00:00Z', '2026-03-29T00:00:00Z',
  '2026-04-05T00:00:00Z', '2026-07-21T00:00:00Z', '2026-09-06T00:00:00Z',
  '2026-10-04T00:00:00Z', '2026-10-25T00:00:00Z', '2026-11-01T00:00:00Z',
  '2026-12-31T00:00:00Z',
];

type Case = {
  timezone: string | null;
  preferred_hour: number | null;
  base: string;
  expected: number | null;
};

const cases: Case[] = [];
for (const base of BASES) {
  const baseDate = new Date(base);
  for (const zone of ZONES) {
    for (let hour = 0; hour < 24; hour++) {
      cases.push({
        timezone: zone,
        preferred_hour: hour,
        base,
        expected: notifyUtcHour(zone, hour, baseDate),
      });
    }
    // 希望時刻が未設定
    cases.push({
      timezone: zone,
      preferred_hour: null,
      base,
      expected: notifyUtcHour(zone, undefined, baseDate),
    });
  }
  // タイムゾーンも未設定
  cases.push({
    timezone: null,
    preferred_hour: null,
    base,
    expected: notifyUtcHour(undefined, undefined, baseDate),
  });
}

const out = path.join(__dirname, 'notify_golden.json');
fs.writeFileSync(out, JSON.stringify(cases, null, 1));
console.log(`wrote ${cases.length} cases -> ${out}`);
