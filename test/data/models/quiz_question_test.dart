import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/data/models/quiz_question.dart';

void main() {
  group('QuizQuestion.fromJson', () {
    test('dummy_reasons あり', () {
      final json = _baseJson()
        ..['dummy_reasons'] = ['เร็ว は副詞のため代入不可', 'บ้าน は名詞/場所', 'สวย は形容詞'];

      final q = QuizQuestion.fromJson(json);

      expect(q.dummyReasons, ['เร็ว は副詞のため代入不可', 'บ้าน は名詞/場所', 'สวย は形容詞']);
    });

    test('dummy_reasons なし（旧データ）→ 空リスト', () {
      final q = QuizQuestion.fromJson(_baseJson());

      expect(q.dummyReasons, isEmpty);
    });

    test('dummy_reasons が null → 空リスト', () {
      final json = _baseJson()..['dummy_reasons'] = null;

      final q = QuizQuestion.fromJson(json);

      expect(q.dummyReasons, isEmpty);
    });
  });

  group('QuizQuestion.toJson', () {
    test('dummy_reasons を含む', () {
      const q = QuizQuestion(
        sentenceId: 'id1',
        thaiText: 'ผมกินข้าว',
        blankText: 'ผม___ข้าว',
        correctAnswer: 'กิน',
        choices: ['กิน', 'เร็ว', 'บ้าน', 'สวย'],
        pronunciation: 'gin',
        explanation: '「食べる」という動詞',
        dummyReasons: ['เร็ว は副詞', 'บ้าน は名詞', 'สวย は形容詞'],
      );

      final json = q.toJson();

      expect(json['dummy_reasons'], ['เร็ว は副詞', 'บ้าน は名詞', 'สวย は形容詞']);
    });

    test('dummyReasons 未指定時は空リストを出力', () {
      const q = QuizQuestion(
        sentenceId: 'id1',
        thaiText: 'ผมกินข้าว',
        blankText: 'ผม___ข้าว',
        correctAnswer: 'กิน',
        choices: ['กิน', 'เร็ว', 'บ้าน', 'สวย'],
        pronunciation: 'gin',
        explanation: '「食べる」という動詞',
      );

      final json = q.toJson();

      expect(json['dummy_reasons'], isEmpty);
    });

    test('fromJson → toJson ラウンドトリップ', () {
      final original = _baseJson()
        ..['dummy_reasons'] = ['เร็ว は副詞', 'บ้าน は名詞'];

      final json = QuizQuestion.fromJson(original).toJson();

      expect(json['dummy_reasons'], original['dummy_reasons']);
      expect(json['correct_answer'], original['correct_answer']);
    });

    test('旧データ（dummy_reasons なし）→ toJson → fromJson → 空リスト', () {
      final oldJson = _baseJson(); // dummy_reasons キーなし

      final roundtripped = QuizQuestion.fromJson(
        QuizQuestion.fromJson(oldJson).toJson(),
      );

      expect(roundtripped.dummyReasons, isEmpty);
    });
  });
}

Map<String, dynamic> _baseJson() => {
      'sentence_id': 'id1',
      'thai_text': 'ผมกินข้าว',
      'blank_text': 'ผม___ข้าว',
      'correct_answer': 'กิน',
      'choices': ['กิน', 'เร็ว', 'บ้าน', 'สวย'],
      'pronunciation': 'gin',
      'explanation': '「食べる」という動詞',
      'srs_interval': 1,
      'japanese_translation': '私はご飯を食べる',
      'sentence_pronunciation': 'phom gin khao',
    };
