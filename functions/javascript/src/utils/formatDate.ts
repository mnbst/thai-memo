export function formatDate(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

/** JST現在日時を "YYYY-MM-DD" 形式で返す */
export function todayJST(): string {
  return new Date().toLocaleDateString('ja-JP', {
    timeZone: 'Asia/Tokyo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).replace(/\//g, '-');
}

/** JST現在日時のDateオブジェクトを返す（内部的にAsia/Tokyoオフセット適用） */
export function nowJST(): Date {
  const now = new Date();
  const jstString = now.toLocaleString('en-US', { timeZone: 'Asia/Tokyo' });
  return new Date(jstString);
}
