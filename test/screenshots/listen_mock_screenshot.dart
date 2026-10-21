// =============================================================================
// listen_mock_screenshot.dart
// 聞き流し再生（トラック版）の UI 案を1枚の PNG に並べるモック。
// ① 履歴からトラックに追加 ② トラック一覧 ③ トラックの中身＋ミニバー ④ 再生画面
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

typedef _T = ({String name, int count, String mode});

const _tracks = <_T>[
  (name: '通勤用', count: 12, mode: 'じっくり'),
  (name: '寝る前', count: 5, mode: 'さらっと'),
  (name: '旅行で使う', count: 23, mode: 'さらっと'),
];

void main() {
  testWidgets('聞き流し UI 案を撮る', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const w = _phoneW * 4 + _gap * 5;
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
              _Phone(label: '① 履歴：長押しでトラックに追加', child: _HistoryMock()),
              SizedBox(width: _gap),
              _Phone(label: '② トラック一覧', child: _TrackListMock()),
              SizedBox(width: _gap),
              _Phone(label: '③ トラックの中身（再生中はミニバー）', child: _TrackDetailMock()),
              SizedBox(width: _gap),
              _Phone(label: '④ 再生画面（じっくり・単語の段）', child: _PlayerMock()),
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
// 履歴タブの共通部品
// ---------------------------------------------------------------------------

/// 履歴タブの外枠。上に [例文][トラック] の切り替え、下にナビゲーション。
class _HistoryShell extends StatelessWidget {
  const _HistoryShell({
    required this.tracksSelected,
    required this.body,
    this.title = '履歴',
    this.leading,
    this.actions = const [],
    this.showSwitch = true,
    this.bottom,
  });
  final bool tracksSelected;
  final Widget body;
  final String title;
  final Widget? leading;
  final List<Widget> actions;
  final bool showSwitch;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: leading,
        title: Text(title),
        actions: [...actions, const SizedBox(width: 4)],
      ),
      body: Column(
        children: [
          if (showSwitch) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: _switch(context),
            ),
            const SizedBox(height: 12),
          ],
          Expanded(child: body),
          if (bottom != null) bottom!,
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

  Widget _switch(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget seg(String t, IconData icon, bool sel) => Expanded(
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: sel ? cs.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: sel
                  ? const [BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1))]
                  : null,
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 17, color: sel ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(t,
                  style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: sel ? cs.primary : cs.onSurfaceVariant)),
            ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        seg('例文', Icons.notes_rounded, !tracksSelected),
        seg('トラック', Icons.queue_music_rounded, tracksSelected),
      ]),
    );
  }
}

/// 角丸の枠に入った一覧。
Widget _listBox(BuildContext context, List<Widget> rows) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: cs.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: cs.outlineVariant),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      for (final (i, r) in rows.indexed) ...[
        if (i > 0) Divider(height: 1, color: cs.outlineVariant),
        r,
      ],
    ]),
  );
}

Widget _sentenceText(BuildContext context, _S s) {
  final theme = Theme.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(s.th,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(s.ja,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    ],
  );
}

// ---------------------------------------------------------------------------
// ① 履歴（例文）＋「トラックに追加」シート
// ---------------------------------------------------------------------------

class _HistoryMock extends StatelessWidget {
  const _HistoryMock();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Stack(children: [
      _HistoryShell(
        tracksSelected: false,
        body: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: _listBox(context, [
            for (final (i, s) in _sentences.indexed)
              Container(
                color: i == 1 ? cs.primaryContainer.withValues(alpha: 0.5) : null,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(children: [
                  Expanded(child: _sentenceText(context, s)),
                  Icon(s.fav ? Icons.favorite : Icons.favorite_border,
                      size: 20,
                      color: s.fav ? AppColors.vermilion : cs.onSurfaceVariant),
                ]),
              ),
          ]),
        ),
      ),
      // 背景を暗くしてシートを出す
      Positioned.fill(child: Container(color: const Color(0x66000000))),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Material(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 34 + 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: cs.outlineVariant,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Text('トラックに追加',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(_sentences[1].th,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 16),
                for (final (i, t) in _tracks.indexed)
                  _trackOption(context, t, added: i == 0),
                const SizedBox(height: 4),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: cs.surfaceContainerHighest,
                    child: Icon(Icons.add, color: cs.primary),
                  ),
                  title: Text('新しいトラック',
                      style: theme.textTheme.titleMedium?.copyWith(
                          color: cs.primary, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _trackOption(BuildContext context, _T t, {required bool added}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: AppColors.indigo,
        child: const Icon(Icons.queue_music_rounded, color: AppColors.gold, size: 20),
      ),
      title: Text(t.name,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text('${t.count}文',
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      // 入っているトラックはチェック。押すと外す。
      trailing: Icon(
          added ? Icons.check_circle : Icons.add_circle_outline,
          color: added ? AppColors.jade : cs.onSurfaceVariant,
          size: 26),
    );
  }
}

// ---------------------------------------------------------------------------
// ② トラック一覧
// ---------------------------------------------------------------------------

class _TrackListMock extends StatelessWidget {
  const _TrackListMock();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return _HistoryShell(
      tracksSelected: true,
      body: Column(children: [
        for (final t in _tracks)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('${t.count}文 ・ ${t.mode}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              // 押すとすぐ頭から流す。カードの残りを押すと中身へ。
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                    color: AppColors.gold, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded,
                    color: AppColors.indigo, size: 30),
              ),
            ]),
          ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.add),
            label: const Text('新しいトラック',
                style: TextStyle(fontWeight: FontWeight.w700, fontFamilyFallback: _fallbacks)),
          ),
        ),
        const Spacer(),
        // 無料プランの上限
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text('無料プランはトラック1つ・5文まで。Premium で無制限',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// ③ トラックの中身＋ミニバー
// ---------------------------------------------------------------------------

class _TrackDetailMock extends StatelessWidget {
  const _TrackDetailMock();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return _HistoryShell(
      tracksSelected: true,
      showSwitch: false,
      title: '通勤用',
      leading: const Icon(Icons.arrow_back),
      actions: [IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () {})],
      bottom: const _MiniBar(),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(children: [
            Text('12文 ・ じっくり',
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            const Spacer(),
            FilledButton.icon(
              onPressed: () {},
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.indigo,
                minimumSize: const Size(0, 40),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: const Text('最初から',
                  style: TextStyle(fontWeight: FontWeight.w700, fontFamilyFallback: _fallbacks)),
            ),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: _listBox(context, [
              for (final (i, s) in _sentences.indexed)
                if (i == 3) _swipedRow(context, s) else _row(context, s, playing: i == 1),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _row(BuildContext context, _S s, {required bool playing}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: playing ? cs.tertiaryContainer.withValues(alpha: 0.6) : cs.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(children: [
        SizedBox(
          width: 26,
          child: playing
              ? const Icon(Icons.graphic_eq, size: 18, color: AppColors.goldInk)
              : null,
        ),
        Expanded(child: _sentenceText(context, s)),
        // 並べ替えのつまみ
        Icon(Icons.drag_handle_rounded, color: cs.onSurfaceVariant),
      ]),
    );
  }

  /// 横スワイプで外す途中の行。
  Widget _swipedRow(BuildContext context, _S s) {
    return Stack(children: [
      Positioned.fill(
        child: Container(
          color: AppColors.vermilion,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.remove_circle_outline, color: Colors.white, size: 20),
            SizedBox(width: 6),
            Text('外す',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontFamilyFallback: _fallbacks)),
          ]),
        ),
      ),
      Transform.translate(
        offset: const Offset(-96, 0),
        child: _row(context, s, playing: false),
      ),
    ]);
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
        // トラック全体の進み（2/12 のうち文の中の位置まで）
        const LinearProgressIndicator(
          value: 0.12,
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
                  Text('通勤用 ・ 2 / 12 ・ 単語',
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
              Text('通勤用 ・ 2 / 12',
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
                _pill(theme, Icons.speed, '0.7x'),
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
