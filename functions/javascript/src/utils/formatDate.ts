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

const JST_OFFSET_MS = 9 * 60 * 60 * 1000;

/** JST現在日時のDateオブジェクトを返す */
export function nowJST(): Date {
  return new Date(Date.now() + JST_OFFSET_MS);
}
