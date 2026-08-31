// =============================================================================
// history_screen.dart
// 過去に生成されたタイ語例文の一覧（履歴）画面。
// 検索・お気に入り絞り込み・個別/一括削除に対応。
// 各行をタップすると詳細画面（DetailScreen）へ遷移する。
// 左スワイプで個別削除も可能。
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/generation_labels.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../data/models/thai_sentence.dart';
import '../providers/sentence_provider.dart';
import '../widgets/thai_highlight.dart';
import 'detail_screen.dart';

/// 過去の例文一覧（履歴）画面。
///
/// 一覧は1枚のカードに罫線区切りで積む。例文ごとにカードを分けると、
/// 面の切れ目が行数だけ増えて、ざっと目で追えなくなる。
class HistoryScreen extends ConsumerStatefulWidget {
  static const routeName = 'history';

  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

/// [HistoryScreen] のステート。
///
/// 検索クエリ、絞り込みの状態、検索バーのテキストコントローラを管理する。
class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  /// 検索クエリ（小文字正規化済み）
  String _searchQuery = '';

  /// お気に入りフィルタの状態
  bool _showFavoritesOnly = false;

  /// 検索バーのテキストコントローラ
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final sentencesAsync = ref.watch(allSentencesProvider);
    final all = sentencesAsync.valueOrNull ?? const <ThaiSentence>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.historyTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.historyDeleteAll,
            onPressed: all.isEmpty ? null : _showDeleteAllConfirmation,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(l10n),
          const SizedBox(height: 12),
          _buildFilterChips(l10n, all),
          const SizedBox(height: 12),
          Expanded(child: _buildSentenceList(sentencesAsync)),
        ],
      ),
    );
  }

  /// 検索バーを構築する。タイ語・日本語・発音で絞り込める。
  Widget _buildSearchBar(L10n l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppConfig.screenPadding, 4,
          AppConfig.screenPadding, 0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: l10n.historySearchHint,
          prefixIcon: const Icon(Icons.search, size: 20),
          // 入力中のみクリアボタンを表示
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
        ),
        onChanged: (value) {
          setState(() => _searchQuery = value.toLowerCase());
        },
      ),
    );
  }

  /// 「すべて / お気に入り」の絞り込みチップ。
  ///
  /// 件数を添えるのは、お気に入りが0件のときに空の一覧へ飛ばさないため。
  Widget _buildFilterChips(L10n l10n, List<ThaiSentence> all) {
    final favoriteCount = all.where((s) => s.isFavorite).length;
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppConfig.screenPadding),
        child: Row(
          children: [
            _buildFilterChip(
              label: l10n.historyFilterAll,
              count: all.length,
              selected: !_showFavoritesOnly,
              onTap: () => setState(() => _showFavoritesOnly = false),
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              label: l10n.historyFilterFavorites,
              count: favoriteCount,
              selected: _showFavoritesOnly,
              icon: Icons.favorite,
              iconColor: AppColors.vermilion,
              onTap: () => setState(() => _showFavoritesOnly = true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    Color? iconColor,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final foreground = selected ? cs.onPrimary : cs.onSurfaceVariant;
    return Material(
      color: selected ? cs.primary : cs.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? cs.primary : cs.outlineVariant),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                // ハートは選択の有無にかかわらず朱のまま。ここだけは
                // 「お気に入り」という意味の色で、状態の色ではない。
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: foreground.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 例文リストを構築する。
  ///
  /// 絞り込みと検索を適用したうえで、1枚のカードに罫線区切りで積む。
  Widget _buildSentenceList(AsyncValue<List<ThaiSentence>> sentencesAsync) {
    return sentencesAsync.when(
      data: (sentences) {
        var filtered = _showFavoritesOnly
            ? sentences.where((s) => s.isFavorite).toList()
            : sentences;

        // 検索クエリによるフィルタリング（タイ語・日本語・発音で絞り込み）
        if (_searchQuery.isNotEmpty) {
          filtered = filtered.where((sentence) {
            return sentence.thaiText.toLowerCase().contains(_searchQuery) ||
                sentence.japaneseTranslation
                    .toLowerCase()
                    .contains(_searchQuery) ||
                sentence.pronunciation.toLowerCase().contains(_searchQuery);
          }).toList();
        }

        if (filtered.isEmpty) return _buildEmptyState();

        final cs = Theme.of(context).colorScheme;
        final radius = BorderRadius.circular(AppConfig.cardBorderRadius);
        // カードは中身の高さに合わせたいので、リストの背面に敷く。
        // 全件を1つの Column にすると履歴が伸びた分だけ描画が重くなる。
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(allSentencesProvider),
          child: CustomScrollView(
            // 一覧が短くても引いて更新できるようにする。
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppConfig.screenPadding,
                  0,
                  AppConfig.screenPadding,
                  AppConfig.screenPadding,
                ),
                sliver: DecoratedSliver(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: radius,
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  sliver: SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) => const Divider(
                      height: 1,
                      indent: 14,
                      endIndent: 14,
                    ),
                    itemBuilder: (context, index) => _buildSentenceRow(
                      filtered[index],
                      isFirst: index == 0,
                      isLast: index == filtered.length - 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _buildErrorState(error.toString()),
    );
  }

  /// 例文が0件の場合の空状態表示を構築する。
  ///
  /// お気に入りフィルタ中/検索中/初期状態で異なるメッセージを表示する。
  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _showFavoritesOnly
                  ? Icons.favorite_border
                  : Icons.search_off_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 20),
            Text(
              _showFavoritesOnly
                  ? l10n.historyEmptyFavorites
                  : (_searchQuery.isNotEmpty
                      ? l10n.historyEmptySearch
                      : l10n.historyEmpty),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _showFavoritesOnly
                  ? l10n.historyEmptyFavoritesHint
                  : (_searchQuery.isNotEmpty
                      ? l10n.historyEmptySearchHint
                      : l10n.historyEmptyHint),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// エラー状態の表示を構築する。
  Widget _buildErrorState(String error) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 20),
            Text(L10n.of(context).commonError,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              error,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 全件削除の確認ダイアログを表示する。
  Future<void> _showDeleteAllConfirmation() async {
    final l10n = L10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.historyDeleteAll),
        content: Text(l10n.historyDeleteAllConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await ref.read(sentenceControllerProvider.notifier).deleteAllSentences();
      ref.invalidate(allSentencesProvider);
      if (mounted) _showSnack(l10n.historyDeletedAll);
    } catch (e) {
      if (mounted) _showSnack(l10n.historyDeleteFailed('$e'), isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor:
            isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  /// 個別の例文の行を構築する。
  ///
  /// タイ語（学習単語だけ金）・日本語訳・テーマ・作成日を1行にまとめる。
  /// 発音と単語数は一覧では読まないので出さない。詳細で見られる。
  Widget _buildSentenceRow(
    ThaiSentence sentence, {
    required bool isFirst,
    required bool isLast,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cardRadius = Radius.circular(AppConfig.cardBorderRadius);

    return Dismissible(
      key: Key(sentence.id ?? ''),
      direction: DismissDirection.endToStart, // 左スワイプのみ
      // スワイプ時に表示される赤い削除背景。カードの端の行だけ、
      // カードと同じ角丸で欠かす。
      background: Container(
        decoration: BoxDecoration(
          color: cs.error,
          borderRadius: BorderRadius.only(
            topRight: isFirst ? cardRadius : Radius.zero,
            bottomRight: isLast ? cardRadius : Radius.zero,
          ),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete, color: cs.onError),
      ),
      confirmDismiss: (direction) => _confirmDelete(sentence),
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              settings: const RouteSettings(name: DetailScreen.routeName),
              builder: (context) =>
                  DetailScreen(sentence: sentence, source: 'history'),
            ),
          );
          ref.invalidate(allSentencesProvider);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      buildTintedThaiText(
                        sentence.thaiText,
                        sentence.targetWords ?? const [],
                        theme.textTheme.titleMedium?.copyWith(
                              fontSize: 18,
                              // タイ文字は太らせると声調記号が潰れる。
                              fontWeight: FontWeight.w500,
                              height: 1.5,
                              color: cs.onSurface,
                            ) ??
                            const TextStyle(fontSize: 18),
                        AppColors.goldInk,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      sentence.japaneseTranslation,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    _buildMetaRow(sentence),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildFavoriteButton(sentence),
            ],
          ),
        ),
      ),
    );
  }

  /// テーマと作成日。読ませる情報ではないので、いちばん小さく置く。
  Widget _buildMetaRow(ThaiSentence sentence) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = L10n.of(context);
    final topic = sentence.context?.topic;
    final createdAt = sentence.createdAt;

    return Row(
      children: [
        if (topic != null && topic.isNotEmpty) ...[
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              topicLabel(l10n, topic).name,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onTertiaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            createdAt != null
                ? _formatDate(l10n, createdAt)
                : l10n.commonUnknown,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.8),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// 作成日。年が変わっているものだけ年を添える。
  /// 一覧のほとんどは今年のもので、毎行に年を出すと日付が読みにくい。
  String _formatDate(L10n l10n, DateTime createdAt) {
    if (createdAt.year == DateTime.now().year) {
      return l10n.historyDate(createdAt.month, createdAt.day);
    }
    return l10n.historyDateWithYear(
        createdAt.year, createdAt.month, createdAt.day);
  }

  Widget _buildFavoriteButton(ThaiSentence sentence) {
    final id = sentence.id;
    final l10n = L10n.of(context);
    return IconButton(
      constraints: const BoxConstraints.tightFor(
        width: AppConfig.minTapTarget,
        height: AppConfig.minTapTarget,
      ),
      padding: EdgeInsets.zero,
      icon: Icon(
        sentence.isFavorite ? Icons.favorite : Icons.favorite_border,
        size: 24,
      ),
      color: sentence.isFavorite
          ? AppColors.vermilion
          : Theme.of(context).colorScheme.outline,
      tooltip: sentence.isFavorite
          ? l10n.detailFavoriteRemove
          : l10n.detailFavoriteAdd,
      onPressed: id == null
          ? null
          : () async {
              await ref
                  .read(sentenceRepositoryProvider)
                  .toggleFavorite(id, !sentence.isFavorite);
              ref.invalidate(allSentencesProvider);
            },
    );
  }

  /// スワイプ削除の確認。削除できたときだけ行を消す。
  Future<bool> _confirmDelete(ThaiSentence sentence) async {
    final l10n = L10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.historyDeleteConfirmTitle),
        content: Text(l10n.historyDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;
    try {
      await ref
          .read(sentenceControllerProvider.notifier)
          .deleteSentence(sentence.id!);
      ref.invalidate(allSentencesProvider);
      if (mounted) _showSnack(l10n.historyDeletedOne);
      return true;
    } catch (e) {
      if (mounted) _showSnack(l10n.historyDeleteFailed('$e'), isError: true);
      return false;
    }
  }
}
