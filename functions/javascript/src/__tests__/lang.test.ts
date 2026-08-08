import { resolveLang } from '../utils/lang';

describe('resolveLang', () => {
  it('対応言語はそのまま返す', () => {
    expect(resolveLang('ja')).toBe('ja');
    expect(resolveLang('en')).toBe('en');
  });

  it('大文字・前後の空白を吸収する', () => {
    expect(resolveLang('EN')).toBe('en');
    expect(resolveLang(' ja ')).toBe('ja');
  });

  it('lang を送らない旧クライアントは ja になる', () => {
    expect(resolveLang(undefined)).toBe('ja');
    expect(resolveLang(null)).toBe('ja');
  });

  it('未知・不正な値は ja に倒す', () => {
    // 日本語ユーザーに英語の解説が返るより、既定言語のままのほうが害が小さい
    expect(resolveLang('th')).toBe('ja');
    expect(resolveLang('')).toBe('ja');
    expect(resolveLang(123)).toBe('ja');
    expect(resolveLang({})).toBe('ja');
  });
});
