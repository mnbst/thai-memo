/**
 * notifyUtcHour.ts — 毎日例文の配信対象を時刻で絞り込むための非正規化フィールド。
 *
 * deliverDailySentence は毎時起動し、ユーザーのローカル時刻が配信希望時刻と
 * 一致する対象だけに配信する。この判定を Firestore クエリ側で行えるよう、
 * 「現地の preferred_generation_hour が UTC の何時の起動に当たるか」を
 * users/{uid}.notify_utc_hour に持たせる。
 */

/** 配信希望時刻のデフォルト（daily_sentence.py の DEFAULT_GENERATION_HOUR と一致） */
export const DEFAULT_GENERATION_HOUR = 10;
/** タイムゾーン未設定・不正時のフォールバック */
export const DEFAULT_TIMEZONE = 'Asia/Tokyo';

function localHour(timezone: string, date: Date): number | null {
  try {
    const formatted = new Intl.DateTimeFormat('en-US', {
      timeZone: timezone,
      hour: 'numeric',
      hourCycle: 'h23',
    }).format(date);
    return Number(formatted);
  } catch {
    return null;
  }
}

/**
 * 現地の preferredHour が UTC の何時の起動に当たるかを求める。
 *
 * オフセットの引き算ではなく24通りを実際に現地時刻へ変換して探す。
 * こうすることで +5:30 / +5:45 のような分単位オフセット（現地 10:30 に配信
 * される、というズレはあるが対応は1対1）や DST でも正しい値になる。
 *
 * DST の春の切り替え日はその現地時刻自体が存在しないため null を返す。
 * 呼び出し側は既存値を維持する（その日は配信されない = 従来と同じ挙動）。
 */
export function notifyUtcHour(
  timezone: string | undefined,
  preferredHour: number | undefined,
  base: Date = new Date(),
): number | null {
  const tz = timezone || DEFAULT_TIMEZONE;
  const hour = typeof preferredHour === 'number' ?
    preferredHour :
    DEFAULT_GENERATION_HOUR;
  const day = new Date(Date.UTC(
    base.getUTCFullYear(), base.getUTCMonth(), base.getUTCDate(),
  ));

  for (let utcHour = 0; utcHour < 24; utcHour++) {
    const candidate = new Date(day.getTime() + utcHour * 3600_000);
    const resolved = localHour(tz, candidate) ??
      localHour(DEFAULT_TIMEZONE, candidate);
    if (resolved === hour) return utcHour;
  }
  return null;
}
