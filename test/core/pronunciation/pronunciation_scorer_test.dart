import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/pronunciation/pronunciation_scorer.dart';
import 'package:thai_memo/core/thai_tone_analyzer.dart';

SyllableScore _score(ToneVerdict verdict) => SyllableScore(
      syllableIndex: 0,
      tone: ThaiTone.mid,
      verdict: verdict,
    );

void main() {
  group('contourSlope', () {
    test('上昇するカーブは正の傾き', () {
      expect(contourSlope([0, 0.25, 0.5, 0.75, 1]), greaterThan(0));
    });

    test('下降するカーブは負の傾き', () {
      expect(contourSlope([1, 0.75, 0.5, 0.25, 0]), lessThan(0));
    });

    test('平坦なカーブは傾き0', () {
      expect(contourSlope([0.4, 0.4, 0.4, 0.4]), closeTo(0, 1e-9));
    });

    test('点が足りなければ0', () {
      expect(contourSlope([]), 0);
      expect(contourSlope([0.5]), 0);
    });

    test('端の1点が外れても向きは反転しない', () {
      // 始点と終点の差で傾きを取ると、検出誤りで判定が裏返る。
      // 回帰直線を使っているかの確認。
      final clean = [1.0, 0.8, 0.6, 0.4, 0.2];
      final withOutlier = [1.0, 0.8, 0.6, 0.4, 1.1];
      expect(contourSlope(clean), lessThan(0));
      expect(contourSlope(withOutlier), lessThan(0));
    });
  });

  group('overallScoreOf', () {
    test('全て correct なら100', () {
      expect(
        overallScoreOf([_score(ToneVerdict.correct), _score(ToneVerdict.correct)]),
        100,
      );
    });

    test('close は半分として数える', () {
      expect(
        overallScoreOf([_score(ToneVerdict.correct), _score(ToneVerdict.close)]),
        75,
      );
    });

    test('全て wrong なら0', () {
      expect(overallScoreOf([_score(ToneVerdict.wrong)]), 0);
    });

    test('unscored は分母に入れない', () {
      expect(
        overallScoreOf([
          _score(ToneVerdict.correct),
          _score(ToneVerdict.unscored),
        ]),
        100,
      );
    });

    test('採点対象が無ければ0', () {
      expect(overallScoreOf([]), 0);
      expect(overallScoreOf([_score(ToneVerdict.unscored)]), 0);
    });
  });
}
