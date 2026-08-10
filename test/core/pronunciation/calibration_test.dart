// 閾値が「正しい発話を通し、声調の取り違えを弾く」範囲に収まっていることを守る。
//
// 判定が厳しすぎる発音練習は続かないので閾値は緩めたいが、緩めすぎると
// 声調の取り違えが「合っている」に化けて機能の中身が無くなる。
// その両側をこのテストで固定する。
//
// 採点は「その音節の中でのピッチの動き（形）」と「**直前の音節が終わった高さ**
// から見た入り方」の2つ。どちらも**向きしか見ない**。振れ幅・下げ幅・声域内の
// 絶対的な高さは採点しない。高さも動きの大きさも話者・場面・文中の位置で素直に
// 動くので、正しく発音していても弾かれてしまう。
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/pronunciation/pronunciation_analyzer.dart';
import 'package:thai_memo/core/pronunciation/pronunciation_scorer.dart';
import 'package:thai_memo/core/pronunciation/tone_contour.dart';
import 'package:thai_memo/core/thai_tone_analyzer.dart';

import '../../helpers/f0_synthesizer.dart';

const _tones = [
  ThaiTone.mid,
  ThaiTone.falling,
  ThaiTone.low,
  ThaiTone.rising,
  ThaiTone.high,
  ThaiTone.mid,
];

SyllableScore _scoreOf(
  Map<int, ThaiTone> substitutions,
  int target, {
  int unvoicedOnsetFrames = 0,
}) {
  final result = analyzePronunciation(
    f0Hz: synthesizeF0(
      tones: _tones,
      substitutions: substitutions,
      unvoicedOnsetFrames: unvoicedOnsetFrames,
    ),
    tones: _tones,
  );
  return result.syllables[target];
}

String _detail(SyllableScore score) =>
    'corr=${score.shapeCorrelation?.toStringAsFixed(2) ?? '-'} '
    'slopeErr=${score.shapeError.toStringAsFixed(2)} '
    'step=${score.queryStep.toStringAsFixed(2)}'
    '/${score.referenceStep.toStringAsFixed(2)}';

void main() {
  group('正しい発話は余裕をもって通る', () {
    test('どの音節も correct になる', () {
      for (var i = 0; i < _tones.length; i++) {
        final score = _scoreOf(const {}, i);
        expect(
          score.shapeError,
          lessThan(kShapeErrorThreshold),
          reason: '音節$i (${_tones[i].name}) の形状誤差',
        );
        expect(
          score.verdict,
          ToneVerdict.correct,
          reason: '音節$i (${_tones[i].name}) ${_detail(score)}',
        );
      }
    });

    test('入り方の向きが、境目に張り付いていない', () {
      // 向きの3分割は境目で跳ねる。お手本の段差が [kFlatStepThreshold] の
      // すぐ内側にあると、録音がほんの少し大きく動いただけで割れてしまう。
      // 正しい発話では、段差そのものの差がその幅に収まっていること。
      for (var i = 0; i < _tones.length; i++) {
        final score = _scoreOf(const {}, i);
        expect(
          score.transitionError,
          lessThanOrEqualTo(kFlatStepThreshold),
          reason: '音節$i (${_tones[i].name}) ${_detail(score)}',
        );
      }
    });
  });

  group('子音の無声区間があっても正しい発話は通る', () {
    // 実際の発話では音節の頭に必ず無声の子音が入る。この区間を落として時間軸が
    // 縮むと、DTWの帯（時間が比例している前提）と噛み合わずに対応づけがずれる。
    // カーブも有声区間の継ぎ目で垂直に跳んで見える。
    for (final onset in [3, 6, 9]) {
      test('音節の頭に無声フレーム$onset個', () {
        for (var i = 0; i < _tones.length; i++) {
          final score = _scoreOf(const {}, i, unvoicedOnsetFrames: onset);
          expect(
            score.verdict,
            ToneVerdict.correct,
            reason: '音節$i (${_tones[i].name}) ${_detail(score)}',
          );
        }
      });
    }
  });

  group('発話の途中の無声区間を落とさない', () {
    // 閉鎖音の閉鎖区間は 120ms（[kMaxInterpolatedGap]）を超えることがある。
    // そこを時間軸から削ると、削られる量が音節ごとに違うので DTW の帯
    // （時間が比例している前提）と噛み合わなくなる。実機で 460 フレーム中 161 が
    // 消え、死音節の取り分が予算の 0.4〜0.8 倍に出ていた。
    for (final onset in [12]) {
      test('$onset フレーム（${onset * 10}ms）の無声区間があっても通る', () {
        for (var i = 0; i < _tones.length; i++) {
          final score = _scoreOf(const {}, i, unvoicedOnsetFrames: onset);
          expect(
            score.verdict,
            ToneVerdict.correct,
            reason: '音節$i (${_tones[i].name}) ${_detail(score)}',
          );
        }
      });
    }

    test('無声区間のぶん、音節の取り分が縮まない', () {
      // 音節ごとの無声区間の長さは同じなので、取り分の比は無声が無いときと
      // 変わらないはず。削っていると、縮み方の違いがここに出る。
      final withoutGap = [
        for (var i = 0; i < _tones.length; i++)
          _scoreOf(const {}, i).queryEnd - _scoreOf(const {}, i).queryStart + 1,
      ];
      final withGap = [
        for (var i = 0; i < _tones.length; i++)
          _scoreOf(const {}, i, unvoicedOnsetFrames: 12).queryEnd -
              _scoreOf(const {}, i, unvoicedOnsetFrames: 12).queryStart +
              1,
      ];
      final totalWithout = withoutGap.reduce((a, b) => a + b);
      final totalWith = withGap.reduce((a, b) => a + b);
      for (var i = 0; i < _tones.length; i++) {
        expect(
          withGap[i] / totalWith,
          closeTo(withoutGap[i] / totalWithout, 0.03),
          reason: '音節$i (${_tones[i].name}) の取り分',
        );
      }
    });
  });

  group('長い無音は音節の切れ目へ寄る', () {
    // 声の途切れは音節の切れ目の手がかり。無声フレームの対応づけコストを一律 0 に
    // すると、長い途切れの中では経路がどこを通っても同じになり、境界が決まらない。
    // 実機で 440ms の空白が音節の真ん中に飲み込まれ、隣の音節が9フレームまで
    // 潰れて採点不能になった。
    test('音節の切れ目に置いた 300ms の間で、両隣が潰れない', () {
      final f0 = synthesizeF0(tones: _tones);
      // 音節2と3の境目（30フレーム区切り）に無音を差し込む。
      final withPause = <double?>[
        ...f0.sublist(0, 90),
        ...List<double?>.filled(30, null),
        ...f0.sublist(90),
      ];
      final result = analyzePronunciation(f0Hz: withPause, tones: _tones);
      for (var i = 0; i < _tones.length; i++) {
        final score = result.syllables[i];
        expect(
          score.queryValues.length,
          greaterThanOrEqualTo(kMinVoicedFramesPerSyllable),
          reason: '音節$i (${_tones[i].name}) が潰れている',
        );
      }
    });
  });

  group('手がかりの無い切れ目は予算どおりに置く', () {
    // 共鳴音で繋がり（途切れが出ない）、かつ同じ声調が並ぶと、音響的にも
    // 声調的にも境界を決められない。DTW に選ばせると当てずっぽうになり、実機で
    // 同じ文を9回録ると2音節の合計は 28〜38% とほぼ一定なのに、その中の分け方が
    // 毎回反転し、どちらかが有声5フレーム未満になって採点不能になった。
    const sameTone = [
      ThaiTone.mid,
      ThaiTone.high,
      ThaiTone.high,
      ThaiTone.low,
    ];

    test('同じ声調が繋がって並んでも、どちらも潰れない', () {
      final result = analyzePronunciation(
        // 無声区間を置かない＝境界の手がかりが無い状態。
        f0Hz: synthesizeF0(tones: sameTone),
        tones: sameTone,
      );
      for (var i = 0; i < sameTone.length; i++) {
        expect(
          result.syllables[i].queryValues.length,
          greaterThanOrEqualTo(kMinVoicedFramesPerSyllable),
          reason: '音節$i (${sameTone[i].name}) が潰れている',
        );
      }
    });

    test('分け方が予算の比になる', () {
      final result = analyzePronunciation(
        f0Hz: synthesizeF0(tones: sameTone),
        tones: sameTone,
      );
      // 同じ予算の2音節なので、取り分もほぼ同じになるはず。
      final second = result.syllables[1].queryEnd - result.syllables[1].queryStart;
      final third = result.syllables[2].queryEnd - result.syllables[2].queryStart;
      expect(second / third, closeTo(1.0, 0.25));
    });
  });

  group('声調の取り違えは correct にならない', () {
    const cases = <String, (Map<int, ThaiTone>, int)>{
      '下降→上昇': ({1: ThaiTone.rising}, 1),
      '上昇→下降': ({3: ThaiTone.falling}, 3),
      '上昇→中平': ({3: ThaiTone.mid}, 3),
      '低平→高平': ({2: ThaiTone.high}, 2),
      '高平→低平': ({4: ThaiTone.low}, 4),
      '高平→中平': ({4: ThaiTone.mid}, 4),
      '上昇→高平': ({3: ThaiTone.high}, 3),
      '下降→中平': ({1: ThaiTone.mid}, 1),
      // 文頭は入り方が無いので形だけで見る。平らな3声調どうしでも、逆向きに
      // 動いていれば相関が負に出るのでそこで落とせる。
      '文頭の 中平→下降': ({0: ThaiTone.falling}, 0),
      '文頭の 中平→高平': ({0: ThaiTone.high}, 0),
      '文頭の 中平→上昇': ({0: ThaiTone.rising}, 0),
    };

    cases.forEach((label, params) {
      test(label, () {
        final score = _scoreOf(params.$1, params.$2);
        expect(
          score.verdict,
          isNot(ToneVerdict.correct),
          reason: '$label が見逃されている (${_detail(score)})',
        );
      });
    });
  });

  group('発話末の下がりを誤りにしない', () {
    // 発話末では declination とは別に、さらにピッチが落ちる（final lowering）。
    // 文末の丁寧語尾（ครับ / ค่ะ）は必ずこの位置に来るので、見込んでおかないと
    // **末尾の語だけが毎回弾かれる**。
    for (final extra in [0.0, 0.2, 0.5]) {
      test('末尾がお手本より $extra ぶん低くても通る', () {
        final result = analyzePronunciation(
          f0Hz: synthesizeF0(
            tones: _tones,
            finalLowering: kFinalLoweringRange + extra,
          ),
          tones: _tones,
        );
        final last = result.syllables.last;
        expect(last.verdict, ToneVerdict.correct, reason: _detail(last));
      });
    }
  });

  group('短母音・死音節は形を要求しない', () {
    // 短い音節では声調の動きを出しきる時間がない（tonal undershoot）。
    // 上昇声を平坦に言っても、入り方が合っていれば通す。
    test('上昇声を平坦に発音しても、短い音節なら通る', () {
      final result = analyzePronunciation(
        // 上昇声の音節を中平声で発音した＝上がりきらなかった状態。
        f0Hz: synthesizeF0(tones: _tones, substitutions: {3: ThaiTone.mid}),
        tones: _tones,
        shortSyllables: List.generate(_tones.length, (i) => i == 3),
      );
      expect(result.syllables[3].verdict, ToneVerdict.correct);
    });

    test('短くても形が出ていれば、直前の誤りに巻き込まれない', () {
      // 短さが免除するのは「形を要求すること」であって、出せた形を
      // 捨てる理由にはならない。
      final short = List.generate(_tones.length, (i) => i == 1);
      // 長さは変えない（短母音でも生音節なら極端には縮まない）。
      final result = analyzePronunciation(
        // 音節1（下降声）は正しく発音し、その直前だけを誤る。
        f0Hz: synthesizeF0(
          tones: _tones,
          substitutions: {0: ThaiTone.high},
          shortSyllables: short,
        ),
        tones: _tones,
        shortSyllables: short,
      );
      final score = result.syllables[1];
      expect(score.verdict, ToneVerdict.correct, reason: _detail(score));
    });

    test('長い音節なら同じ発音は通らない', () {
      // 短いと申告しない限り、形は要求する。
      final result = analyzePronunciation(
        f0Hz: synthesizeF0(tones: _tones, substitutions: {3: ThaiTone.mid}),
        tones: _tones,
      );
      expect(result.syllables[3].verdict, isNot(ToneVerdict.correct));
    });
  });

  group('動きの大きさは問わない', () {
    for (final scale in [0.7, 0.6, 0.4]) {
      test('下降声の振れ幅が $scale 倍でも通る', () {
        // お手本ほど大きく動けない発音。向きが同じなら合格にする。
        final result = analyzePronunciation(
          f0Hz: synthesizeF0(tones: _tones, contourScaleBySyllable: {1: scale}),
          tones: _tones,
        );
        expect(result.syllables[1].verdict, ToneVerdict.correct);
      });

      test('上昇声の振れ幅が $scale 倍でも通る', () {
        final result = analyzePronunciation(
          f0Hz: synthesizeF0(tones: _tones, contourScaleBySyllable: {3: scale}),
          tones: _tones,
        );
        expect(result.syllables[3].verdict, ToneVerdict.correct);
      });
    }
  });

  group('直前の誤りに巻き込まれない', () {
    // 入り方は直前の終わり際からの段差なので、**直前が誤ると自分の入り方も
    // 崩れる**。ただし向きしか見ないので、崩れ方が向きを変えるほどでなければ残る。
    test('直前が誤っていても、自身の形と入り方の向きが合っていれば通る', () {
      final result = analyzePronunciation(
        // 音節1（下降声）を中平声で発音し、続く音節2は正しく発音する。
        f0Hz: synthesizeF0(tones: _tones, substitutions: {1: ThaiTone.mid}),
        tones: _tones,
      );
      // 直前が中平声で終わると音節2への入り方が -0.81（お手本は -0.28）に
      // なるが、どちらも「下がって入る」なので向きは合う。
      final score = result.syllables[2];
      expect(score.verdict, isNot(ToneVerdict.wrong), reason: _detail(score));
    });

    test('直前が誤っていても、誤った音節そのものは弾かれる', () {
      final result = analyzePronunciation(
        f0Hz: synthesizeF0(tones: _tones, substitutions: {1: ThaiTone.rising}),
        tones: _tones,
      );
      expect(result.syllables[1].verdict, isNot(ToneVerdict.correct));
      final score = result.syllables[2];
      expect(score.verdict, ToneVerdict.correct, reason: _detail(score));
    });
  });

  group('短い音節はお手本でも短く置く', () {
    // お手本の点数は、そのままお手本側の時間の割り当てになる。全音節を等分に
    // すると、実際に短い音節の境界が DTW の帯（対角線から6%）に張り付いて動けず、
    // 隣の音節がフレームを飲み込む。実機で、10フレームの音節の境界が
    // 帯の限界にぴったり止まり、その2音節だけが誤判定になった。
    final short = List.generate(_tones.length, (i) => i == 1 || i == 4);
    final points = [
      for (final isShort in short)
        syllablePointsFor(shortVowel: isShort, dead: isShort),
    ];

    test('実際に短く発音された音節が並んでも全部通る', () {
      final result = analyzePronunciation(
        f0Hz: synthesizeF0(
          tones: _tones,
          shortSyllables: short,
          syllablePoints: points,
        ),
        tones: _tones,
        shortSyllables: short,
        syllablePoints: points,
      );
      for (var i = 0; i < _tones.length; i++) {
        final score = result.syllables[i];
        expect(
          score.verdict,
          ToneVerdict.correct,
          reason: '音節$i (${_tones[i].name}) '
              'n=${score.queryValues.length} ${_detail(score)}',
        );
      }
    });

    test('短い音節がフレームを奪われていない', () {
      // 割り当てられたフレーム数が、実際の長さの比（0.6倍）から大きく
      // 外れていないこと。奪われると高さも形も別の音節のものになる。
      final result = analyzePronunciation(
        f0Hz: synthesizeF0(
          tones: _tones,
          shortSyllables: short,
          syllablePoints: points,
        ),
        tones: _tones,
        shortSyllables: short,
        syllablePoints: points,
      );
      for (var i = 0; i < _tones.length; i++) {
        final expected = short[i] ? 30 * 0.6 : 30.0;
        expect(
          result.syllables[i].queryValues.length,
          closeTo(expected, expected * 0.35),
          reason: '音節$i',
        );
      }
    });
  });

  group('文頭は形だけで見る', () {
    // 直前が無いので入り方が測れない。カーブの形だけで判断する。
    test('正しく発音していれば通る', () {
      final score = _scoreOf(const {}, 0);
      expect(score.queryStep, 0);
      expect(score.referenceStep, 0);
      expect(score.verdict, ToneVerdict.correct);
    });

    test('形が食い違えば通らない', () {
      expect(
        _scoreOf({0: ThaiTone.rising}, 0).verdict,
        isNot(ToneVerdict.correct),
      );
    });

    test('根拠が形だけのときは wrong にしない', () {
      // 手がかりが1つしか無い音節を、その1つだけで断定してはいけない。
      expect(_scoreOf({0: ThaiTone.high}, 0).verdict, ToneVerdict.close);
    });
  });

  group('高平声の上げそこねを罰しすぎない', () {
    // 高平声は形が使えない（平らな3声調）ので入り方だけが頼りで、しかも実際の
    // 発話で最も上げそこねやすい。とくに**下降声の直後**は低く終わった位置から
    // 入るので上がりきらない。実機で、お手本より 0.75〜1.44 低く出ている。
    //
    // 上げ幅は採点しないので、上がってさえいれば通る。
    const fallHigh = [
      ThaiTone.mid,
      ThaiTone.falling,
      ThaiTone.high,
      ThaiTone.low,
      ThaiTone.rising,
      ThaiTone.mid,
    ];

    ToneVerdict verdictOf(List<ThaiTone> tones, double drop) =>
        analyzePronunciation(
          f0Hz: synthesizeF0(
            tones: tones,
            levelOffsetBySyllable: {2: -drop},
          ),
          tones: tones,
        ).syllables[2].verdict;

    test('下降声の直後の上げそこねを通す', () {
      for (final drop in [0.2, 0.4, 0.6, 0.7, 1.0]) {
        expect(verdictOf(fallHigh, drop), ToneVerdict.correct,
            reason: '下げ幅 $drop');
      }
    });
  });

  group('見逃すことを受け入れている取り違え', () {
    // **高さも動きの大きさも採点しない**と決めた代償。判定を厳しくすると
    // 正しい発話まで巻き込むため、意図してこの側に倒している。

    test('中平→低平 は通る（どちらも平らで、入り方の向きも同じ）', () {
      expect(_scoreOf({0: ThaiTone.low}, 0).verdict, ToneVerdict.correct);
    });

    test('末尾の 中平→高平 は通る（文末はどのみち下がって入る）', () {
      // 文末は final lowering で大きく下がるので、入り方の向きでは分けられない。
      // 直前が巻き添えで correct を外し、基準が信用できない扱いになるため、
      // 向きの一致だけが残って通る。
      expect(_scoreOf({5: ThaiTone.high}, 5).verdict, ToneVerdict.correct);
    });

    test('低平→中平 も通る（同じ最小対立の逆向き）', () {
      // 5声調で最も差が小さい対立。どちらも平らで、入り方の向きも変わらない。
      expect(_scoreOf({2: ThaiTone.mid}, 2).verdict, ToneVerdict.correct);
    });

    test('末尾の 中平→低平 は通る（同じ最小対立）', () {
      expect(_scoreOf({5: ThaiTone.low}, 5).verdict, ToneVerdict.correct);
    });

    test('下降→高平 は通る（形が部分的に重なる）', () {
      // 高平声は上がってから最後に落ちるので、下降声と形が重なる（相関 0.65）。
      expect(_scoreOf({1: ThaiTone.high}, 1).verdict, ToneVerdict.correct);
    });
  });
}
