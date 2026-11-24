/// エラーメッセージが「本日の生成上限」によるものかを判定する。
///
/// エラーは表示用の文字列としてしか流れてこないため、文言で見分けている。
/// 言語ごとに共通の語が無いので、各言語ぶんの目印を見る。
/// 文言を変えるときは `quotaSentenceReached` / `quotaQuizReached` と
/// ここの目印が食い違わないよう揃えること。
bool isQuotaErrorMessage(String message) {
  const markers = ['ここまでです', 'last new', 'all the new', '여기까지'];
  final lower = message.toLowerCase();
  return markers.any(lower.contains);
}
