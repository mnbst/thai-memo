import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../providers/leaderboard_provider.dart';
import '../providers/remaining_quota_provider.dart';
import '../providers/vocab_stats_provider.dart';
import '../widgets/swipe_back.dart';
import '../widgets/vocab_level.dart';
import 'paywall_screen.dart';

/// 語彙スコアのランキング画面。
///
/// スコアも表示名（タイ人名を自動採番）もサーバーが書く。ユーザーの設定操作はない。
/// 自分の順位を上に固定し、その下に上位[leaderboardTopCount]人と、自分の上下
/// [leaderboardNeighborCount]人ずつを並べる。全員ぶんの一覧は出さない。
class RankingScreen extends ConsumerWidget {
  static const routeName = 'ranking';

  const RankingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final rowsAsync = ref.watch(leaderboardRowsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.rankingTitle)),
      body: SwipeBack(
        // 自分の順位は常に見えるよう画面上部に固定し、一覧だけをスクロールさせる。
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppConfig.defaultPadding,
                AppConfig.defaultPadding,
                AppConfig.defaultPadding,
                8,
              ),
              child: _MyRankCard(),
            ),
            Expanded(child: _RankingList(rowsAsync: rowsAsync)),
          ],
        ),
      ),
    );
  }
}

/// 自分の周辺だけの一覧部分
class _RankingList extends ConsumerWidget {
  const _RankingList({required this.rowsAsync});

  final AsyncValue<List<LeaderboardEntry>> rowsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);

    return CustomScrollView(
      // Material の RefreshIndicator は内容に重なるので、引っ張った分だけ
      // 場所を空ける Cupertino 版を使う（Android でも bouncing physics で動く）。
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        CupertinoSliverRefreshControl(
          onRefresh: () async {
            // epoch を進めると3つの provider が作り直され、キャッシュを飛ばして
            // 取り直す（以降その起動中はキャッシュを使わない）。
            ref.read(leaderboardRefreshEpochProvider.notifier).state++;
            await Future.wait([
              ref.read(leaderboardRowsProvider.future),
              ref.read(vocabDistributionProvider.future),
            ]);
          },
        ),
        rowsAsync.when(
          // 引っ張って更新のときは CupertinoSliverRefreshControl が回るので、
          // ここでもう一度スピナーを出さない（丸が2つ並んで見える）。
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          data: (entries) {
            if (entries.isEmpty) {
              return _MessageSliver(text: l10n.rankingUnrankedHint);
            }
            return SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConfig.defaultPadding,
              ),
              sliver: SliverList.builder(
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  // トップ3と自分の周辺が離れているときは、間を省略と分かるようにする
                  final gap = index > 0 &&
                      entry.rank > entries[index - 1].rank + 1;
                  if (!gap) return _RankRow(entry: entry);
                  return Column(
                    children: [
                      const _RankGap(),
                      _RankRow(entry: entry),
                    ],
                  );
                },
              ),
            );
          },
          loading: () => const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (error, stackTrace) {
            debugPrint('leaderboard load failed: $error');
            // デバッグビルドだけは原因（権限・index未作成など）をそのまま出す
            return _MessageSliver(
              text: kDebugMode ? '$error' : l10n.rankingLoadFailed,
            );
          },
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppConfig.defaultPadding,
            24,
            AppConfig.defaultPadding,
            8,
          ),
          sliver: SliverToBoxAdapter(child: _DistributionCard()),
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppConfig.defaultPadding,
            8,
            AppConfig.defaultPadding,
            32,
          ),
          sliver: SliverToBoxAdapter(child: _FreeCapNote()),
        ),
      ],
    );
  }
}

/// 自分の順位・語彙数・表示名
class _MyRankCard extends ConsumerWidget {
  const _MyRankCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final vocab = ref.watch(vocabStatsProvider).valueOrNull?.estimatedVocab ?? 0;
    // 上限に張り付いた帯は全員同点なので、1位と出すと嘘になる。順位を伏せる。
    final tied = isTiedBand(bandOf(vocab));
    final rank = tied ? null : ref.watch(myRankProvider).valueOrNull;

    return Card(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.rankingYourRank,
              style: textTheme.labelLarge
                  ?.copyWith(color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  rank == null ? '—' : l10n.rankingPosition(rank),
                  style: textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const Spacer(),
                Text(
                  l10n.vocabWords(vocab),
                  style: textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            // 順位は全体ではなく同じ語彙帯の中のもの。どこと比べた数字なのかを
            // 書かないと、帯が変わったときに順位が飛ぶ理由が読めない。
            if (rank != null) ...[
              const SizedBox(height: 4),
              Text(
                l10n.rankingBandScope(_bandLabel(l10n, bandOf(vocab))),
                style: textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onPrimaryContainer),
              ),
            ],
            if (rank == null) ...[
              const SizedBox(height: 4),
              Text(
                tied ? l10n.rankingCapTiedNote : l10n.rankingUnrankedHint,
                style: textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onPrimaryContainer),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 帯の表示名（「301〜600」「1001〜」）。順位カードと分布バーで同じ言い方をする。
String _bandLabel(L10n l10n, ({int min, int? max}) band) => band.max == null
    ? l10n.rankingBandOver(band.min)
    : l10n.rankingBandRange(band.min, band.max!);

class _RankRow extends StatelessWidget {
  const _RankRow({required this.entry});

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isMe = entry.isMe;

    final name = isMe
        ? (entry.nickname ?? l10n.rankingYou)
        : (entry.nickname ??
            l10n.rankingAnonymousName(
              entry.uid.substring(entry.uid.length - 4).toUpperCase(),
            ));
    final weight = isMe ? FontWeight.bold : FontWeight.normal;

    return Container(
      decoration: BoxDecoration(
        color: isMe ? colorScheme.primaryContainer : null,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              l10n.rankingPosition(entry.rank),
              style: textTheme.labelLarge?.copyWith(
                fontWeight: entry.rank <= 3 ? FontWeight.bold : weight,
                color: entry.rank <= 3 ? colorScheme.primary : null,
              ),
            ),
          ),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(fontWeight: weight),
            ),
          ),
          Text(
            l10n.vocabWords(entry.vocab),
            style: textTheme.bodyMedium?.copyWith(fontWeight: weight),
          ),
        ],
      ),
    );
  }
}

/// 順位が飛んでいることを示す区切り
class _RankGap extends StatelessWidget {
  const _RankGap();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              '⋯',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Divider(
              color: Theme.of(context).colorScheme.outlineVariant,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// 語彙スコアの分布。自分がどの帯にいるかを1本だけ色で示す。
///
/// 系列が1本なので凡例は置かず、見出しと自分の帯の直接ラベルで識別させる。
class _DistributionCard extends ConsumerWidget {
  const _DistributionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final distributionAsync = ref.watch(vocabDistributionProvider);
    final rank = ref.watch(myRankProvider).valueOrNull;

    return distributionAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (distribution) {
        if (distribution.total <= 0) return const SizedBox.shrink();
        final percentile = distribution.percentile(rank);
        final maxCount = distribution.bands
            .fold<int>(0, (value, band) => band.count > value ? band.count : value);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppConfig.defaultPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.rankingDistributionTitle,
                            style: textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            l10n.rankingDistributionSubtitle,
                            style: textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (percentile != null)
                      Text(
                        l10n.rankingPercentile(percentile),
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final band in distribution.bands)
                  _BandBar(band: band, maxCount: maxCount),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 分布の1行。バーは横向き（帯ラベルが縦に読めるほうが対応づけやすい）。
class _BandBar extends StatelessWidget {
  const _BandBar({required this.band, required this.maxCount});

  final VocabBand band;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final label = _bandLabel(l10n, (min: band.min, max: band.max));
    // 0人の帯も存在が分かるよう、ごく細い下地を残す
    final ratio = maxCount <= 0 ? 0.0 : band.count / maxCount;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: band.isMine
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
                fontWeight: band.isMine ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Container(
                    height: 10,
                    width: (constraints.maxWidth * ratio).clamp(
                      band.count > 0 ? 4.0 : 0.0,
                      constraints.maxWidth,
                    ),
                    decoration: BoxDecoration(
                      color: band.isMine
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '${band.count}',
              textAlign: TextAlign.right,
              style: textTheme.bodySmall?.copyWith(
                color: band.isMine
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
                fontWeight: band.isMine ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// free の語彙スコア上限の注記とプレミアム導線（タップ起点）
class _FreeCapNote extends ConsumerWidget {
  const _FreeCapNote();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(effectivePremiumProvider)) return const SizedBox.shrink();

    final l10n = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.rankingFreeCapNote(freeVocabScoreLimit),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        TextButton(
          onPressed: () => PaywallBottomSheet.show(context, source: 'ranking'),
          child: Text(l10n.vocabSeePremium),
        ),
      ],
    );
  }
}

class _MessageSliver extends StatelessWidget {
  const _MessageSliver({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ),
    );
  }
}
