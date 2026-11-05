// =============================================================================
// vocab_history_screen.dart
// 復習タブ。出会った語を語彙ランクの大きい順に並べ、覚え具合をゲージで示す。
// 語をタップすると語の詳細、右上のアイコンから全例文の一覧（HistoryScreen）へ。
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/vocab_word.dart';
import '../../l10n/app_localizations.dart';
import '../providers/analytics_provider.dart';
import '../providers/vocab_progress_provider.dart';
import '../providers/vocab_stats_provider.dart';
import '../widgets/vocab_gauge.dart';
import '../widgets/vocab_guide_card.dart';
import 'history_screen.dart';
import 'vocab_word_screen.dart';

/// 一覧の中で語彙スコアの線を入れる位置を返す。
///
/// [entries] は語彙ランクの大きい順。スコアが無い人（0）は線を引かない。
@visibleForTesting
int? scoreMarkerIndex(List<VocabEntry> entries, int score) {
  if (score <= 0 || entries.isEmpty) return null;
  for (var i = 0; i < entries.length; i++) {
    final rank = entries[i].progress.rank;
    if (rank == 0 || rank <= score) return i;
  }
  return entries.length;
}

class VocabHistoryScreen extends ConsumerStatefulWidget {
  static const routeName = 'vocab_history';

  const VocabHistoryScreen({super.key});

  @override
  ConsumerState<VocabHistoryScreen> createState() => _VocabHistoryScreenState();
}

class _VocabHistoryScreenState extends ConsumerState<VocabHistoryScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  VocabMastery? _filter;
  bool _searching = false;
  String _query = '';

  /// 開いたときに自分の位置へ一度だけ動かす。
  bool _positioned = false;

  bool _showGuide = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadGuide());
  }

  Future<void> _loadGuide() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || (prefs.getBool(AppConfig.prefKeyVocabGuideDismissed) ?? false)) {
      return;
    }
    setState(() => _showGuide = true);
  }

  Future<void> _closeGuide() async {
    setState(() => _showGuide = false);
    unawaited(ref
        .read(analyticsServiceProvider)
        .logCoachMark(id: 'vocab_guide', action: 'dismiss'));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConfig.prefKeyVocabGuideDismissed, true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _closeSearch() {
    _searchController.clear();
    setState(() {
      _searching = false;
      _query = '';
    });
  }

  void _openAllSentences() {
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: HistoryScreen.routeName),
        builder: (_) => const HistoryScreen(),
      ),
    );
  }

  List<VocabEntry> _visible(List<VocabEntry> all) {
    return all.where((e) {
      if (_filter != null && e.progress.mastery != _filter) return false;
      if (_query.isEmpty) return true;
      return e.progress.word.contains(_query) ||
          e.pronunciation.toLowerCase().contains(_query) ||
          e.meaning.toLowerCase().contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final entriesAsync = ref.watch(vocabEntriesProvider);
    final all = entriesAsync.valueOrNull ?? const <VocabEntry>[];
    final score = ref.watch(vocabStatsProvider).valueOrNull?.estimatedVocab ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(hintText: l10n.vocabSearchHint),
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              )
            : Text(l10n.historyTitle),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            tooltip: l10n.vocabSearchHint,
            onPressed: _searching
                ? _closeSearch
                : () => setState(() => _searching = true),
          ),
          IconButton(
            icon: const Icon(Icons.article_outlined),
            tooltip: l10n.vocabAllSentences,
            onPressed: _openAllSentences,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppConfig.screenPadding, 4, AppConfig.screenPadding, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_showGuide) VocabGuideCard(onClose: _closeGuide),
            _Summary(entries: all, score: score),
            const SizedBox(height: 10),
            Row(
              children: [
                _chip(l10n.vocabFilterAll, all.length, null),
                for (final m in VocabMastery.values) ...[
                  const SizedBox(width: 6),
                  _chip(
                    m.label(l10n),
                    all.where((e) => e.progress.mastery == m).length,
                    m,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(
                l10n.vocabRankHeader,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            Expanded(child: _buildList(entriesAsync, all, score, l10n)),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, int count, VocabMastery? value) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = _filter == value;
    final ink = value?.inkColor(context);
    final fill = ink ?? cs.primary;
    final foreground = selected ? cs.onPrimary : (ink ?? cs.onSurfaceVariant);
    final style = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: foreground,
    );
    return Expanded(
      child: Material(
        color: selected ? fill : cs.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => setState(() => _filter = value),
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? fill
                    : (ink?.withValues(alpha: 0.55) ?? cs.outlineVariant),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, maxLines: 1, style: style),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$count',
                    maxLines: 1,
                    style: style?.copyWith(
                      color: foreground.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(
    AsyncValue<List<VocabEntry>> async,
    List<VocabEntry> all,
    int score,
    L10n l10n,
  ) {
    if (all.isEmpty && async.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final visible = _visible(all);
    if (visible.isEmpty) {
      return Center(
        child: Text(all.isEmpty ? l10n.vocabEmpty : l10n.vocabSearchEmpty),
      );
    }

    // 行の高さを固定して、1万語でも自分の位置まで計算だけで飛べるようにする。
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final bodySize = theme.textTheme.bodyMedium?.fontSize ?? 14;
    final rowExtent =
        28 + scaler.scale(18) * 1.5 + scaler.scale(bodySize) * 1.5 + 1;
    final markerExtent = 16 + scaler.scale(bodySize) * 1.5;

    final marker = scoreMarkerIndex(visible, score);
    final count = visible.length + (marker == null ? 0 : 1);

    if (!_positioned && marker != null && _filter == null && _query.isEmpty) {
      _positioned = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final target = marker * rowExtent - rowExtent * 2;
        _scroll.jumpTo(
          target.clamp(0.0, _scroll.position.maxScrollExtent),
        );
      });
    }

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(vocabProgressProvider);
          await ref.read(vocabEntriesProvider.future);
        },
        child: ListView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: count,
          itemExtentBuilder: (i, _) {
            if (i >= count) return null;
            return i == marker ? markerExtent : rowExtent;
          },
          itemBuilder: (context, i) {
            if (i == marker) return _ScoreMarker(score: score);
            final index = marker != null && i > marker ? i - 1 : i;
            return _VocabRow(
              entry: visible[index],
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  settings: const RouteSettings(name: VocabWordScreen.routeName),
                  builder: (_) => VocabWordScreen(entry: visible[index]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 上部の集計。出会った語数・語彙スコアと、状態ごとの割合の帯。
class _Summary extends StatelessWidget {
  final List<VocabEntry> entries;
  final int score;

  const _Summary({required this.entries, required this.score});

  int _count(VocabMastery m) =>
      entries.where((e) => e.progress.mastery == m).length;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.indigo,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${entries.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  l10n.vocabWordsMet,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
              Text(
                l10n.vocabScoreValue(score),
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (entries.isNotEmpty) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                height: 10,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (m, color) in const [
                      (VocabMastery.learned, Color(0xFF58B89A)),
                      (VocabMastery.learning, AppColors.gold),
                      (VocabMastery.seen, Color(0xFF8A93A8)),
                    ])
                      if (_count(m) > 0)
                        Expanded(
                          flex: _count(m),
                          child: ColoredBox(color: color),
                        ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 語彙スコアの位置を示す線。
class _ScoreMarker extends StatelessWidget {
  final int score;

  const _ScoreMarker({required this.score});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF6B5220);
    return ColoredBox(
      color: const Color(0xFFF2E7CF),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            const Icon(Icons.place, size: 15, color: ink),
            const SizedBox(width: 6),
            Text(
              L10n.of(context).vocabScoreValue(score),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VocabRow extends StatelessWidget {
  final VocabEntry entry;
  final VoidCallback onTap;

  const _VocabRow({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final word = entry.progress;
    return InkWell(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: cs.outlineVariant)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  word.rank > 0 ? '${word.rank}' : '-',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: muted?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${word.word}  ${entry.meaning}'.trimRight(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                        // タイ文字は太らせると声調記号が潰れる。
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                      ),
                    ),
                    Text(
                      entry.pronunciation,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: muted,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              VocabGauge(word: word),
            ],
          ),
        ),
      ),
    );
  }
}
