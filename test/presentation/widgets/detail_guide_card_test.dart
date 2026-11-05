import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/analytics_provider.dart';
import 'package:thai_memo/presentation/widgets/detail_guide_card.dart';
import 'package:thai_memo/presentation/widgets/first_set_steps.dart';
import 'package:thai_memo/services/analytics_service.dart';

class _NoopAnalytics extends Fake implements AnalyticsService {
  @override
  Future<void> logCoachMark(
      {required String id, required String action}) async {}
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    Set<FirstSetStep> done = const {},
    VoidCallback? onBackToLearn,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsServiceProvider.overrideWithValue(_NoopAnalytics()),
          firstSentenceIdProvider
              .overrideWith((ref) => FirstSentenceIdController.fixed('s1')),
          firstStepsDoneProvider
              .overrideWith((ref) => FirstStepsDoneController.fixed(done)),
        ],
        child: MaterialApp(
          locale: const Locale('ja'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: DetailGuideCard(
                sentenceId: 's1',
                onBackToLearn: onBackToLearn,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  const label = '学習に戻って確認クイズを解く';

  testWidgets('学習タブから開いてクイズが未完了なら戻る導線を出す', (tester) async {
    var tapped = false;
    await pump(tester, onBackToLearn: () => tapped = true);

    await tester.tap(find.text(label));
    expect(tapped, isTrue);
  });

  testWidgets('クイズを解いた後は戻る導線を出さない', (tester) async {
    await pump(tester, done: {FirstSetStep.quiz}, onBackToLearn: () {});

    expect(find.text(label), findsNothing);
  });

  testWidgets('学習タブ以外から開いたら戻る導線を出さない', (tester) async {
    await pump(tester);

    expect(find.text(label), findsNothing);
  });
}
