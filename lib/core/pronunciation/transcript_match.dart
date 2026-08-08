// =============================================================================
// transcript_match.dart
// 音声認識の結果と例文を突き合わせ、語ごとに「通じたか」を返す。
//
// 声調（ピッチ）の判定とは別軸の検査。声調が合っていても子音・母音を外していれば
// 語として通じないため、両方を出さないと学習者は何を直せばよいか分からない。
//
// この検査の性質を理解しておくこと。音声認識は言語モデルで補正を掛けるため、
// 多少発音を外しても期待される語に「直して」認識する。つまり**見逃す方向に甘い**。
// 逆に認識できなかった場合は「通じないレベルで外している」という強い信号になる。
// そのため結果は「合っている／間違っている」ではなく「通じた／通じなかった」として扱う。
// =============================================================================

/// 語ごとの認識結果。
enum WordRecognition {
  /// 認識結果に現れた（通じた）。
  recognized,

  /// 認識結果に現れなかった（通じなかった可能性が高い）。
  missing,

  /// 判定していない。端末が音声認識に対応していない場合。
  unavailable,
}

/// 照合の前に取り除く文字。
///
/// タイ語は語間に空白を置かないが、認識器は区切りとして空白を差し込むことがある。
/// 句読点も認識器が付けたり付けなかったりするため、両側から落として比べる。
final RegExp _ignoredChars = RegExp(r'[\s​.,!?;:"' "'" r'()\[\]।๚๛]');

/// SARA AM（ำ）の分解形。NIKHAHIT + SARA AA。
///
/// タイ文字の ำ は、見た目が同じでも1文字（U+0E33）と2文字（U+0E4D U+0E32）の
/// 2通りの表し方がある。**Unicode の正規化（NFC）では統一されない**ため、
/// 明示的に畳む必要がある。
///
/// 音声認識は分解形を返すことがあり、これを揃えないと ทำ・น้ำ・คำ・จำ のような
/// 頻出語がすべて「認識されなかった」と誤判定される。
const String _decomposedSaraAm = 'ํา';
const String _saraAm = 'ำ';

/// 照合用に文字列を正規化する。
String normalizeForMatch(String text) => text
    .replaceAll(_decomposedSaraAm, _saraAm)
    .replaceAll(_ignoredChars, '');

/// 認識結果と例文の語を突き合わせる。
///
/// 語が例文の順に現れるかを前から順に探す。見つかった語の直後から次の語を探すので、
/// 語順が入れ替わっている場合は後ろの語が [WordRecognition.missing] になる。
/// 認識器が語を落とした場合も同様。
///
/// [available] が false のとき（端末が音声認識に対応していない、権限が無い等）は
/// 全語を [WordRecognition.unavailable] にする。判定できないことと
/// 判定して駄目だったことを混同させない。
List<WordRecognition> matchTranscript({
  required List<String> expectedWords,
  required String transcript,
  bool available = true,
}) {
  if (!available) {
    return List<WordRecognition>.filled(
      expectedWords.length,
      WordRecognition.unavailable,
    );
  }

  final haystack = normalizeForMatch(transcript);
  final results = <WordRecognition>[];
  var cursor = 0;

  for (final word in expectedWords) {
    final needle = normalizeForMatch(word);
    if (needle.isEmpty) {
      results.add(WordRecognition.unavailable);
      continue;
    }

    final found = haystack.indexOf(needle, cursor);
    if (found >= 0) {
      results.add(WordRecognition.recognized);
      cursor = found + needle.length;
    } else {
      // カーソルは進めない。1語聞き取れなかっただけで、以降が全て
      // missing に倒れるのを防ぐ。
      results.add(WordRecognition.missing);
    }
  }

  return results;
}

/// 判定できた語のうち、認識された語の割合（0.0〜1.0）。
///
/// 判定対象が無ければ null。全体の傾向をアナリティクスへ送るために使う。
double? recognizedRatio(List<WordRecognition> results) {
  final judged = results
      .where((r) => r != WordRecognition.unavailable)
      .toList();
  if (judged.isEmpty) return null;

  final recognized =
      judged.where((r) => r == WordRecognition.recognized).length;
  return recognized / judged.length;
}
