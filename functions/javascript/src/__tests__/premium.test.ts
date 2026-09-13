import {isEffectivePremium} from '../utils/premium';

const timestamp = (ms: number) => ({toMillis: () => ms});

describe('isEffectivePremium', () => {
  const now = Date.UTC(2026, 8, 13);

  test('tier反映待ちでも有効期限内の購読をpremiumとして扱う', () => {
    expect(isEffectivePremium({
      tier: 'free',
      subscription: {
        status: 'active',
        expires_at: timestamp(now + 60_000),
      },
    }, now)).toBe(true);
  });

  test('期限切れの購読はpremiumとして扱わない', () => {
    expect(isEffectivePremium({
      tier: 'free',
      subscription: {
        status: 'expired',
        expires_at: timestamp(now - 60_000),
      },
    }, now)).toBe(false);
  });

  test('tier反映待ちでも買い切りはpremiumとして扱う', () => {
    expect(isEffectivePremium({
      tier: 'free',
      subscription: {lifetime: true, status: 'active'},
    }, now)).toBe(true);
  });

  test('取消済み買い切りをpremiumへ復活させない', () => {
    expect(isEffectivePremium({
      tier: 'free',
      subscription: {lifetime: true, status: 'expired'},
    }, now)).toBe(false);
  });

  test('取消済み購読は期限が未来でもpremiumへ復活させない', () => {
    expect(isEffectivePremium({
      tier: 'free',
      subscription: {
        status: 'expired',
        expires_at: timestamp(now + 60_000),
      },
    }, now)).toBe(false);
  });

  test('保留中の購読は期限が未来でもpremiumへ復活させない', () => {
    expect(isEffectivePremium({
      tier: 'free',
      subscription: {
        status: 'on_hold',
        expires_at: timestamp(now + 60_000),
      },
    }, now)).toBe(false);
  });
});
