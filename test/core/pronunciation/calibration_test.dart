// 閾値が「正しい発話を通し、声調の取り違えを弾く」範囲に収まっていることを守る。
//
// 判定が厳しすぎる発音練習は続かないので閾値は緩めたいが、緩めすぎると
// 声調の取り違えが「合っている」に化けて機能の中身が無くなる。
// その両側をこのテストで固定する。
//
// 採点は「その音節の中でのピッチの動き（形）」と「**直前の**音節との段差
// （つながり）」の2つ。声域内の絶対的な高さは、比べる相手がいない文頭を除いて
// 採点しない。高さは話者・場面・文中の位置で素直に動くので、正しく発音していても
// 弾かれてしまう。
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

void main() {
  group('正しい発話は余裕をもって通る', () {
    test('どの音節も閾値の内側に収まる', () {
      for (var i = 0; i < _tones.length; i++) {
        final score = _scoreOf(const {}, i);
        expect(
          score.shapeError,
          lessThan(kShapeErrorThreshold),
          reason: '音節$i (${_tones[i].name}) の形状誤差',
        );
        expect(
          score.transitionError,
          lessThan(kTransitionErrorThreshold),
          reason: '音節$i (${_tones[i].name}) のつながり誤差',
        );
        expect(score.verdict, ToneVerdict.correct);
      }
    });

    test('つながりの誤差は合格ラインから十分離れている', () {
      // 実際の人の声は合成音声よりばらつくので、余裕が要る。
      // 無声子音を90msまで入れた条件を含めて、正しい発話は最大 0.207。
      // 弾けている取り違えは最小 0.55 なので、間に十分な帯がある。
      for (var i = 0; i < _tones.length; i++) {
        expect(
          _scoreOf(const {}, i).transitionError,
          lessThan(0.25),
          reason: '音節$i (${_tones[i].name})',
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
            reason: '音節$i (${_tones[i].name}) '
                '(shape=${score.shapeError.toStringAsFixed(3)}, '
                'link=${score.transitionError.toStringAsFixed(3)})',
          );
        }
      });
    }
  });

  group('声調の取り違えは correct にならない', () {
    const cases = <String, (Map<int, ThaiTone>, int)>{
      '下降→上昇': ({1: ThaiTone.rising}, 1),
      '上昇→下降': ({3: ThaiTone.falling}, 3),
      '上昇→中平': ({3: ThaiTone.mid}, 3),
      '中平→下降': ({0: ThaiTone.falling}, 0),
      '中平→高平': ({0: ThaiTone.high}, 0),
      '高平→中平': ({4: ThaiTone.mid}, 4),
      '末尾の中平→高平': ({5: ThaiTone.high}, 5),
      '低平→高平': ({2: ThaiTone.high}, 2),
      '高平→低平': ({4: ThaiTone.low}, 4),
      '低平→中平': ({2: ThaiTone.mid}, 2),
      // 形が一致していても、高さの関係が崩れていれば通さない。
      // どちらも右上がりなので相関は 0.90 に達するが、高さは 1.17 ずれている。
      '上昇→高平': ({3: ThaiTone.high}, 3),
      '中平→上昇': ({0: ThaiTone.rising}, 0),
      '下降→中平': ({1: ThaiTone.mid}, 1),
    };

    cases.forEach((label, params) {
      test(label, () {
        final score = _scoreOf(params.$1, params.$2);
        expect(
          score.verdict,
          isNot(ToneVerdict.correct),
          reason: '$label が見逃されている '
              '(link=${score.transitionError.toStringAsFixed(3)})',
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
        expect(
          last.verdict,
          ToneVerdict.correct,
          reason: 'link=${last.transitionError.toStringAsFixed(3)}',
        );
      });
    }
  });

  group('短母音・死音節は形を要求しない', () {
    // 短い音節では声調の動きを出しきる時間がない（tonal undershoot）。
    // 上昇声を平坦に言っても、隣との高低差が合っていれば通す。
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
      expect(
        score.verdict,
        ToneVerdict.correct,
        reason: 'link=${score.transitionError.toStringAsFixed(3)} '
            'lvl=${score.levelError.toStringAsFixed(3)}',
      );
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

  group('カーブの形が合っていれば、ずれと振れ幅は問わない', () {
    for (final scale in [0.7, 0.6]) {
      test('下降声の振れ幅が $scale 倍でも通る', () {
        // お手本ほど大きく動けない発音。形が同じなら合格にする。
        final result = analyzePronunciation(
          f0Hz: synthesizeF0(
            tones: _tones,
            contourScaleBySyllable: {1: scale},
          ),
          tones: _tones,
        );
        expect(result.syllables[1].verdict, ToneVerdict.correct);
      });

      test('上昇声の振れ幅が $scale 倍でも通る', () {
        final result = analyzePronunciation(
          f0Hz: synthesizeF0(
            tones: _tones,
            contourScaleBySyllable: {3: scale},
          ),
          tones: _tones,
        );
        expect(result.syllables[3].verdict, ToneVerdict.correct);
      });
    }
  });

  group('直前の誤りに巻き込まれない', () {
    // つながりは直前との段差だけを見るので、**直前が誤ると自分の段差も崩れる**。
    // そのとき自身の高さがほぼ一致していて形も合っていれば通す。
    test('直前が誤っていても、自身の高さと形が合っていれば通る', () {
      final result = analyzePronunciation(
        // 音節1（下降声）を中平声で発音し、続く音節2は正しく発音する。
        f0Hz: synthesizeF0(tones: _tones, substitutions: {1: ThaiTone.mid}),
        tones: _tones,
      );
      final score = result.syllables[2];
      expect(
        score.verdict,
        ToneVerdict.correct,
        reason: 'link=${score.transitionError.toStringAsFixed(3)} '
            'lvl=${score.levelError.toStringAsFixed(3)}',
      );
    });

    test('直前が誤っていれば、自身の高さの許容を広げる', () {
      // 段差が崩れていても、原因がどちらの音節かは分からない。実機で、高平声を
      // 上げそこねた次の低平声が段差 1.501 で誤りにされた（その音節自身は
      // 高さのずれ 0.01）。ここでは 0.414 まで離れても通す。
      final result = analyzePronunciation(
        f0Hz: synthesizeF0(tones: _tones, substitutions: {1: ThaiTone.rising}),
        tones: _tones,
      );
      final score = result.syllables[2];
      expect(
        score.verdict,
        ToneVerdict.correct,
        reason: 'link=${score.transitionError.toStringAsFixed(3)} '
            'lvl=${score.levelError.toStringAsFixed(3)}',
      );
      // 誤った音節そのものは、その直前が正しいので通常どおり弾かれる。
      expect(result.syllables[1].verdict, isNot(ToneVerdict.correct));
    });

    test('自身の高さが外れていれば、逃げ道にはならない', () {
      // 高さがほぼ一致しているときだけの逃げ道。緩めると取り違えが素通りする。
      expect(
        _scoreOf({2: ThaiTone.high}, 2).verdict,
        isNot(ToneVerdict.correct),
      );
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
              'n=${score.queryValues.length} '
              'link=${score.transitionError.toStringAsFixed(3)} '
              'lvl=${score.levelError.toStringAsFixed(3)}',
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

  group('文頭はピッチのグラフだけで見る', () {
    // 直前が無いので段差が測れない。カーブの形と、声域内の高さそのもので判断する。
    test('正しく発音していれば通る', () {
      final score = _scoreOf(const {}, 0);
      expect(score.transitionError, 0);
      expect(score.verdict, ToneVerdict.correct);
    });

    test('平らな声調を大きく動かせば通らない', () {
      // 中平声を上昇声で発音した。高さのずれは 0.19 と小さいが、形が食い違う。
      expect(_scoreOf({0: ThaiTone.rising}, 0).verdict,
          isNot(ToneVerdict.correct));
    });

    test('高さが声域の反対側に出れば通らない', () {
      expect(_scoreOf({0: ThaiTone.high}, 0).verdict, ToneVerdict.wrong);
    });
  });

  group('見逃すことを受け入れている取り違え', () {
    // 判定を厳しくすると正しい発話まで巻き込むため、**意図してこの側に倒している**。

    test('中平→低平 は通る（つながりの差が小さすぎる）', () {
      // 5声調で最も差が小さい対立。つながりの誤差は 0.355 で、正しい発話の
      // 上限（無声子音を長く取ったときの 0.246）とほとんど接している。
      expect(_scoreOf({0: ThaiTone.low}, 0).verdict, ToneVerdict.correct);
    });

    test('末尾の 中平→低平 は通る（同じ最小対立）', () {
      // 文末はもともと下がる（final lowering）ので、低く言われても
      // 「下がりが少し深い」との区別がつかない。つながりの差は 0.294。
      expect(_scoreOf({5: ThaiTone.low}, 5).verdict, ToneVerdict.correct);
    });

    test('下降→高平 は通る（高さの関係が偶然そろう）', () {
      // 高平声は上がってから最後に落ちるので、下降声と部分的に形が重なる
      // （相関 0.77）。この文では高さの関係も 0.074 しか変わらず、手がかりが無い。
      expect(_scoreOf({1: ThaiTone.high}, 1).verdict, ToneVerdict.correct);
    });
  });
}
