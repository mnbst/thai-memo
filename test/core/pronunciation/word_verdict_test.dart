import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/pronunciation/pronunciation_scorer.dart';
import 'package:thai_memo/core/pronunciation/transcript_match.dart';
import 'package:thai_memo/core/pronunciation/word_verdict.dart';
import 'package:thai_memo/core/thai_tone_analyzer.dart';

SyllableScore _score(ToneVerdict verdict) => SyllableScore(
      syllableIndex: 0,
      tone: ThaiTone.mid,
      verdict: verdict,
    );

void main() {
  group('toneVerdictOfWord', () {
    test('全て correct なら correct', () {
      expect(
        toneVerdictOfWord([_score(ToneVerdict.correct), _score(ToneVerdict.correct)]),
        ToneVerdict.correct,
      );
    });

    test('1音節でも外していれば correct にはしない', () {
      // 0.75 の頃はここが correct だった。直すべき語が緑に見えるので締めた。
      expect(
        toneVerdictOfWord([
          _score(ToneVerdict.correct),
          _score(ToneVerdict.correct),
          _score(ToneVerdict.close),
        ]),
        ToneVerdict.close,
      );
    });

    test('外した音節が1つでも、語全体を wrong にはしない', () {
      // 1音節でも外すと語全体が赤くなる作りでは、どこを直すか分からない。
      expect(
        toneVerdictOfWord([
          _score(ToneVerdict.correct),
          _score(ToneVerdict.correct),
          _score(ToneVerdict.wrong),
        ]),
        ToneVerdict.close,
      );
    });

    test('半分が close なら close', () {
      expect(
        toneVerdictOfWord([_score(ToneVerdict.correct), _score(ToneVerdict.wrong)]),
        ToneVerdict.close,
      );
    });

    test('全て wrong なら wrong', () {
      expect(
        toneVerdictOfWord([_score(ToneVerdict.wrong), _score(ToneVerdict.wrong)]),
        ToneVerdict.wrong,
      );
    });

    test('unscored しか無ければ unscored', () {
      expect(toneVerdictOfWord([_score(ToneVerdict.unscored)]), ToneVerdict.unscored);
    });

    test('unscored は分母に入れない', () {
      expect(
        toneVerdictOfWord([_score(ToneVerdict.correct), _score(ToneVerdict.unscored)]),
        ToneVerdict.correct,
      );
    });
  });

  group('combinedWordVerdict', () {
    test('通じたことは加点にしない（声調をそのまま通す）', () {
      for (final tone in ToneVerdict.values) {
        expect(
          combinedWordVerdict(tone, WordRecognition.recognized),
          tone,
          reason: '$tone',
        );
      }
    });

    test('発音を判定していない端末では声調のみで決まる', () {
      for (final tone in ToneVerdict.values) {
        expect(combinedWordVerdict(tone, WordRecognition.unavailable), tone);
      }
    });

    test('通じなかった語は、声調が合っていても言い直す（wrong）', () {
      for (final tone in ToneVerdict.values) {
        expect(
          combinedWordVerdict(tone, WordRecognition.missing),
          ToneVerdict.wrong,
          reason: '$tone',
        );
      }
    });
  });

  group('combinedScore', () {
    test('全て通じたら声調の点と発音の満点で決まる', () {
      expect(
        combinedScore(80, List.filled(4, WordRecognition.recognized)),
        80 * 0.5 + 100 * 0.5,
      );
    });

    test('全て通じなければ声調の点の半分', () {
      expect(
        combinedScore(80, List.filled(4, WordRecognition.missing)),
        40,
      );
    });

    test('通じた語の割合がそのまま発音側の点になる', () {
      expect(
        combinedScore(60, const [
          WordRecognition.recognized,
          WordRecognition.recognized,
          WordRecognition.recognized,
          WordRecognition.missing,
        ]),
        60 * 0.5 + 75 * 0.5,
      );
    });

    test('判定していない端末では声調の点をそのまま返す', () {
      // 発音側を満点として足すと、対応していない端末のほうが点が出てしまう。
      expect(combinedScore(70, List.filled(3, WordRecognition.unavailable)), 70);
      expect(combinedScore(70, const []), 70);
    });

    test('unavailable は分母に入れない', () {
      expect(
        combinedScore(80, const [
          WordRecognition.recognized,
          WordRecognition.unavailable,
        ]),
        80 * 0.5 + 100 * 0.5,
      );
    });
  });
}
