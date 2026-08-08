/**
 * lang.ts — 訳文・解説の言語（app_language）の正規化
 *
 * クライアントは callable リクエストに lang を載せてくる。
 * Python 側の constants.resolve_lang と同じ規則にすること。
 */

/** 対応言語 */
export const SUPPORTED_LANGS = ['ja', 'en'] as const;
export type Lang = (typeof SUPPORTED_LANGS)[number];

/** 既定言語 */
export const DEFAULT_LANG: Lang = 'ja';

/**
 * リクエストの lang を対応言語に正規化する。
 *
 * lang を送らない旧クライアントは ja になる（後方互換）。未知の値も ja に倒す。
 * 日本語ユーザーに英語の解説が返る事故のほうが、既定言語のまま返すより害が大きい。
 */
export function resolveLang(value: unknown): Lang {
  if (typeof value !== 'string') return DEFAULT_LANG;
  const lang = value.trim().toLowerCase();
  return (SUPPORTED_LANGS as readonly string[]).includes(lang)
    ? (lang as Lang)
    : DEFAULT_LANG;
}
