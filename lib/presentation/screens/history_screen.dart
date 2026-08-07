// =============================================================================
// history_screen.dart
// 過去に生成されたタイ語例文の一覧（履歴）画面。
// テキスト検索、個別/一括削除に対応。
// 各例文カードをタップすると詳細画面（DetailScreen）へ遷移する。
// スワイプ操作で個別削除も可能。
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../data/models/thai_sentence.dart';
import '../providers/sentence_provider.dart';
import 'detail_screen.dart';

/// 過去の例文一覧（履歴）画面。
///
/// SQLiteデータベースに保存された例文をリスト表示する。
/// テキスト検索・個別削除（スワイプ）・全件削除に対応。
/// プルダウンリフレッシュで一覧を更新できる。
class HistoryScreen extends ConsumerStatefulWidget {
  static const routeName = 'history';

  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

/// [HistoryScreen] のステート。
///
/// 検索クエリ、検索バーのテキストコントローラを管理する。
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
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).historyTitle),
        actions: [
          IconButton(
            icon: Icon(
              _showFavoritesOnly ? Icons.favorite : Icons.favorite_border,
              color: _showFavoritesOnly ? Colors.red : null,
            ),
            onPressed: () {
              setState(() {
                _showFavoritesOnly = !_showFavoritesOnly;
              });
            },
            tooltip: L10n.of(context).historyFavoritesOnly,
          ),
          // メニューボタン（全件削除）
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'delete_all') {
                _showDeleteAllConfirmation();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'delete_all',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep,
                        color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 8),
                    Text(L10n.of(context).historyDeleteAll,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 検索バー
          _buildSearchBar(),
          // 例文リスト
          Expanded(child: _buildSentenceList()),
        ],
      ),
    );
  }

  /// 検索バーを構築する。
  ///
  /// タイ語・日本語・ローマ字発音で例文を絞り込み検索できる。
  /// テキスト入力中はクリアボタンが表示される。
  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(AppConfig.defaultPadding),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: L10n.of(context).historySearchHint,
          prefixIcon: const Icon(Icons.search),
          // 入力中のみクリアボタンを表示
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
          ),
          filled: true,
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value.toLowerCase();
          });
        },
      ),
    );
  }

  /// 例文リストを構築する。
  ///
  /// お気に入りフィルタの状態に応じて全件/お気に入りのみを取得し、
  /// さらに検索クエリでフィルタリングして表示する。
  /// Riverpodの非同期プロバイダを監視し、loading/error/data状態を処理する。
  Widget _buildSentenceList() {
    final sentencesAsync = ref.watch(allSentencesProvider);

    return sentencesAsync.when(
      data: (sentences) {
        var filteredSentences = _showFavoritesOnly
            ? sentences.where((s) => s.isFavorite).toList()
            : sentences;

        // 検索クエリによるフィルタリング（タイ語・日本語・発音で絞り込み）
        if (_searchQuery.isNotEmpty) {
          filteredSentences = filteredSentences.where((sentence) {
            return sentence.thaiText.toLowerCase().contains(_searchQuery) ||
                sentence.japaneseTranslation.toLowerCase().contains(
                      _searchQuery,
                    ) ||
                sentence.pronunciation.toLowerCase().contains(_searchQuery);
          }).toList();
        }

        if (filteredSentences.isEmpty) {
          return _buildEmptyState();
        }

        // プルダウンリフレッシュ対応のリスト表示
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(allSentencesProvider);
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(AppConfig.defaultPadding),
            itemCount: filteredSentences.length,
            itemBuilder: (context, index) {
              return _buildSentenceCard(filteredSentences[index]);
            },
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
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              _showFavoritesOnly
                  ? L10n.of(context).historyEmptyFavorites
                  : (_searchQuery.isNotEmpty
                      ? L10n.of(context).historyEmptySearch
                      : L10n.of(context).historyEmpty),
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              _showFavoritesOnly
                  ? L10n.of(context).historyEmptyFavoritesHint
                  : (_searchQuery.isNotEmpty
                      ? L10n.of(context).historyEmptySearchHint
                      : L10n.of(context).historyEmptyHint),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// エラー状態の表示を構築する。
  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(L10n.of(context).commonError,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(
              error,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 全件削除の確認ダイアログを表示する。
  ///
  /// ユーザーが「削除」を選択した場合、DBから全例文を削除し、
  /// 履歴プロバイダを再取得して一覧を更新する。
  Future<void> _showDeleteAllConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L10n.of(context).historyDeleteAll),
        content: Text(L10n.of(context).historyDeleteAllConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L10n.of(context).commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(L10n.of(context).commonDelete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref
            .read(sentenceControllerProvider.notifier)
            .deleteAllSentences();
        // 一覧を再取得して更新
        ref.invalidate(allSentencesProvider);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.of(context).historyDeletedAll),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.of(context).historyDeleteFailed('$e')),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  /// 個別の例文カードを構築する。
  ///
  /// 作成日・タイ語テキスト・発音・日本語訳・単語数を表示する。
  /// タップで詳細画面へ遷移、左スワイプで個別削除が可能。
  /// お気に入り登録されている場合はハートアイコンを表示する。
  Widget _buildSentenceCard(ThaiSentence sentence) {
    final createdAt = sentence.createdAt;
    final formattedDate = createdAt != null
        ? '${createdAt.year}/${createdAt.month}/${createdAt.day}'
        : L10n.of(context).commonUnknown;

    return Dismissible(
      key: Key(sentence.id ?? ''),
      direction: DismissDirection.endToStart, // 左スワイプのみ
      // スワイプ時に表示される赤い削除背景
      background: Container(
        margin: const EdgeInsets.only(bottom: AppConfig.defaultPadding),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error,
          borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete, color: Theme.of(context).colorScheme.onError),
      ),
      // スワイプ時の確認ダイアログ
      confirmDismiss: (direction) async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(L10n.of(context).historyDeleteConfirmTitle),
            content: Text(L10n.of(context).historyDeleteConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(L10n.of(context).commonCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: Text(L10n.of(context).commonDelete),
              ),
            ],
          ),
        );

        if (confirmed == true) {
          try {
            await ref
                .read(sentenceControllerProvider.notifier)
                .deleteSentence(sentence.id!);
            // 一覧を再取得して更新
            ref.invalidate(allSentencesProvider);

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(L10n.of(context).historyDeletedOne),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
            return true;
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(L10n.of(context).historyDeleteFailed('$e')),
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
              );
            }
            return false;
          }
        }

        return false;
      },
      onDismissed: (direction) {
        // Deletion is handled in confirmDismiss
      },
      // 例文カードの本体
      child: Card(
        margin: const EdgeInsets.only(bottom: AppConfig.defaultPadding),
        child: InkWell(
          // タップで詳細画面へ遷移
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                settings: const RouteSettings(name: DetailScreen.routeName),
                builder: (context) => DetailScreen(
                  sentence: sentence,
                  source: 'history',
                ),
              ),
            );
            ref.invalidate(allSentencesProvider);
          },
          borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
          child: Padding(
            padding: const EdgeInsets.all(AppConfig.defaultPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ヘッダー行: 作成日とお気に入りアイコン
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        formattedDate,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () async {
                        await ref
                            .read(sentenceRepositoryProvider)
                            .toggleFavorite(sentence.id!, !sentence.isFavorite);
                        ref.invalidate(allSentencesProvider);
                      },
                      child: Icon(
                        sentence.isFavorite
                            ? Icons.favorite
                            : Icons.favorite_border,
                        size: 20,
                        color: sentence.isFavorite
                            ? Colors.red
                            : Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // タイ語テキスト（最大2行で省略）
                Text(
                  sentence.thaiText,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                        fontSize: 18,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                // ローマ字発音（1行で省略）
                Text(
                  sentence.pronunciation,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.7),
                        fontStyle: FontStyle.italic,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                // 日本語訳（最大2行で省略）
                Text(
                  sentence.japaneseTranslation,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                // 単語数の表示
                Row(
                  children: [
                    Icon(
                      Icons.list_alt,
                      size: 14,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      L10n.of(context)
                          .historyWordCount(sentence.wordBreakdowns.length),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
