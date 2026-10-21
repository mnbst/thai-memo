// =============================================================================
// review_notify_mock_app.dart
// 通知を1日に複数回設定する UI 案（iPhone の「時計 › アラーム」風）。
// 設定の入口・通知時刻の一覧と、届く通知の見え方を
// シミュレーターで触って確かめるためのモック。
//
//   flutter run -t test/screenshots/review_notify_mock_app.dart
//
// どの時刻にも新しい例文セットが届く。前の配信セットを1本も読んでいなければ
// 新しいセットに入れ替える（洗い替え）。読みかけのセットはそのまま残す。
// free は1枠、premium は3枠。プランが変わったら通知時刻はリセットする。
// =============================================================================

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:thai_memo/core/config/app_config.dart';
import 'package:thai_memo/core/theme/app_theme.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';

void main() => runApp(const _MockApp());

/// premium の通知の枠の数（固定）。free は1枠。
const _slotCount = 3;

/// プランごとの初期の枠。プランが変わったら通知時刻はこれに戻す。
List<_Slot> _defaultSlots({required bool premium}) => premium
    ? [_Slot(7, enabled: false), _Slot(10), _Slot(20, enabled: false)]
    : [_Slot(10)];

class _Slot {
  _Slot(this.hour, {this.enabled = true});
  int hour;
  bool enabled;
}

/// プレビューで時刻ごとに違うセットが届くように見せる見本。
const _samples = [
  (word: 'กิน（食べる）', body: 'ฉันกินข้าวแล้ว\nchǎn kin khâaw lɛ́ɛw\nもうご飯を食べた'),
  (word: 'ฝน（雨）', body: 'พรุ่งนี้ฝนจะตก\nphrûng níi fǒn cà tòk\n明日は雨が降りそう'),
  (word: 'รถติด（渋滞）', body: 'รถติดมากวันนี้\nrót tìt mâak wan níi\n今日はすごく渋滞している'),
];

String _fmt(int hour) => '${hour.toString().padLeft(2, '0')}:00';

class _MockApp extends StatelessWidget {
  const _MockApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppLightTheme(ThaiFont.sarabun),
      home: const _MockHome(),
    );
  }
}

class _MockHome extends StatefulWidget {
  const _MockHome();

  @override
  State<_MockHome> createState() => _MockHomeState();
}

class _MockHomeState extends State<_MockHome> {
  int _tab = 0;
  bool _premium = false;
  var _slots = _defaultSlots(premium: false);

  List<_Slot> get _enabledSorted =>
      _slots.where((s) => s.enabled).toList()
        ..sort((a, b) => a.hour.compareTo(b.hour));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_tab == 0 ? '設定' : '届く通知')),
      body: _tab == 0 ? _buildSettings() : _buildPreview(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.settings), label: '設定'),
          NavigationDestination(
              icon: Icon(Icons.notifications), label: '通知プレビュー'),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 設定（学習設定カード）。通知は1行にまとめ、一覧画面へ入る。
  // ---------------------------------------------------------------------------

  Widget _buildSettings() {
    final theme = Theme.of(context);
    final on = _enabledSorted;
    final tiles = <Widget>[
      const ListTile(
        leading: Icon(Icons.straighten),
        title: Text('語彙テスト'),
        subtitle: Text('前回 2026/10/12'),
        trailing: Icon(Icons.chevron_right),
      ),
      ListTile(
        leading: const Icon(Icons.notifications_active_outlined),
        title: const Text('毎日の例文通知'),
        subtitle: Text(
          on.isEmpty ? 'オフ' : on.map((s) => _fmt(s.hour)).join('・'),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.push(
            context,
            CupertinoPageRoute(
              builder: (_) =>
                  _SlotListScreen(slots: _slots, premium: _premium),
            ),
          );
          setState(() {});
        },
      ),
      const ListTile(
        leading: Icon(Icons.leaderboard_outlined),
        title: Text('ランキング'),
        subtitle: Text('今週の学習量'),
        trailing: Icon(Icons.chevron_right),
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(AppConfig.screenPadding),
      children: [
        // モックだけの切り替え。free と premium の見え方を比べる。
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('モック：Free')),
            ButtonSegment(value: true, label: Text('モック：Premium')),
          ],
          selected: {_premium},
          onSelectionChanged: (v) => setState(() {
            _premium = v.first;
            _slots = _defaultSlots(premium: _premium);
          }),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              '学習設定',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.08 * 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0)
                  const Divider(
                    height: 1,
                    indent: AppConfig.defaultPadding,
                    endIndent: AppConfig.defaultPadding,
                  ),
                tiles[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 届く通知（ロック画面風）。オンの時刻を順に並べる。
  // ---------------------------------------------------------------------------

  Widget _buildPreview() {
    final on = _enabledSorted;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B2440), Color(0xFF3A2F4F)],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 24, 12, 24),
        children: [
          if (on.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Text('通知はオフです',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70)),
            ),
          for (var i = 0; i < on.length; i++) ...[
            _caption(_fmt(on[i].hour)),
            _notification(
              time: _fmt(on[i].hour),
              title: '🇹🇭 ${_samples[i].word} ほか4本',
              body: _samples[i].body,
            ),
          ],
          const SizedBox(height: 16),
          if (on.length > 1)
            const Text(
              '前のセットを読んでいなければ、新しいセットに入れ替わります。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
        ],
      ),
    );
  }

  Widget _caption(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
      );

  Widget _notification({
    required String time,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF1F3A68),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Text('ไ',
                style: TextStyle(color: Colors.white, fontSize: 20)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                    Text(time,
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(fontSize: 14, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 通知時刻の一覧（アラーム風）。枠は固定で、トグルだけで出し入れする。
// 行タップで時刻変更。free は1枠＋プレミアム案内、premium は3枠＋入れ替えの注意。
// -----------------------------------------------------------------------------

class _SlotListScreen extends StatefulWidget {
  const _SlotListScreen({required this.slots, required this.premium});
  final List<_Slot> slots;
  final bool premium;

  @override
  State<_SlotListScreen> createState() => _SlotListScreenState();
}

class _SlotListScreenState extends State<_SlotListScreen> {
  List<_Slot> get _slots => widget.slots;
  bool get _premium => widget.premium;

  void _sort() => _slots.sort((a, b) => a.hour.compareTo(b.hour));

  @override
  void initState() {
    super.initState();
    _sort();
  }


  void _showPremiumPitch() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.notifications_active,
                    size: 40, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text('無料プランの通知は1日1回までです',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  'プレミアムなら、朝・昼・夜など1日$_slotCount回まで'
                  '新しい例文セットが届きます。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('プレミアムを見る'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('閉じる'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _edit(_Slot slot) async {
    final taken = {
      for (final s in _slots)
        if (!identical(s, slot)) s.hour,
    };
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (_) => _HourSheet(
        initial: slot.hour,
        taken: taken,
        title: '時刻を変更',
      ),
    );
    if (picked == null) return;
    setState(() {
      slot.hour = picked;
      _sort();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('毎日の例文通知')),
      body: ListView(
        children: [
          for (final slot in _slots) _row(theme, slot),
          if (_premium)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Text(
                '通知ごとに新しい例文セットが届きます。'
                '次の通知までに1本も読まなかった例文セットは、新しいものに入れ替わります。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading:
                  Icon(Icons.lock, size: 20, color: theme.colorScheme.primary),
              title: Text(
                'プレミアムでは、例文通知を1日$_slotCount回まで設定できます',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
              trailing: Icon(Icons.chevron_right,
                  color: theme.colorScheme.primary),
              onTap: _showPremiumPitch,
            ),
        ],
      ),
    );
  }

  Widget _row(ThemeData theme, _Slot slot) {
    final color = slot.enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.outline;
    return InkWell(
      onTap: () => _edit(slot),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _fmt(slot.hour),
                style: TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w300,
                  height: 1.1,
                  color: color,
                ),
              ),
            ),
            CupertinoSwitch(
              value: slot.enabled,
              activeTrackColor: theme.colorScheme.primary,
              onChanged: (v) => setState(() => slot.enabled = v),
            ),
          ],
        ),
      ),
    );
  }
}

/// iOS の時刻選択風のホイール。配信は時単位なので「時」だけ回す。
class _HourSheet extends StatefulWidget {
  const _HourSheet({
    required this.initial,
    required this.taken,
    required this.title,
  });
  final int initial;
  final Set<int> taken;
  final String title;

  @override
  State<_HourSheet> createState() => _HourSheetState();
}

class _HourSheetState extends State<_HourSheet> {
  late int _hour = widget.initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dup = widget.taken.contains(_hour);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('キャンセル'),
              ),
              Expanded(
                child: Text(widget.title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium),
              ),
              TextButton(
                onPressed: dup ? null : () => Navigator.pop(context, _hour),
                child: const Text('保存'),
              ),
            ],
          ),
          SizedBox(
            height: 216,
            child: CupertinoPicker(
              itemExtent: 40,
              scrollController:
                  FixedExtentScrollController(initialItem: widget.initial),
              onSelectedItemChanged: (h) => setState(() => _hour = h),
              children: [
                for (var h = 0; h < 24; h++)
                  Center(
                    child: Text(
                      _fmt(h),
                      style: TextStyle(
                        fontSize: 22,
                        color: widget.taken.contains(h)
                            ? theme.colorScheme.outline
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 28,
            child: dup
                ? Text('その時刻はもう設定されています',
                    style: TextStyle(color: theme.colorScheme.error))
                : null,
          ),
        ],
      ),
    );
  }
}
