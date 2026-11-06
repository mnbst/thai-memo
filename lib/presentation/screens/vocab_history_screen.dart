// =============================================================================
// vocab_history_screen.dart
// 復習タブ。出会った語を語彙ランクの大きい順に並べ、覚え具合をゲージで示す。
// 語をタップすると語の詳細、右上のアイコンから全例文の一覧（HistoryScreen）へ。
// =============================================================================

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/vocab_word.dart';
import '../../l10n/app_localizations.dart';
import '../providers/analytics_provider.dart';
import '../providers/remaining_quota_provider.dart';
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

/// まとめクイズのスコア枠（low〜high）。サーバーの uvm.QuizScoreBand と同じ計算。
///
/// 復習枠・苦手枠は範囲外からも出るので、画面では目安として見せる。
@visibleForTesting
(int, int) quizScoreBand({
  required int score,
  required int tested,
  required bool premium,
}) {
  const freeLimit = 100;
  const testCeiling = 3000;
  final floor = premium ? tested : min(tested, freeLimit);
  final current = max(score, floor);
  final low = max(floor, current - 30);

  // free の key_word 帯は測定値で平行移動しない。
  final shift = premium ? floor : 0;
  final e = max(score - shift, 0);
  var keyWordHigh = e + max(8.0, 20 - e / 5).toInt() + shift;
  if (shift >= testCeiling) {
    keyWordHigh = max(keyWordHigh, score + (0.015 * score).toInt());
  }
  if (!premium) keyWordHigh = min(keyWordHigh, freeLimit);
  if (shift >= testCeiling) return (low, keyWordHigh);
  return (low, min(current + 8, keyWordHigh));
}

enum VocabListMarker { rangeTop, score, rangeBottom }

/// 語の間にスコア行と出題範囲の区切りを挟んだ、一覧の行を返す。
///
/// [entries] は語彙ランクの大きい順。範囲内の語が無ければ区切りは出さない。
@visibleForTesting
List<Object> vocabListRows(
  List<VocabEntry> entries,
  int score,
  (int, int)? band,
) {
  final marks = <(int, int, VocabListMarker)>[];
  final scoreAt = scoreMarkerIndex(entries, score);
  if (scoreAt != null) marks.add((scoreAt, score, VocabListMarker.score));
  if (band != null) {
    final (low, high) = band;
    bool isBelow(VocabEntry e) => e.progress.rank < low;
    final top = entries.indexWhere(
      (e) => e.progress.rank > 0 && e.progress.rank <= high,
    );
    final below = entries.indexWhere(isBelow);
    final bottom = below < 0 ? entries.length : below;
    if (top >= 0 && top < bottom) {
      marks.add((top, high, VocabListMarker.rangeTop));
      marks.add((bottom, low - 1, VocabListMarker.rangeBottom));
    }
  }
  // 同じ位置なら語彙ランクの大きい順に並べる。
  marks.sort((a, b) {
    final byIndex = a.$1.compareTo(b.$1);
    return byIndex != 0 ? byIndex : b.$2.compareTo(a.$2);
  });

  final rows = <Object>[];
  var next = 0;
  for (var i = 0; i <= entries.length; i++) {
    while (next < marks.length && marks[next].$1 == i) {
      rows.add(marks[next++].$3);
    }
    if (i < entries.length) rows.add(entries[i]);
  }
  return rows;
}

class VocabHistoryScreen extends ConsumerStatefulWidget {
  static const routeName = 'vocab_history';

  const VocabHistoryScreen({super.key});

  @override
  ConsumerState<VocabHistoryScreen> createState() => _VocabHistoryScreenState();
}

class _VocabHistoryScreenState extends ConsumerState<VocabHistoryScreen> {
  final GlobalKey<NestedScrollViewState> _nestedKey = GlobalKey();
  final TextEditingController _searchController = TextEditingController();

  /// 一覧のスクロール位置。出題範囲の貼り付け表示だけが購読する。
  final ValueNotifier<double> _listPixels = ValueNotifier(0);
  VocabMastery? _filter;
  bool _searching = false;
  String _query = '';

  /// 開いたときに自分の位置へ一度だけ動かす。
  bool _positioned = false;

  bool _guideChecked = false;
  bool _showGuide = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadGuide());
  }

  Future<void> _loadGuide() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _guideChecked = true;
      _showGuide =
          !(prefs.getBool(AppConfig.prefKeyVocabGuideDismissed) ?? false);
    });
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
    _searchController.dispose();
    _listPixels.dispose();
    super.dispose();
  }

  bool _onListNotification(Notification n) {
    // 絞り込みで一覧が縮むと、スクロールせずに位置だけが変わることがある。
    if (n is ScrollNotification && n.depth == 0) {
      _listPixels.value = n.metrics.pixels;
    } else if (n is ScrollMetricsNotification && n.depth == 0) {
      _listPixels.value = n.metrics.pixels;
    }
    return false;
  }

  void _closeSearch() {
    _searchController.clear();
    setState(() {
      _searching = false;
      _query = '';
    });
  }

  void _logReview(String action, {String? value}) {
    unawaited(
      ref
          .read(analyticsServiceProvider)
          .logReviewTab(action: action, value: value),
    );
  }

  void _openAllSentences() {
    _logReview('all_sentences');
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
    final stats = ref.watch(vocabStatsProvider).valueOrNull;
    final score = stats?.estimatedVocab ?? 0;
    final premium = ref.watch(effectivePremiumProvider);
    final band = stats == null
        ? null
        : quizScoreBand(
            score: score,
            tested: stats.testedVocab,
            premium: premium,
          );

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(hintText: l10n.vocabSearchHint),
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
              )
            : Text(l10n.historyTitle),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            tooltip: l10n.vocabSearchHint,
            onPressed: _searching
                ? _closeSearch
                : () {
                    _logReview('search');
                    setState(() => _searching = true);
                  },
          ),
          IconButton(
            icon: const Icon(Icons.article_outlined),
            tooltip: l10n.vocabAllSentences,
            onPressed: _openAllSentences,
          ),
          const SizedBox(width: 4),
        ],
      ),
      // 案内カードだけを見出しとして一緒に流し、下の一覧の高さはカードの有無で変えない。
      body: NestedScrollView(
        key: _nestedKey,
        headerSliverBuilder: (context, _) => [
          if (_showGuide)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppConfig.screenPadding, 4, AppConfig.screenPadding, 0),
                child: VocabGuideCard(onClose: _closeGuide),
              ),
            ),
        ],
        body: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppConfig.screenPadding, 4, AppConfig.screenPadding, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              Expanded(child: _buildList(entriesAsync, all, score, band, l10n)),
            ],
          ),
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
          onTap: () {
            _logReview('filter', value: value?.name ?? 'all');
            setState(() => _filter = value);
          },
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
    (int, int)? band,
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

    final rows = vocabListRows(visible, score, band);
    final count = rows.length;
    double extentOf(Object row) => row is VocabEntry ? rowExtent : markerExtent;
    double offsetOf(int index) =>
        rows.take(index).fold<double>(0, (sum, row) => sum + extentOf(row));
    final marker = rows.indexOf(VocabListMarker.score);
    final rangeTop = rows.indexOf(VocabListMarker.rangeTop);
    final rangeTopOffset = rangeTop < 0 ? 0.0 : offsetOf(rangeTop);
    final rangeBottomOffset = rangeTop < 0
        ? 0.0
        : offsetOf(rows.indexOf(VocabListMarker.rangeBottom));

    // NestedScrollView は一覧を動かすと見出しも畳むので、案内を閉じるまで飛ばない。
    if (!_positioned &&
        _guideChecked &&
        !_showGuide &&
        marker >= 0 &&
        _filter == null &&
        _query.isEmpty) {
      _positioned = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final scroll = _nestedKey.currentState?.innerController;
        if (scroll == null || !scroll.hasClients) return;
        final target = offsetOf(marker) - rowExtent * 2;
        scroll.jumpTo(
          target.clamp(0.0, scroll.position.maxScrollExtent),
        );
      });
    }

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(vocabProgressProvider);
                await ref.read(vocabEntriesProvider.future);
              },
              child: NotificationListener<Notification>(
                onNotification: _onListNotification,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: count,
                  itemExtentBuilder: (i, _) {
                    if (i >= count) return null;
                    return extentOf(rows[i]);
                  },
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    return switch (row) {
                      VocabListMarker.score => _ScoreMarker(score: score),
                      VocabListMarker.rangeTop => const _RangeEdge(top: true),
                      VocabListMarker.rangeBottom =>
                        const _RangeEdge(top: false),
                      _ => _VocabRow(
                          entry: row as VocabEntry,
                          onTap: () {
                            _logReview(
                              'word_open',
                              value: row.progress.mastery.name,
                            );
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                settings: const RouteSettings(
                                  name: VocabWordScreen.routeName,
                                ),
                                builder: (_) => VocabWordScreen(entry: row),
                              ),
                            );
                          },
                        ),
                    };
                  },
                ),
              ),
            ),
            if (rangeTop >= 0)
              ValueListenableBuilder<double>(
                valueListenable: _listPixels,
                builder: (context, pixels, _) {
                  if (pixels < rangeTopOffset) return const SizedBox.shrink();
                  final past = pixels >= rangeBottomOffset;
                  // 上端の区切りは、下端の区切りに押し出されて入れ替わる。
                  final y = past
                      ? 0.0
                      : (rangeBottomOffset - pixels - markerExtent)
                          .clamp(-markerExtent, 0.0);
                  return Positioned(
                    top: y,
                    left: 0,
                    right: 0,
                    height: markerExtent,
                    child: _RangeEdge(top: !past),
                  );
                },
              ),
            // 範囲を見ている間は、下端の区切りを一覧の一番下で止めておく。
            if (rangeTop >= 0)
              ValueListenableBuilder<double>(
                valueListenable: _listPixels,
                builder: (context, pixels, _) {
                  final viewport = constraints.maxHeight;
                  final topInView =
                      pixels + viewport >= rangeTopOffset + markerExtent;
                  final bottomInView =
                      rangeBottomOffset - pixels <= viewport - markerExtent;
                  if (!topInView || bottomInView) {
                    return const SizedBox.shrink();
                  }
                  return Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: markerExtent,
                    child: const _RangeEdge(top: false),
                  );
                },
              ),
          ],
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

/// まとめクイズの出題範囲の上端・下端を示す区切り。
class _RangeEdge extends StatelessWidget {
  final bool top;

  const _RangeEdge({required this.top});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF2E7D66);
    return ColoredBox(
      color: const Color(0xFFE3F1EC),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(
              top ? Icons.arrow_downward : Icons.arrow_upward,
              size: 15,
              color: ink,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                L10n.of(context).vocabQuizRange,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
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
