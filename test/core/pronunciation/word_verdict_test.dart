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

    test('1音節だけ外した3音節の語は correct のまま', () {
      // 1音節でも外すと語全体が赤くなる作りでは、どこを直すか分からない。
      expect(
        toneVerdictOfWord([
          _score(ToneVerdict.correct),
          _score(ToneVerdict.correct),
          _score(ToneVerdict.close),
        ]),
        ToneVerdict.correct,
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

    test('通じなかったら声調が合っていても一段下げる', () {
      expect(
        combinedWordVerdict(ToneVerdict.correct, WordRecognition.missing),
        ToneVerdict.close,
      );
    });

    test('声調も惜しい以下なら wrong', () {
      expect(
        combinedWordVerdict(ToneVerdict.close, WordRecognition.missing),
        ToneVerdict.wrong,
      );
      expect(
        combinedWordVerdict(ToneVerdict.wrong, WordRecognition.missing),
        ToneVerdict.wrong,
      );
    });

    test('声調が測れなくても、通じなかったことは伝える', () {
      expect(
        combinedWordVerdict(ToneVerdict.unscored, WordRecognition.missing),
        ToneVerdict.wrong,
      );
    });
  });
}
