// =============================================================================
// tip_card_screenshot.dart
// Tips・ガイドの投稿文を、アプリと同じ色・フォントの縦長カード（9:16）の画像にする。
// TikTok の写真投稿に使う。通常の `flutter test` では拾われない。
//
//   flutter test test/screenshots/tip_card_screenshot.dart \
//     --dart-define=TIP_TEXT=build/x_post/text.txt \
//     --dart-define=TIP_OUT=build/x_post/tip_ja.png \
//     --dart-define=X_POST_LANG=ja \
//     --dart-define=TIP_LABEL=Guide   # 既定は Tips
//
// 1行目を見出し、空行のあとを本文として組む。
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/theme/app_colors.dart';
import 'package:thai_memo/core/theme/app_theme.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';

import 'x_post_common.dart';

const String _lang = String.fromEnvironment('X_POST_LANG', defaultValue: 'ja');

/// 左上の見出し。Tips は Tips、ガイドは Guide。
const String _label = String.fromEnvironment('TIP_LABEL', defaultValue: 'Tips');

/// 9:16 の論理サイズ。描画倍率 3 で 1179×2096。
const Size _size = Size(393, 698.7);
const _key = ValueKey('tip-card');

void main() {
  const textPath = String.fromEnvironment(
    'TIP_TEXT',
    defaultValue: 'build/x_post/text.txt',
  );
  const outPath = String.fromEnvironment(
    'TIP_OUT',
    defaultValue: 'build/x_post/tip.png',
  );

  testWidgets('Tips の文をカード画像に書き出す', (tester) async {
    // フォントの読み込みだけ使う（例文は読まない）。
    await loadPostFonts();
    tester.view.devicePixelRatio = postPixelRatio;
    tester.view.physicalSize = _size * postPixelRatio;
    addTearDown(tester.view.reset);

    // 絵文字のフォントが無く豆腐になるので、カードからは落とす（投稿文には残る）。
    final text = _stripEmoji(File(textPath).readAsStringSync()).trim();
    final parts = text.split(RegExp(r'\n\s*\n'));
    final title = parts.first.trim();
    final body = parts.skip(1).join('\n\n').trim();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale(_lang),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: postThemeWithFallbacks(buildAppLightTheme(ThaiFont.sarabun)),
        home: RepaintBoundary(
          key: _key,
          child: _TipCard(title: title, body: body),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final png = (await tester.runAsync(() => capturePost(tester, _key)))!;
    File(outPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(png);
  });
}

/// 絵文字（記号・絵文字の面と異体字セレクタ・ZWJ）を除く。
String _stripEmoji(String text) => text
    .replaceAll(
      RegExp(
        r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}\u{2B50}\u{2B55}]',
        unicode: true,
      ),
      '',
    )
    .replaceAll(RegExp(r'[ \t]+\n'), '\n');

class _TipCard extends StatelessWidget {
  const _TipCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appName = L10n.of(context).appTitle;
    return ColoredBox(
      color: AppColors.paper,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 56, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(width: 4, height: 18, color: AppColors.gold),
                const SizedBox(width: 8),
                Text(
                  _label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.goldInk,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
              decoration: BoxDecoration(
                color: AppColors.indigo,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (body.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  body,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppColors.indigo,
                    fontSize: 19,
                    height: 1.7,
                  ),
                ),
              ),
            const Spacer(),
            Center(
              child: Text(
                appName,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.goldInk,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
