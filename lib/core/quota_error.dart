/// エラーメッセージが「本日の生成上限」によるものかを判定する。
///
/// エラーは表示用の文字列としてしか流れてこないため、文言で見分けている。
/// 英語版では「上限」が出ないので、両言語の目印を見る。
/// 文言を変えるときは `quotaSentenceReached` / `quotaQuizReached` と
/// ここの目印が食い違わないよう揃えること。
bool isQuotaErrorMessage(String message) {
  const markers = ['上限', 'limit'];
  final lower = message.toLowerCase();
  return markers.any(lower.contains);
}
