import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/pronunciation/pronunciation_scorer.dart';
import 'package:thai_memo/core/thai_tone_analyzer.dart';
import 'package:thai_memo/presentation/providers/pronunciation_provider.dart';

SyllableScore _score(ThaiTone tone, ToneVerdict verdict) => SyllableScore(
      syllableIndex: 0,
      tone: tone,
      verdict: verdict,
    );

void main() {
  group('worstToneOf', () {
    test('正答率が最も低い声調を返す', () {
      final worst = worstToneOf([
        _score(ThaiTone.mid, ToneVerdict.correct),
        _score(ThaiTone.mid, ToneVerdict.correct),
        _score(ThaiTone.rising, ToneVerdict.wrong),
        _score(ThaiTone.rising, ToneVerdict.wrong),
      ]);
      expect(worst, 'rising');
    });

    test('試行回数ではなく正答率で比べる', () {
      // 上昇声は1回だけ外し、下降声は3回中2回外している。
      final worst = worstToneOf([
        _score(ThaiTone.rising, ToneVerdict.wrong),
        _score(ThaiTone.falling, ToneVerdict.wrong),
        _score(ThaiTone.falling, ToneVerdict.wrong),
        _score(ThaiTone.falling, ToneVerdict.correct),
      ]);
      expect(worst, 'rising');
    });

    test('close は正解として数えない', () {
      final worst = worstToneOf([
        _score(ThaiTone.mid, ToneVerdict.correct),
        _score(ThaiTone.low, ToneVerdict.close),
      ]);
      expect(worst, 'low');
    });

    test('unscored は集計に含めない', () {
      final worst = worstToneOf([
        _score(ThaiTone.mid, ToneVerdict.correct),
        _score(ThaiTone.unknown, ToneVerdict.unscored),
      ]);
      expect(worst, 'mid');
    });

    test('採点対象が無ければ空文字', () {
      expect(worstToneOf([]), '');
      expect(worstToneOf([_score(ThaiTone.unknown, ToneVerdict.unscored)]), '');
    });
  });
}
