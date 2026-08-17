// 2節の文（thai_text の空白で区切られた文）を、正しく発音したときに通ることを守る。
//
// 話者は節の切れ目で息を継ぎ、**声を上げ直す**。declination は節ごとにやり直され、
// 節末では（文末ほどではないが）下がる。お手本を「全体で1本の直線」で描くと、
// 節1の末尾が低すぎ、節2の頭が高すぎると判定され、正しい発話が落ちる。
//
// 息継ぎの無音そのものも壊れやすい。時間軸が伸びるぶん比例配分の予想位置がずれ、
// 間の周りの音節が丸ごとずれる。だから間の長さも一緒に振って確かめる。
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/pronunciation/pronunciation_analyzer.dart';
import 'package:thai_memo/core/pronunciation/pronunciation_scorer.dart';
import 'package:thai_memo/core/pronunciation/tone_contour.dart';
import 'package:thai_memo/core/thai_tone_analyzer.dart';

import '../../helpers/f0_synthesizer.dart';

/// 2節・8音節。節2は 添字4 から始まる。
const _tones = [
  ThaiTone.mid,
  ThaiTone.falling,
  ThaiTone.low,
  ThaiTone.rising,
  ThaiTone.high,
  ThaiTone.mid,
  ThaiTone.falling,
  ThaiTone.low,
];

const _clauseStarts = [4];

/// 節の切れ目の間（300ms）。
const _pauseFrames = 30;

/// [spoken] は話者が実際に声を上げ直す位置。[given] は**判定側に渡す**切れ目で、
/// 省略すると [spoken] と同じ。渡さなかったとき何が起きるかを見るために分けてある。
List<SyllableScore> _scores({
  List<ThaiTone> tones = _tones,
  List<int> spoken = _clauseStarts,
  List<int>? given,
  int pauseFrames = _pauseFrames,
  double clauseFinalLowering = kClauseFinalLoweringRange,
}) {
  final result = analyzePronunciation(
    f0Hz: synthesizeF0(
      tones: tones,
      clauseStarts: spoken,
      pauseFrames: pauseFrames,
      clauseFinalLowering: clauseFinalLowering,
      unvoicedOnsetFrames: 3,
    ),
    tones: tones,
    clauseStarts: given ?? spoken,
  );
  expect(result.isScored, isTrue, reason: '採点できていない: ${result.failure}');
  return result.syllables;
}

int _badCount(List<SyllableScore> scores) =>
    scores.where((s) => s.verdict != ToneVerdict.correct).length;

String _detail(List<SyllableScore> scores) => [
      for (final s in scores)
        '${s.syllableIndex}:${s.tone.name}=${s.verdict.name}'
            '(lvl=${(s.queryLevel - s.referenceLevel).toStringAsFixed(2)})',
    ].join(' ');

void main() {
  group('2節の文を正しく発音したとき', () {
    test('全音節が correct', () {
      final scores = _scores();
      expect(_badCount(scores), 0, reason: _detail(scores));
    });

    test('間の長さが 0〜1秒のどこでも通る', () {
      // 1秒の間は、比例配分の予想位置を 50 フレーム動かす（帯は 6%）。
      for (final pause in [0, 15, 30, 60, 100]) {
        final scores = _scores(pauseFrames: pause);
        expect(
          _badCount(scores),
          0,
          reason: '間 ${pause * 10}ms — ${_detail(scores)}',
        );
      }
    });

    test('切れ目がどの位置にあっても通る', () {
      for (var breakAt = 1; breakAt < _tones.length; breakAt++) {
        for (final pause in [30, 100]) {
          final scores = _scores(spoken: [breakAt], pauseFrames: pause);
          expect(
            _badCount(scores),
            0,
            reason: '切れ目=$breakAt 間=${pause * 10}ms — ${_detail(scores)}',
          );
        }
      }
    });

    test('長い息継ぎを「声が拾えていない」にしない', () {
      // 子音の無声区間が半分あり（onset 150ms）、さらに 1.2 秒の息継ぎが入ると、
      // 声のフレームの割合は 0.50 から 0.33 へ落ちて [kMinVoicedRatio] を切る。
      // 節の切れ目が分かっていれば、その無音は息継ぎだと分かる。
      final f0 = synthesizeF0(
        tones: _tones,
        clauseStarts: _clauseStarts,
        pauseFrames: 120,
        unvoicedOnsetFrames: 15,
      );

      expect(
        analyzePronunciation(
          f0Hz: f0,
          tones: _tones,
          clauseStarts: _clauseStarts,
        ).failure,
        PronunciationFailure.none,
      );
      // 切れ目を渡さなければ、息継ぎと騒音の区別が付かない（従来どおり弾く）。
      expect(
        analyzePronunciation(f0Hz: f0, tones: _tones).failure,
        PronunciationFailure.tooQuiet,
      );
    });

    test('節末の下がり方は話者によって違ってよい', () {
      // 下がらない（0）／お手本どおり／文末と同じだけ下がる／逆に上がる。
      // お手本は起こり得る幅の真ん中を当てているので、どちらへ振れても
      // 収まっていること（[kClauseFinalLoweringRange]）。
      for (final drop in [
        0.0,
        kClauseFinalLoweringRange,
        kFinalLoweringRange,
        -0.2,
      ]) {
        final scores = _scores(clauseFinalLowering: drop);
        expect(
          _badCount(scores),
          0,
          reason: '節末の下がり $drop — ${_detail(scores)}',
        );
      }
    });
  });

  // 切れ目の前後にどの声調が来ても崩れないことを見る。1組の並びだけでは、
  // たまたま通る組を選んでいないと言えない。
  group('切れ目の前後の声調を総当たりしても', () {
    const all = [
      ThaiTone.mid,
      ThaiTone.low,
      ThaiTone.falling,
      ThaiTone.high,
      ThaiTone.rising,
    ];

    /// 誤判定を許す上限（音節数に対する割合）。
    ///
    /// 0 にはできない。合成側は declination と節末の下がりを生のカーブに足すが、
    /// お手本は正規化した尺度の上で足すので、下がり量の**声調の振れ幅に対する
    /// 比が両者で違う**。節が2つになると下がりも2回来るので、この食い違いも
    /// 2倍に出る。合成側を正規化して揃えると今度は声調の取り違えを見逃す側へ
    /// 倒れた（calibration_test が2件通ってしまう）ので、ここは合わせない。
    ///
    /// 残るのは節末・節頭の平坦声調の「惜しい」で、話者が文末と同じだけ下げた
    /// 回にだけ出る（お手本はその半分を見込んでいる）。
    const tolerance = 0.03;

    /// 25通りを1回ぶん採点し、誤判定の数を返す。
    int badOf({required bool given, required double drop}) {
      var bad = 0;
      final detail = <String>[];
      for (final before in all) {
        for (final after in all) {
          // 節1 = [mid, X] / 節2 = [Y, mid, falling]
          final tones = [
            ThaiTone.mid,
            before,
            after,
            ThaiTone.mid,
            ThaiTone.falling,
          ];
          final scores = _scores(
            tones: tones,
            spoken: const [2],
            given: given ? null : const [],
            clauseFinalLowering: drop,
          );
          final count = _badCount(scores);
          bad += count;
          if (count > 0) {
            detail.add('${before.name}→${after.name}: ${_detail(scores)}');
          }
        }
      }
      if (detail.isNotEmpty) {
        printOnFailure('given=$given drop=$drop\n${detail.join('\n')}');
      }
      return bad;
    }

    test('誤判定が $tolerance を超えない', () {
      for (final drop in [
        0.0,
        kClauseFinalLoweringRange,
        kFinalLoweringRange,
      ]) {
        final bad = badOf(given: true, drop: drop);
        expect(bad / (25 * 5), lessThanOrEqualTo(tolerance),
            reason: '節末の下がり $drop で $bad/125');
      }
    });

    // 判定が厳しくなってからは、切れ目を渡さなくても誤判定が 0 に落ちる
    // 並びが出る。**増えないこと**を守る（渡して悪化しないことが要件）。
    test('切れ目を渡しても誤判定が増えない', () {
      for (final drop in [
        0.0,
        kClauseFinalLoweringRange,
        kFinalLoweringRange,
      ]) {
        final given = badOf(given: true, drop: drop);
        final notGiven = badOf(given: false, drop: drop);
        expect(given, lessThanOrEqualTo(notGiven), reason: '節末の下がり $drop');
      }
    });
  });
}
