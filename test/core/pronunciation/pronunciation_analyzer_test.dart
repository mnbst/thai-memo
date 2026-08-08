import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/pronunciation/pronunciation_analyzer.dart';
import 'package:thai_memo/core/pronunciation/pronunciation_scorer.dart';
import 'package:thai_memo/core/pronunciation/speaker_range.dart';
import 'package:thai_memo/core/thai_tone_analyzer.dart';

import '../../helpers/f0_synthesizer.dart';

/// 5声調がひと通り混ざった音節列。実際の例文に近い構成。
const _tones = [
  ThaiTone.mid,
  ThaiTone.falling,
  ThaiTone.low,
  ThaiTone.rising,
  ThaiTone.high,
  ThaiTone.mid,
];

ToneVerdict _verdictAt(PronunciationResult result, int index) =>
    result.syllables[index].verdict;

void main() {
  group('正しく発音した場合', () {
    test('全音節が correct になる', () {
      final result = analyzePronunciation(
        f0Hz: synthesizeF0(tones: _tones),
        tones: _tones,
      );

      expect(result.isScored, isTrue);
      expect(
        result.syllables.map((s) => s.verdict),
        everyElement(ToneVerdict.correct),
      );
      expect(result.overallScore, 100);
    });

    test('声の高さが違っても判定は変わらない', () {
      // 声域が異なる2人が同じように発音した場合。正規化が効いていれば同じ結果になる。
      final low = analyzePronunciation(
        f0Hz: synthesizeF0(
          tones: _tones,
          medianSemitone: 38,
          halfRangeSemitone: 3,
        ),
        tones: _tones,
      );
      final high = analyzePronunciation(
        f0Hz: synthesizeF0(
          tones: _tones,
          medianSemitone: 55,
          halfRangeSemitone: 6,
        ),
        tones: _tones,
      );

      expect(low.overallScore, 100);
      expect(high.overallScore, 100);
    });

    test('話速が違っても判定は変わらない', () {
      final fast = analyzePronunciation(
        f0Hz: synthesizeF0(tones: _tones, framesPerSyllable: 15),
        tones: _tones,
      );
      final slow = analyzePronunciation(
        f0Hz: synthesizeF0(tones: _tones, framesPerSyllable: 60),
        tones: _tones,
      );

      expect(fast.overallScore, 100);
      expect(slow.overallScore, 100);
    });
  });

  group('声調を間違えた場合', () {
    test('下降声を上昇声で発音すると correct にならない', () {
      // 動きが逆になる誤り。形状誤差で捕まえる。
      final result = analyzePronunciation(
        f0Hz: synthesizeF0(
          tones: _tones,
          substitutions: {1: ThaiTone.rising},
        ),
        tones: _tones,
      );

      expect(_verdictAt(result, 1), isNot(ToneVerdict.correct));
      expect(result.overallScore, lessThan(100));
    });

    test('高平声を低平声で発音すると correct にならない', () {
      final result = analyzePronunciation(
        f0Hz: synthesizeF0(
          tones: _tones,
          substitutions: {4: ThaiTone.low},
        ),
        tones: _tones,
      );

      expect(_verdictAt(result, 4), isNot(ToneVerdict.correct));
    });

    test('間違えた音節以外は correct のまま残る', () {
      final result = analyzePronunciation(
        f0Hz: synthesizeF0(
          tones: _tones,
          substitutions: {1: ThaiTone.rising},
        ),
        tones: _tones,
      );

      // 誤りが文全体に波及して全部×になってしまうと、どこが悪いのか分からない。
      final correctCount = result.syllables
          .where((s) => s.verdict == ToneVerdict.correct)
          .length;
      expect(correctCount, greaterThanOrEqualTo(3));
    });
  });

  group('採点できない場合', () {
    test('音節が無ければ noSyllables', () {
      final result = analyzePronunciation(f0Hz: const [], tones: const []);
      expect(result.failure, PronunciationFailure.noSyllables);
      expect(result.isScored, isFalse);
    });

    test('音声が1フレームも届いていなければ captureFailed', () {
      // 収録経路の問題。「静かな場所でもう一度」と案内しても直らないので
      // tooQuiet と分けている。
      final result = analyzePronunciation(f0Hz: const [], tones: _tones);
      expect(result.failure, PronunciationFailure.captureFailed);
    });

    test('声が拾えていなければ tooQuiet', () {
      final result = analyzePronunciation(
        f0Hz: List<double?>.filled(200, null),
        tones: _tones,
      );
      expect(result.failure, PronunciationFailure.tooQuiet);
    });

    test('無声フレームが多すぎる録音は採点しない', () {
      final noisy = synthesizeF0(tones: _tones)
          .asMap()
          .entries
          // 4フレームに3つを欠測にする（有声率25%）。
          .map((e) => e.key % 4 == 0 ? e.value : null)
          .toList();

      final result = analyzePronunciation(f0Hz: noisy, tones: _tones);
      expect(result.failure, PronunciationFailure.tooQuiet);
    });

    test('抑揚が無い録音は声域が取れず、プロファイルも無ければ採点しない', () {
      final result = analyzePronunciation(
        f0Hz: synthesizeF0(tones: _tones, flatten: 0.05),
        tones: _tones,
      );
      expect(result.failure, PronunciationFailure.noSpeakerRange);
    });
  });

  group('声域プロファイル', () {
    test('今回の録音から声域が取れたときは fresh を返す', () {
      final result = analyzePronunciation(
        f0Hz: synthesizeF0(tones: _tones),
        tones: _tones,
      );
      expect(result.freshRange, isNotNull);
      expect(result.speakerRange, isNotNull);
    });

    test('声域が取れないときは蓄積プロファイルで代替し、fresh は返さない', () {
      final profile = SpeakerPitchProfile(
        range: const SpeakerRange(medianSemitone: 45, rangeSemitone: 6.4),
        sampleCount: 5,
      );

      final result = analyzePronunciation(
        f0Hz: synthesizeF0(tones: _tones, flatten: 0.05),
        tones: _tones,
        profile: profile,
      );

      expect(result.isScored, isTrue);
      expect(result.speakerRange, isNotNull);
      // 推定に失敗した回をプロファイルに書き戻すと誤差が積み上がる。
      expect(result.freshRange, isNull);
    });

    test('抑揚の無い発音は isMonotone が立つ', () {
      // 平坦に読むと中平声の音節だけが偶然一致し、点数は半分近くまで伸びる。
      // 点数だけでは「声調を付けずに読んだ」ことが伝わらないため、別に旗を立てる。
      final profile = SpeakerPitchProfile(
        range: const SpeakerRange(medianSemitone: 45, rangeSemitone: 6.4),
        sampleCount: 5,
      );

      final result = analyzePronunciation(
        f0Hz: synthesizeF0(tones: _tones, flatten: 0.05),
        tones: _tones,
        profile: profile,
      );

      expect(result.isScored, isTrue);
      expect(result.isMonotone, isTrue);
    });

    test('きちんと抑揚を付けた発音では isMonotone が立たない', () {
      final result = analyzePronunciation(
        f0Hz: synthesizeF0(tones: _tones),
        tones: _tones,
      );
      expect(result.isMonotone, isFalse);
    });
  });

  group('SpeakerPitchProfile.merge', () {
    test('移動平均で新しい推定を取り込む', () {
      const initial = SpeakerPitchProfile(
        range: SpeakerRange(medianSemitone: 40, rangeSemitone: 6),
        sampleCount: 1,
      );
      final merged = initial.merge(
        const SpeakerRange(medianSemitone: 44, rangeSemitone: 8),
      );

      expect(merged.range.medianSemitone, closeTo(42, 1e-9));
      expect(merged.range.rangeSemitone, closeTo(7, 1e-9));
      expect(merged.sampleCount, 2);
    });

    test('試行数は上限で頭打ちになる', () {
      var profile = const SpeakerPitchProfile(
        range: SpeakerRange(medianSemitone: 40, rangeSemitone: 6),
        sampleCount: kProfileMaxSamples,
      );
      profile = profile.merge(
        const SpeakerRange(medianSemitone: 50, rangeSemitone: 10),
      );
      expect(profile.sampleCount, kProfileMaxSamples);
    });
  });
}
