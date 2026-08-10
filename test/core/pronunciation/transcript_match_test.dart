import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/pronunciation/transcript_match.dart';

void main() {
  group('matchTranscript', () {
    test('例文どおりに認識されれば全語 recognized', () {
      final results = matchTranscript(
        expectedWords: ['ผม', 'ชอบ', 'อาหาร', 'ไทย'],
        transcript: 'ผมชอบอาหารไทย',
      );
      expect(results, everyElement(WordRecognition.recognized));
    });

    test('認識器が入れた空白は無視する', () {
      // タイ語は語間に空白を置かないが、認識器は区切りを入れてくることがある。
      final results = matchTranscript(
        expectedWords: ['ผม', 'ชอบ', 'อาหาร'],
        transcript: 'ผม ชอบ อาหาร',
      );
      expect(results, everyElement(WordRecognition.recognized));
    });

    test('句読点は無視する', () {
      final results = matchTranscript(
        expectedWords: ['สวัสดี', 'ครับ'],
        transcript: 'สวัสดี, ครับ!',
      );
      expect(results, everyElement(WordRecognition.recognized));
    });

    test('SARA AM の分解形を同じ語として扱う', () {
      // ทำ は1文字(U+0E33)でも2文字(U+0E4D U+0E32)でも書ける。見た目は同じだが
      // Unicode の正規化では統一されず、認識器は分解形を返すことがある。
      // 揃えないと ทำ・น้ำ・คำ のような頻出語がすべて誤検出になる。
      const composed = 'ทำ';
      const decomposed = 'ทํา';
      expect(composed == decomposed, isFalse, reason: '前提: 文字列としては別物');

      final results = matchTranscript(
        expectedWords: [composed, 'งาน'],
        transcript: '$decomposed' 'งาน',
      );
      expect(results, everyElement(WordRecognition.recognized));
    });

    test('落ちた語だけが missing になる', () {
      final results = matchTranscript(
        expectedWords: ['ผม', 'ชอบ', 'อาหาร', 'ไทย'],
        transcript: 'ผมอาหารไทย',
      );
      expect(results, [
        WordRecognition.recognized,
        WordRecognition.missing,
        WordRecognition.recognized,
        WordRecognition.recognized,
      ]);
    });

    test('1語聞き取れなくても以降が巻き添えにならない', () {
      // カーソルを進めない設計の確認。ここが崩れると、最初の1語を外しただけで
      // 文全体が真っ赤になり、どこが悪いのか分からなくなる。
      final results = matchTranscript(
        expectedWords: ['กาว', 'ชอบ', 'อาหาร'],
        transcript: 'ชอบอาหาร',
      );
      expect(results, [
        WordRecognition.missing,
        WordRecognition.recognized,
        WordRecognition.recognized,
      ]);
    });

    test('語順が入れ替わっていれば後ろの語が missing', () {
      final results = matchTranscript(
        expectedWords: ['ชอบ', 'ผม'],
        transcript: 'ผมชอบ',
      );
      expect(results, [
        WordRecognition.recognized,
        WordRecognition.missing,
      ]);
    });

    test('同じ語が2回出ても2回ぶん数える', () {
      final results = matchTranscript(
        expectedWords: ['มา', 'มา'],
        transcript: 'มามา',
      );
      expect(results, everyElement(WordRecognition.recognized));
    });

    test('同じ語が1回しか認識されなければ2つ目は missing', () {
      final results = matchTranscript(
        expectedWords: ['มา', 'มา'],
        transcript: 'มา',
      );
      expect(results, [
        WordRecognition.recognized,
        WordRecognition.missing,
      ]);
    });

    test('認識結果が空なら全語 missing', () {
      final results = matchTranscript(
        expectedWords: ['ผม', 'ชอบ'],
        transcript: '',
      );
      expect(results, everyElement(WordRecognition.missing));
    });

    test('非対応端末では unavailable にする', () {
      // 判定できないことと、判定して駄目だったことを混同させない。
      final results = matchTranscript(
        expectedWords: ['ผม', 'ชอบ'],
        transcript: '',
        available: false,
      );
      expect(results, everyElement(WordRecognition.unavailable));
    });
  });

  group('recognizedRatio', () {
    test('判定できた語のうちの認識割合を返す', () {
      expect(
        recognizedRatio([
          WordRecognition.recognized,
          WordRecognition.recognized,
          WordRecognition.missing,
          WordRecognition.missing,
        ]),
        0.5,
      );
    });

    test('unavailable は分母に入れない', () {
      expect(
        recognizedRatio([
          WordRecognition.recognized,
          WordRecognition.unavailable,
        ]),
        1.0,
      );
    });

    test('判定対象が無ければ null', () {
      expect(recognizedRatio([]), isNull);
      expect(recognizedRatio([WordRecognition.unavailable]), isNull);
    });
  });
}
