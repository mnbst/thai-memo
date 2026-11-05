import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/screens/tone_guide_screen.dart';

void main() {
  testWidgets('子音クラスの説明に、ห が先頭につく規則を出す', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('ja'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: ToneGuideScreen(),
    ));
    await tester.pumpAndSettle();

    final note = find.text('一部の低子音の前に ห がつくと、発音せず高子音の声調規則に従います。');
    await tester.scrollUntilVisible(note, 300,
        scrollable: find.byType(Scrollable).first);
    expect(note, findsOneWidget);
  });
}
