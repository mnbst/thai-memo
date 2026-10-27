import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/analytics_provider.dart';
import 'package:thai_memo/presentation/providers/tts_provider.dart';
import 'package:thai_memo/presentation/screens/thai_script_guide_screen.dart';
import 'package:thai_memo/services/tts_service.dart';

import 'package:thai_memo/services/analytics_service.dart';

class _FakeAnalytics implements AnalyticsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _RecordingTtsService extends Fake implements TtsService {
  final spoken = <String>[];

  @override
  Future<void> speak(
    String text, {
    bool slow = false,
    bool keepVoice = false,
    TtsSpeed speed = TtsSpeed.normal,
  }) async {
    spoken.add(text);
  }
}

Widget _host(_RecordingTtsService tts) => ProviderScope(
      overrides: [
        analyticsServiceProvider.overrideWithValue(_FakeAnalytics()),
        ttsServiceProvider.overrideWithValue(tts),
      ],
      child: const MaterialApp(
        locale: Locale('ja'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: ThaiScriptGuideScreen(),
      ),
    );

void main() {
  testWidgets('文字のしくみから単語の分解まで表示し、語の札を読み上げる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tts = _RecordingTtsService();

    await tester.pumpWidget(_host(tts));
    await tester.pumpAndSettle();

    expect(find.text('1. タイ文字のしくみ'), findsOneWidget);
    expect(find.text('2. よく使う子音'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('5. 単語を分解して読む'), 800);
    expect(find.text('5. 単語を分解して読む'), findsOneWidget);
    expect(find.text('ไม่'), findsOneWidget);

    await tester.ensureVisible(find.text('ไม่'));
    await tester.tap(find.text('ไม่'));
    await tester.pump();

    expect(tts.spoken, contains('ไม่'));
    expect(tester.takeException(), isNull);
  });
}
