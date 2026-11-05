import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/thai_tone_analyzer.dart';
import 'package:thai_memo/data/models/quiz_question.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/widgets/spelling_breakdown_view.dart';
import 'package:thai_memo/presentation/widgets/tone_shift_table.dart';

void main() {
  group('ToneShiftTable.isException', () {
    bool check(ConsonantClass klass, ThaiTone tone, {bool? short}) =>
        ToneShiftTable.isException(
          consonantClass: klass,
          toneMark: ToneMark.none,
          syllableType: SyllableType.dead,
          tone: tone,
          hasShortVowel: short,
        );

    test('表の行と声調が違えば例外', () {
      expect(check(ConsonantClass.middle, ThaiTone.falling), isTrue);
    });

    test('表の行と同じなら例外でない', () {
      expect(check(ConsonantClass.middle, ThaiTone.low), isFalse);
    });

    test('母音の長短が不明なら、どちらかの行に合えば例外でない', () {
      expect(check(ConsonantClass.low, ThaiTone.high), isFalse);
      expect(check(ConsonantClass.low, ThaiTone.falling), isFalse);
    });

    test('階級や声調が不明なら判断しない', () {
      expect(check(ConsonantClass.unknown, ThaiTone.falling), isFalse);
      expect(check(ConsonantClass.middle, ThaiTone.unknown), isFalse);
    });
  });

  group('SpellingToneRuleTile', () {
    Future<void> pump(WidgetTester tester, String tone) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SpellingToneRuleTile(
              parts: [SpellingPart(role: 'tone', tone: tone)],
              rule: const SpellingToneRule(
                consonantClass: 'mid',
                syllable: 'dead',
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
    }

    ToneMark? highlighted(WidgetTester tester) =>
        tester.widget<ToneShiftTable>(find.byType(ToneShiftTable)).toneMark;

    testWidgets('規則どおりの語は表の行を強調する', (tester) async {
      await pump(tester, 'low');
      expect(find.text('（例外）'), findsNothing);
      expect(highlighted(tester), ToneMark.none);
    });

    testWidgets('規則と違う語は例外と添え、表の行を強調しない', (tester) async {
      await pump(tester, 'falling');
      expect(find.text('（例外）'), findsOneWidget);
      expect(highlighted(tester), isNull);
    });
  });
}
