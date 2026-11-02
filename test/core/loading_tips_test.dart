import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/constants/loading_tips.dart';
import 'package:thai_memo/l10n/app_localizations.dart';

void main() {
  test('どの言語でも件数がそろい、空の文言がない', () {
    for (final code in ['ja', 'en', 'ko']) {
      final tips = LoadingTips.all(lookupL10n(Locale(code)));
      expect(tips.length, LoadingTips.count, reason: code);
      for (final tip in tips) {
        expect(tip.title.trim(), isNotEmpty, reason: code);
        expect(tip.content.trim(), isNotEmpty, reason: '$code ${tip.title}');
      }
    }
  });
}
