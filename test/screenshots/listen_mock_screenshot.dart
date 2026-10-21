// =============================================================================
// listen_mock_screenshot.dart
// 聞き流し再生の UI 案（入口・再生画面・ミニバー）を1枚の PNG に並べるモック。
//
//   flutter test test/screenshots/listen_mock_screenshot.dart \
//     --dart-define=OUT=build/listen_mock.png
// =============================================================================

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:thai_memo/core/theme/app_colors.dart';
import 'package:thai_memo/core/theme/app_theme.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';

const _fallbacks = ['NotoSans_regular', 'NotoSansJP'];
const _out = String.fromEnvironment('OUT', defaultValue: 'build/listen_mock.png');

const _phoneW = 390.0;
const _phoneH = 844.0;
const _gap = 36.0;

typedef _S = ({String th, String pron, String ja, bool fav});

const _sentences = <_S>[
  (th: 'ฉันกินข้าวแล้ว', pron: 'chǎn kin khâaw lɛ́ɛw', ja: 'もうご飯を食べた', fav: false),
  (th: 'ไปสนามบินเท่าไหร่ครับ', pron: 'pai sanǎam bin thâw rài khráp', ja: '空港までいくらですか', fav: true),
  (th: 'อร่อยมากเลย', pron: 'a-rɔ̀ɔy mâak ləəy', ja: 'すごくおいしい', fav: false),
  (th: 'พรุ่งนี้ฝนจะตก', pron: 'phrûng níi fǒn cà tòk', ja: '明日は雨が降りそう', fav: true),
  (th: 'ขอน้ำแข็งเพิ่มหน่อย', pron: 'khɔ̌ɔ nám khɛ̌ng phə̂əm nɔ̀y', ja: '氷をもう少しください', fav: false),
  (th: 'รถติดมากวันนี้', pron: 'rót tìt mâak wan níi', ja: '今日はすごく渋滞している', fav: false),
];

void main() {
  testWidgets('聞き流し UI 案を撮る', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const w = _phoneW * 3 + _gap * 4;
    const h = _phoneH + 96;
    tester.view.physicalSize = const Size(w * 2, h * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final theme = _withFallbacks(buildAppLightTheme(ThaiFont.sarabun));
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: RepaintBoundary(
        key: const ValueKey('shot'),
        child: Container(
          color: const Color(0xFFE9E4DA),
          padding: const EdgeInsets.fromLTRB(_gap, 24, _gap, 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _Phone(label: '① 入口：履歴の「聞き流す」', child: _HistoryMock()),
              SizedBox(width: _gap),
              _Phone(label: '② 再生画面（じっくり・単語の段）', child: _PlayerMock()),
              SizedBox(width: _gap),
              _Phone(label: '③ 閉じるとミニバー', child: _HistoryMock(miniBar: true)),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('shot')));
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    File(_out)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
    // ignore: avoid_print
    print('WROTE $_out');
    debugDefaultTargetPlatformOverride = null;
  });
}

class _Phone extends StatelessWidget {
  const _Phone({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontFamily: 'NotoSansJP',
                decoration: TextDecoration.none,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.indigo)),
        const SizedBox(height: 12),
        Container(
          width: _phoneW,
          height: _phoneH,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(36),
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8))
            ],
          ),
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(_phoneW, _phoneH),
              padding: EdgeInsets.only(top: 47, bottom: 34),
              viewPadding: EdgeInsets.only(top: 47, bottom: 34),
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ①③ 履歴タブ
// ---------------------------------------------------------------------------

class _HistoryMock extends StatelessWidget {
  const _HistoryMock({this.miniBar = false});
  final bool miniBar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('履歴'),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: () {}),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'タイ語・日本語・発音で検索',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _chip(context, 'すべて', 42, true),
                const SizedBox(width: 8),
                _chip(context, 'お気に入り', 8, false, icon: Icons.favorite),
                const Spacer(),
                // 入口。いま一覧に出ている例文をそのまま流す。
                FilledButton.icon(
                  onPressed: () {},
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.indigo,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                  icon: const Icon(Icons.headphones, size: 18),
                  label: const Text('聞き流す',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontFamilyFallback: _fallbacks)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: ListView(
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final (i, s) in _sentences.indexed)
                    _row(context, s, playing: miniBar && i == 1,
                        last: i == _sentences.length - 1),
                ],
              ),
            ),
          ),
          if (miniBar) const _MiniBar(),
        ],
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          labelTextStyle: WidgetStatePropertyAll(
              theme.textTheme.labelMedium?.copyWith(fontFamilyFallback: _fallbacks)),
        ),
        child: NavigationBar(
        selectedIndex: 1,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.school_outlined), label: '学習'),
          NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: '履歴'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined), label: '設定'),
        ],
      ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label, int count, bool selected,
      {IconData? icon}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fg = selected ? cs.onPrimary : cs.onSurfaceVariant;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: selected ? cs.primary : cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? cs.primary : cs.outlineVariant),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: AppColors.vermilion),
          const SizedBox(width: 4),
        ],
        Text(label,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700, color: fg)),
        const SizedBox(width: 5),
        Text('$count',
            style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: fg.withValues(alpha: 0.65))),
      ]),
    );
  }

  Widget _row(BuildContext context, _S s,
      {required bool playing, required bool last}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: playing ? cs.tertiaryContainer.withValues(alpha: 0.6) : null,
        border: last
            ? null
            : Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(children: [
        if (playing) ...[
          const Icon(Icons.graphic_eq, size: 18, color: AppColors.goldInk),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.th,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(s.ja,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        Icon(s.fav ? Icons.favorite : Icons.favorite_border,
            size: 20,
            color: s.fav ? AppColors.vermilion : cs.onSurfaceVariant),
        const SizedBox(width: 8),
      ]),
    );
  }
}

class _MiniBar extends StatelessWidget {
  const _MiniBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const onIndigo = Color(0xFFF4EFE4);
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.indigo,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // 全体の進み（3/42 のうち文の中の位置まで）
        const LinearProgressIndicator(
          value: 0.06,
          minHeight: 3,
          color: AppColors.gold,
          backgroundColor: Color(0x33F4EFE4),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ไปสนามบินเท่าไหร่ครับ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                          color: onIndigo, fontWeight: FontWeight.w600)),
                  Text('2 / 42 ・ 単語',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: onIndigo.withValues(alpha: 0.7))),
                ],
              ),
            ),
            IconButton(
                onPressed: () {},
                icon: const Icon(Icons.pause_rounded, color: onIndigo, size: 30)),
            IconButton(
                onPressed: () {},
                icon: const Icon(Icons.skip_next_rounded,
                    color: onIndigo, size: 26)),
            IconButton(
                onPressed: () {},
                icon: Icon(Icons.close,
                    color: onIndigo.withValues(alpha: 0.7), size: 20)),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// ② 再生画面
// ---------------------------------------------------------------------------

class _PlayerMock extends StatelessWidget {
  const _PlayerMock();

  static const _on = Color(0xFFF4EFE4);
  static const _words = [
    ('ไป', 'pai', '行く'),
    ('สนามบิน', 'sanǎam bin', '空港'),
    ('เท่าไหร่', 'thâw rài', 'いくら'),
    ('ครับ', 'khráp', '（男性の丁寧語）'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = _on.withValues(alpha: 0.62);
    return Material(
      color: AppColors.indigo,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 47, 20, 34),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 上端：閉じる・位置・モード
            Row(children: [
              Icon(Icons.keyboard_arrow_down_rounded, color: _on, size: 30),
              const Spacer(),
              Text('すべて ・ 2 / 42',
                  style: theme.textTheme.labelLarge?.copyWith(color: dim)),
              const Spacer(),
              const SizedBox(width: 30),
            ]),
            const SizedBox(height: 14),
            Center(child: _modeToggle(theme)),
            const SizedBox(height: 22),
            // 1文の段（全文→単語→訳→全文）
            _stepper(theme),
            const SizedBox(height: 26),
            // 例文。いま読んでいる語を金で示す。
            Text.rich(
              TextSpan(children: [
                for (final (i, w) in _words.indexed)
                  TextSpan(
                    text: w.$1,
                    style: TextStyle(
                      color: i == 1 ? AppColors.gold : _on,
                      decoration: i == 1 ? TextDecoration.underline : null,
                      decorationColor: AppColors.gold,
                      decorationThickness: 2,
                    ),
                  ),
              ]),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w700, height: 1.5),
            ),
            const SizedBox(height: 6),
            Text('pai sanǎam bin thâw rài khráp',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: dim)),
            const SizedBox(height: 4),
            Text('空港までいくらですか',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(color: _on)),
            const SizedBox(height: 24),
            // いま読み上げている単語のカード
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
              decoration: BoxDecoration(
                color: const Color(0x14F4EFE4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
              ),
              child: Row(children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('สนามบิน',
                        style: theme.textTheme.headlineSmall?.copyWith(
                            color: AppColors.gold, fontWeight: FontWeight.w700)),
                    Text('sanǎam bin',
                        style: theme.textTheme.bodyMedium?.copyWith(color: dim)),
                  ],
                ),
                const SizedBox(width: 14),
                Icon(Icons.arrow_forward_rounded, color: dim, size: 20),
                const SizedBox(width: 14),
                Expanded(
                  child: Text('空港',
                      style: theme.textTheme.titleLarge?.copyWith(
                          color: _on, fontWeight: FontWeight.w700)),
                ),
                Text('2 / 4',
                    style: theme.textTheme.labelMedium?.copyWith(color: dim)),
              ]),
            ),
            const Spacer(),
            // 文の中の進み
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: const LinearProgressIndicator(
                value: 0.38,
                minHeight: 4,
                color: AppColors.gold,
                backgroundColor: Color(0x33F4EFE4),
              ),
            ),
            const SizedBox(height: 18),
            // 操作
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Icon(Icons.skip_previous_rounded, color: _on, size: 40),
                Container(
                  width: 76,
                  height: 76,
                  decoration: const BoxDecoration(
                      color: AppColors.gold, shape: BoxShape.circle),
                  child: const Icon(Icons.pause_rounded,
                      color: AppColors.indigo, size: 44),
                ),
                Icon(Icons.skip_next_rounded, color: _on, size: 40),
              ],
            ),
            const SizedBox(height: 22),
            // 設定チップ
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _pill(theme, Icons.speed, 'ゆっくり'),
                _pill(theme, Icons.translate, '訳'),
                _pill(theme, Icons.repeat, 'ループ'),
                _pill(theme, Icons.bedtime_outlined, '15分'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeToggle(ThemeData theme) {
    Widget seg(String t, bool sel) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
          decoration: BoxDecoration(
            color: sel ? _on : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(t,
              style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: sel ? AppColors.indigo : _on.withValues(alpha: 0.75))),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0x1FF4EFE4),
        borderRadius: BorderRadius.circular(21),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('さらっと', false),
        seg('じっくり', true),
      ]),
    );
  }

  Widget _stepper(ThemeData theme) {
    const steps = ['全文', '単語', '訳', '全文'];
    const current = 1;
    return Row(children: [
      for (final (i, s) in steps.indexed) ...[
        if (i > 0)
          Expanded(
            child: Container(
              height: 2,
              color: i <= current
                  ? AppColors.gold
                  : _on.withValues(alpha: 0.2),
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: i == current
                ? AppColors.gold
                : i < current
                    ? AppColors.gold.withValues(alpha: 0.25)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: i <= current
                    ? AppColors.gold
                    : _on.withValues(alpha: 0.3)),
          ),
          child: Text(s,
              style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: i == current
                      ? AppColors.indigo
                      : _on.withValues(alpha: i < current ? 0.9 : 0.55))),
        ),
      ],
    ]);
  }

  Widget _pill(ThemeData theme, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _on.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: _on.withValues(alpha: 0.85)),
        const SizedBox(width: 4),
        Text(label,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: _on.withValues(alpha: 0.9))),
      ]),
    );
  }
}

ThemeData _withFallbacks(ThemeData t) {
  TextStyle fb(TextStyle? s) =>
      (s ?? const TextStyle()).copyWith(fontFamilyFallback: _fallbacks);
  return t.copyWith(
    textTheme: t.textTheme.apply(fontFamilyFallback: _fallbacks),
    primaryTextTheme: t.primaryTextTheme.apply(fontFamilyFallback: _fallbacks),
    appBarTheme: t.appBarTheme
        .copyWith(titleTextStyle: fb(t.appBarTheme.titleTextStyle)),
  );
}

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final f = File(path);
    if (!f.existsSync()) return;
    await (FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync()))))
        .load();
  }

  const w = {
    'Regular': 'regular',
    'Medium': '500',
    'SemiBold': '600',
    'Bold': '700'
  };
  for (final e in w.entries) {
    await load('Sarabun_${e.value}', 'google_fonts/Sarabun-${e.key}.ttf');
    await load('NotoSans_${e.value}', 'google_fonts/NotoSans-${e.key}.ttf');
  }
  await load('MaterialIcons',
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  await load('NotoSansJP', 'tools/x_post/fonts/NotoSansJP-Regular.otf');
  // 枠外の見出し（fontFamily 未指定）用
  await load('Roboto', 'tools/x_post/fonts/NotoSansJP-Regular.otf');
  await load('FlutterTest', 'tools/x_post/fonts/NotoSansJP-Regular.otf');
}
