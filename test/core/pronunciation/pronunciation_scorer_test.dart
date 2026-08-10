import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/pronunciation/pronunciation_scorer.dart';
import 'package:thai_memo/core/thai_tone_analyzer.dart';

SyllableScore _score(ToneVerdict verdict) => SyllableScore(
      syllableIndex: 0,
      tone: ThaiTone.mid,
      verdict: verdict,
    );

void main() {
  group('contourRise', () {
    test('上がって終わるカーブは正', () {
      expect(contourRise([0, 0.25, 0.5, 0.75, 1]), greaterThan(0));
    });

    test('下がって終わるカーブは負', () {
      expect(contourRise([1, 0.75, 0.5, 0.25, 0]), lessThan(0));
    });

    test('平坦なカーブは0', () {
      expect(contourRise([0.4, 0.4, 0.4, 0.4]), closeTo(0, 1e-9));
    });

    test('点が足りなければ0', () {
      expect(contourRise([]), 0);
      expect(contourRise([0.5]), 0);
    });

    test('端の1点が外れても向きは反転しない', () {
      // 端の1点をそのまま使うと、検出誤りで判定が裏返る。
      // 前後25%の中央値を採っているかの確認。
      final clean = [1.0, 0.8, 0.6, 0.4, 0.2];
      final withOutlier = [1.0, 0.8, 0.6, 0.4, 1.1];
      expect(contourRise(clean), lessThan(0));
      expect(contourRise(withOutlier), lessThan(0));
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
