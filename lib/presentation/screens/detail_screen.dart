// =============================================================================
// detail_screen.dart
// 例文の詳細表示画面。
// タイ語テキスト・発音・日本語訳に加え、単語ごとの分解（意味・文法的役割・声調）、
// 文脈情報（場面・文体・感情・使用シーン・文化的背景）、作成日を表示する。
// 各単語をタップすると声調解説ダイアログが開き、声調ルールを学べる。
// TTS（テキスト読み上げ）で全文・個別単語の発音を再生できる。
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../data/models/thai_sentence.dart';
import '../providers/sentence_provider.dart';
import '../providers/tts_provider.dart';
import '../tone_explanation_dialog.dart';

/// 例文の詳細表示画面。
///
/// [sentence] に渡されたタイ語例文の全情報をカード形式で表示する。
/// AppBarに「お気に入り」トグルと「共有（クリップボードコピー）」ボタンを配置。
/// 画面は以下の4つのセクションで構成される:
/// 1. メイン例文カード（タイ語・発音・日本語訳・TTS再生）
/// 2. 単語分解カード（各単語の意味・文法的役割・声調情報）
/// 3. 文脈カード（場面・文体・感情・使用シーン・文化的背景）
/// 4. メタデータカード（作成日）
class DetailScreen extends ConsumerStatefulWidget {
  /// 表示対象のタイ語例文データ
  final ThaiSentence sentence;

  const DetailScreen({super.key, required this.sentence});

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

/// [DetailScreen] のステート。
///
/// 単語分解セクションと文脈セクションの開閉状態を管理する。
class _DetailScreenState extends ConsumerState<DetailScreen> {
  /// 単語分解セクションの展開/折りたたみ状態
  bool _isWordBreakdownExpanded = true;
  /// 文脈情報セクションの展開/折りたたみ状態
  bool _isContextExpanded = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('例文の詳細'),
        actions: [
          // お気に入りトグルボタン（ハートアイコン）
          IconButton(
            icon: Icon(
              widget.sentence.isFavorite
                  ? Icons.favorite
                  : Icons.favorite_border,
            ),
            onPressed: _toggleFavorite,
            tooltip: 'お気に入り',
          ),
          // クリップボードにコピーするボタン
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareSentence,
            tooltip: '共有',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // メイン例文カード（タイ語テキスト・発音・日本語訳）
            _buildMainSentenceCard(),
            const SizedBox(height: 16),
            // 単語分解カード（各単語の詳細情報）
            _buildWordBreakdownCard(),
            const SizedBox(height: 16),
            // 文脈情報カード（場面・文体・感情など）
            _buildContextCard(),
            const SizedBox(height: 16),
            // メタデータカード（作成日）
            _buildMetadataCard(),
          ],
        ),
      ),
    );
  }

  /// メイン例文カードを構築する。
  ///
  /// タイ語テキスト（選択可能）とTTS再生ボタン、ローマ字発音表記、
  /// 日本語訳を縦に並べて表示する。
  Widget _buildMainSentenceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding * 1.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // タイ語テキスト（長押しでコピー可能）と音声再生ボタン
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    widget.sentence.thaiText,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                      fontSize: 32,
                    ),
                  ),
                ),
                // TTSで全文を音声再生するボタン
                IconButton(
                  icon: Icon(
                    Icons.volume_up,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: () {
                    ref.read(ttsServiceProvider).speak(widget.sentence.thaiText);
                  },
                  tooltip: '全文を再生',
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ローマ字による発音表記（アイコン付き）
            Row(
              children: [
                Icon(
                  Icons.record_voice_over,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    widget.sentence.pronunciation,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.8),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            // 日本語訳（翻訳アイコン付き）
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.translate,
                  size: 16,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    widget.sentence.japaneseTranslation,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 単語分解カードを構築する。
  ///
  /// 例文を構成する各単語を番号付きリストで表示する。
  /// ヘッダー部分をタップすると展開/折りたたみを切り替えられる。
  /// 各単語にはタイ語テキスト・発音・意味・文法的役割が表示され、
  /// タップすると声調解説ダイアログ（ToneExplanationDialog）が開く。
  Widget _buildWordBreakdownCard() {
    return Card(
      child: Column(
        children: [
          // ヘッダー部分（タップで展開/折りたたみ切り替え）
          InkWell(
            onTap: () {
              setState(() {
                _isWordBreakdownExpanded = !_isWordBreakdownExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(AppConfig.defaultPadding),
              child: Row(
                children: [
                  Icon(
                    Icons.list_alt,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '単語の分解 (${widget.sentence.wordBreakdowns.length})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // 展開/折りたたみアイコン
                  Icon(
                    _isWordBreakdownExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                  ),
                ],
              ),
            ),
          ),
          // 展開時のみ単語リストを表示
          if (_isWordBreakdownExpanded) ...[
            const Divider(height: 1),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.sentence.wordBreakdowns.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final word = widget.sentence.wordBreakdowns[index];
                return _buildWordBreakdownItem(word, index);
              },
            ),
          ],
        ],
      ),
    );
  }

  /// 個別の単語分解アイテムを構築する。
  ///
  /// 番号付きの円形バッジ、タイ語テキスト、TTS再生ボタン、発音、
  /// 意味、文法的役割（タグ表示）を含む。
  /// タップすると声調解説ダイアログが開き、その単語の声調分析を確認できる。
  Widget _buildWordBreakdownItem(word, int index) {
    return InkWell(
      // タップで声調解説ダイアログを表示
      onTap: () => ToneExplanationDialog.show(
        context,
        word.wordText,
        wordBreakdown: word,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 単語番号を示す円形バッジ
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // タイ語の単語テキスト
                          Text(
                            word.wordText,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          // 個別単語のTTS再生ボタン（ゆっくり再生）
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: IconButton(
                              icon: Icon(
                                Icons.volume_up,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                ref.read(ttsServiceProvider).speak(word.wordText, slow: true);
                              },
                              tooltip: '単語を再生',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // ローマ字による単語の発音表記
                      Text(
                        word.pronunciation,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.7),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 日本語での意味
            Text(word.meaning, style: Theme.of(context).textTheme.bodyMedium),
            // 文法的役割のタグ表示（存在する場合のみ）
            if (word.grammaticalRole != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.secondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  word.grammaticalRole!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.secondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
            // 「タップして声調を確認」ヒント
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.touch_app,
                  size: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 4),
                Text(
                  'タップして声調を確認',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 文脈情報カードを構築する。
  ///
  /// 例文が使われる場面・文体・感情/トーン・使用シーン・文化的背景を
  /// アイコン付きで表示する。ヘッダータップで展開/折りたたみ可能。
  /// 文脈情報が存在しない場合は空のウィジェットを返す。
  Widget _buildContextCard() {
    final sentenceContext = widget.sentence.context;
    if (sentenceContext == null) return const SizedBox.shrink();

    return Card(
      child: Column(
        children: [
          // ヘッダー部分（タップで展開/折りたたみ切り替え）
          InkWell(
            onTap: () {
              setState(() {
                _isContextExpanded = !_isContextExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(AppConfig.defaultPadding),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '文脈・使い方',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _isContextExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                ],
              ),
            ),
          ),
          // 展開時のみ文脈情報を表示
          if (_isContextExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppConfig.defaultPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 場面（例: 日常の挨拶、レストラン）
                  if (sentenceContext.topic != null) ...[
                    _buildContextItem(
                      Icons.location_on_outlined,
                      '場面',
                      sentenceContext.topic!,
                    ),
                    const SizedBox(height: 12),
                  ],
                  // 文体（例: 口語体、書き言葉）
                  if (sentenceContext.style != null) ...[
                    _buildContextItem(
                      Icons.text_fields_outlined,
                      '文体',
                      sentenceContext.style!,
                    ),
                    const SizedBox(height: 12),
                  ],
                  // 感情・トーン（例: 丁寧、カジュアル）
                  if (sentenceContext.emotion != null) ...[
                    _buildContextItem(
                      Icons.mood_outlined,
                      '感情・トーン',
                      sentenceContext.emotion!,
                    ),
                    const SizedBox(height: 12),
                  ],
                  // 使用シーン（例: 友人との会話で）
                  if (sentenceContext.usageScenarios != null) ...[
                    _buildContextItem(
                      Icons.tips_and_updates_outlined,
                      '使用シーン',
                      sentenceContext.usageScenarios!,
                    ),
                    const SizedBox(height: 12),
                  ],
                  // 文化的背景（例: タイでは年上への敬語が重要）
                  if (sentenceContext.culturalNotes != null) ...[
                    _buildContextItem(
                      Icons.info_outline,
                      '文化的背景',
                      sentenceContext.culturalNotes!,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 文脈情報の各項目（アイコン・ラベル・内容）を構築する。
  Widget _buildContextItem(IconData icon, String label, String content) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(content, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }

  /// メタデータカード（作成日）を構築する。
  Widget _buildMetadataCard() {
    final createdAt = widget.sentence.createdAt;
    final formattedDate = createdAt != null
        ? '${createdAt.year}/${createdAt.month}/${createdAt.day}'
        : '不明';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 16,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 8),
            Text(
              '作成日: $formattedDate',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// お気に入り状態をトグルする。
  ///
  /// DBに保存された例文（idがnullでない）に対してのみ動作する。
  /// 状態変更後にスナックバーでフィードバックを表示する。
  Future<void> _toggleFavorite() async {
    final sentenceId = widget.sentence.id;
    if (sentenceId == null) return;

    await ref
        .read(sentenceControllerProvider.notifier)
        .toggleFavorite(sentenceId, !widget.sentence.isFavorite);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.sentence.isFavorite ? 'お気に入りに追加しました' : 'お気に入りから削除しました',
          ),
          duration: const Duration(seconds: 1),
        ),
      );

      setState(() {
        // Trigger rebuild
      });
    }
  }

  /// 例文をクリップボードにコピーする。
  ///
  /// タイ語テキスト・発音・日本語訳をフォーマットしてクリップボードに設定し、
  /// コピー完了をスナックバーで通知する。
  void _shareSentence() {
    final text =
        '''
${widget.sentence.thaiText}
${widget.sentence.pronunciation}

${widget.sentence.japaneseTranslation}
''';

    Clipboard.setData(ClipboardData(text: text));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('クリップボードにコピーしました'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
