/**
 * notifyUtcHour.test.ts
 *
 * 配信対象クエリの絞り込みに使う UTC 時刻の算出を検証する。
 */
import { notifyUtcHour } from '../utils/notifyUtcHour';

const BASE = new Date('2026-07-21T00:00:00Z');

/** Intl で現地時刻の「時」を取り直す（算出結果の検算用） */
function localHour(timezone: string, date: Date): number {
  return Number(
    new Intl.DateTimeFormat('en-US', {
      timeZone: timezone,
      hour: 'numeric',
      hourCycle: 'h23',
    }).format(date)
  );
}

describe('notifyUtcHour', () => {
  // 分単位オフセットのtzでも、現地の各時刻はUTCのいずれか1時刻に対応する
  const zones = [
    'Asia/Tokyo',
    'Asia/Bangkok',
    'Asia/Kolkata', // +5:30
    'Asia/Kathmandu', // +5:45
    'America/Los_Angeles',
    'Pacific/Chatham', // +12:45
  ];

  it.each(zones)('%s の全希望時刻で現地時刻と一致する', (timezone) => {
    for (let preferred = 0; preferred < 24; preferred++) {
      const utcHour = notifyUtcHour(timezone, preferred, BASE);
      expect(utcHour).not.toBeNull();
      const at = new Date(BASE.getTime() + (utcHour as number) * 3600_000);
      expect(localHour(timezone, at)).toBe(preferred);
    }
  });

  it('未設定は Asia/Tokyo 10時 = UTC 1時', () => {
    expect(notifyUtcHour(undefined, undefined, BASE)).toBe(1);
  });

  it('不正なタイムゾーンは Asia/Tokyo にフォールバックする', () => {
    expect(notifyUtcHour('Not/AZone', 10, BASE)).toBe(1);
  });

  it('DST春の切り替え日に存在しない現地時刻は null', () => {
    const dstDay = new Date('2026-03-08T00:00:00Z');
    expect(notifyUtcHour('America/Los_Angeles', 2, dstDay)).toBeNull();
  });
});
