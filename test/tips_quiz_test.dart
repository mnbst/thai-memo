import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/core/constants/tips_quiz.dart';
import 'package:thai_memo/data/models/quiz_question.dart';
import 'package:thai_memo/l10n/app_localizations.dart';

QuizQuestion _sentenceQuestion(int i) => QuizQuestion(
      sentenceId: 's$i',
      thaiText: '',
      blankText: '',
      correctAnswer: 'w$i',
      choices: const ['a', 'b', 'c', 'd'],
      pronunciation: '',
      explanation: '',
    );

void main() {
  test('id は重ならない', () {
    final ids = tipQuizItems.map((i) => i.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids.length, 34);
  });

  test('3言語とも選択肢の数が同じで、空の文言が無い', () {
    final ja = lookupL10n(const Locale('ja'));
    for (final code in ['ja', 'en', 'ko']) {
      final l10n = lookupL10n(Locale(code));
      for (final item in tipQuizItems) {
        final choices = item.choices(l10n);
        expect(choices.length, item.choices(ja).length,
            reason: '$code ${item.id}');
        expect(choices.length, greaterThanOrEqualTo(2), reason: item.id);
        expect(choices.every((c) => c.text.isNotEmpty), isTrue,
            reason: '$code ${item.id}');
        expect(choices.map((c) => c.text).toSet().length, choices.length,
            reason: '$code ${item.id} 選択肢が重複');
        expect(item.question(l10n).trim(), isNotEmpty,
            reason: '$code ${item.id}');
        expect(item.explanation(l10n).trim(), isNotEmpty,
            reason: '$code ${item.id}');
      }
    }
  });

  test('語順の問題は語順ガイドの例文どおり', () {
    final ja = lookupL10n(const Locale('ja'));
    String correct(String id) =>
        tipQuizItemById(id)!.choices(ja).first.text;
    expect(correct('W1'), 'บ้านใหญ่');
    expect(correct('W3'), 'ผมกินข้าว');
    expect(correct('W5'), 'แมวสองตัวนี้');
    expect(correct('W6'), 'ผมไม่กินเผ็ด');
    expect(correct('W7'), 'ไปไม่ได้');
    expect(tipQuizItemById('W7')!.choices(ja)[1].text, 'ไม่ได้ไป');
    expect(correct('W8'), 'คุณกินอะไร');
    expect(correct('W9'), 'กินข้าวแล้ว');
    expect(correct('W10'), 'ผมไปกับเพื่อน');
    expect(correct('W12'), 'อาหารนี้อร่อยมาก');
    expect(correct('W13'), 'วันนี้ร้อนกว่าเมื่อวาน');
    expect(correct('W14'), 'ผมอยากกินส้มตำ');
    expect(correct('W16'), 'ร้านที่ผมชอบ');
    expect(correct('W17'), 'กินไหมคะ');
  });

  group('TipQuizPicker.fill', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('5問あれば足さない', () async {
      final qs = List.generate(5, _sentenceQuestion);
      expect(await TipQuizPicker.fill(qs, 5), same(qs));
    });

    test('足りない分だけコツ問題を足し、正解は "0"', () async {
      final qs = List.generate(2, _sentenceQuestion);
      final filled = await TipQuizPicker.fill(qs, 5, random: Random(1));
      expect(filled.length, 5);
      final tips = filled.skip(2).toList();
      expect(tips.every((q) => q.isTip && q.correctChoice == '0'), isTrue);
      expect(tips.every((q) => q.choices.contains('0')), isTrue);
    });

    test('出したものは全部出し切るまで繰り返さない', () async {
      final seen = <String>[];
      for (var i = 0; i < 17; i++) {
        final filled =
            await TipQuizPicker.fill([_sentenceQuestion(0)], 3);
        seen.addAll(filled.skip(1).map((q) => q.tipId));
      }
      // 34問を2問ずつ17回で、ちょうど一巡。
      expect(seen.toSet().length, 34);
      final next = await TipQuizPicker.fill([_sentenceQuestion(0)], 3);
      expect(next.skip(1).map((q) => q.tipId).toSet().length, 2);
    });

    test('保存と復元で tip_id が残る', () {
      final q = TipQuizPicker.toQuestion(tipQuizItems.first, Random(0));
      final restored = QuizQuestion.fromJson(q.toJson());
      expect(restored.isTip, isTrue);
      expect(restored.tipId, q.tipId);
      expect(restored.choices, q.choices);
    });
  });
}
