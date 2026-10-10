import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/data/models/quiz_question.dart';

void main() {
  group('QuizQuestion.fromJson', () {
    test('meaning_choice は意味を正解選択肢にする', () {
      final json = _baseJson()
        ..['quiz_format'] = QuizQuestion.meaningChoiceFormat
        ..['correct_answer_meaning'] = '食べる'
        ..['choices'] = ['食べる', '速い', '家', '美しい'];

      final q = QuizQuestion.fromJson(json);

      expect(q.isMeaningChoice, isTrue);
      expect(q.correctAnswer, 'กิน');
      expect(q.correctChoice, '食べる');
      expect(q.toJson()['quiz_format'], QuizQuestion.meaningChoiceFormat);
    });

    test('spelling_choice は正解の分解と書く順の字を読む', () {
      final json = _baseJson()
        ..['quiz_format'] = QuizQuestion.spellingChoiceFormat
        ..['choices'] = ['กิน', 'กีน', 'กิม', 'จิน']
        ..['spelling_parts'] = [
          {'role': 'onset', 'text': 'ก', 'sound': 'k'},
          {'role': 'vowel', 'text': 'ิ', 'sound': 'i'},
          {'role': 'coda', 'text': 'น', 'sound': 'n'},
          {'role': 'tone', 'tone': 'mid'},
        ]
        ..['spelling_glyphs'] = [
          {'role': 'onset', 'text': 'ก'},
          {'role': 'vowel', 'text': 'ิ'},
          {'role': 'coda', 'text': 'น'},
        ];

      final q = QuizQuestion.fromJson(json);

      expect(q.isSpellingChoice, isTrue);
      expect(q.correctChoice, 'กิน');
      expect(q.spellingParts.length, 4);
      expect(q.spellingParts[3].tone, 'mid');
      // 母音記号は土台の「-」を添えて単体でも読めるようにする。
      expect(q.spellingParts[1].displayText, '-ิ');
      expect(q.spellingParts[0].displayText, 'ก');
      // 書く順につなぐと元の綴りに戻る。
      expect(q.spellingGlyphs.map((g) => g.text).join(), 'กิน');
      expect(q.toJson()['spelling_glyphs'], isA<List>());
    });

    test('quiz_format のない旧問題は穴埋めとして読む', () {
      final q = QuizQuestion.fromJson(_baseJson());

      expect(q.isMeaningChoice, isFalse);
      expect(q.correctChoice, q.correctAnswer);
    });

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

  group('並び替え', () {
    QuizQuestion wordOrder() => QuizQuestion.fromJson(_baseJson()
      ..['quiz_format'] = QuizQuestion.wordOrderFormat
      ..['choices'] = ['ทะเล', 'อยาก', 'ผม', 'ไป']
      ..['word_order_answer'] = ['ผม', 'อยาก', 'ไป', 'ทะเล']
      ..['word_order_suffix'] = 'ครับ'
      ..['word_order_show_pronunciation'] = true);

    test('JSONを往復しても並び替えの項目が残る', () {
      final q = QuizQuestion.fromJson(wordOrder().toJson());

      expect(q.isWordOrder, isTrue);
      expect(q.wordOrderAnswer, ['ผม', 'อยาก', 'ไป', 'ทะเล']);
      expect(q.wordOrderPrefix, '');
      expect(q.wordOrderSuffix, 'ครับ');
      expect(q.wordOrderShowPronunciation, isTrue);
    });

    test('並びの正誤は語の文字列で判定する', () {
      final q = wordOrder();

      expect(q.isWordOrderCorrect([2, 1, 3, 0]), isTrue);
      expect(q.isWordOrderCorrect([1, 2, 3, 0]), isFalse);
      expect(q.isWordOrderCorrect([2, 1, 3]), isFalse);
    });

    test('回答の並びは int に詰めて戻せる', () {
      for (final order in [
        [0, 1, 2, 3],
        [3, 2, 1, 0],
        [2, 1, 3, 0],
      ]) {
        final encoded = QuizQuestion.encodeWordOrder(order);
        expect(QuizQuestion.decodeWordOrder(encoded, 4), order);
      }
      // 添字が重なる・桁があふれる値は並びに戻さない
      expect(QuizQuestion.decodeWordOrder(0, 4), isNull);
      expect(QuizQuestion.decodeWordOrder(256, 4), isNull);
      expect(QuizQuestion.decodeWordOrder(-1, 4), isNull);
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
