// =============================================================================
// detail_screen.dart
// 例文の詳細表示画面。
// タイ語テキスト・発音・日本語訳に加え、単語ごとの分解（意味・文法的役割・声調）、
// 文脈情報（場面・文体・感情・使用シーン・文化的背景）、作成日を表示する。
// 各単語をタップすると声調解説ダイアログが開き、声調ルールを学べる。
// TTS（テキスト読み上げ）で全文・個別単語の発音を再生できる。
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/generation_labels.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../data/models/thai_sentence.dart';
import '../../data/models/word_breakdown.dart';
import '../providers/analytics_provider.dart';
import '../providers/sentence_provider.dart';
import '../providers/tts_provider.dart';
import '../widgets/topic_picker.dart';
import '../tone_explanation_dialog.dart';
import '../widgets/sentence_audio_section.dart';
import '../widgets/thai_highlight.dart';
import 'tone_guide_screen.dart';

/// 例文の詳細表示画面。
///
/// [sentence] に渡されたタイ語例文の全情報をカード形式で表示する。
/// AppBarに「共有（クリップボードコピー）」ボタンを配置。
/// 画面は以下の4つのセクションで構成される:
/// 1. メイン例文カード（タイ語・発音・日本語訳・TTS再生）
/// 2. 単語分解カード（各単語の意味・文法的役割・声調情報）
/// 3. 文脈カード（場面・文体・感情・使用シーン・文化的背景）
/// 4. メタデータカード（作成日）
class DetailScreen extends ConsumerStatefulWidget {
  static const routeName = 'detail';

  /// 表示対象のタイ語例文データ
  final ThaiSentence sentence;
  final String source;

  const DetailScreen({
    super.key,
    required this.sentence,
    this.source = 'unknown',
  });

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

/// [DetailScreen] のステート。
///
/// 単語分解セクションと文脈セクションの開閉状態を管理する。
/// 右スワイプで戻ると判定する水平方向の速度しきい値（px/秒）
const double _swipeBackVelocity = 300;

class _DetailScreenState extends ConsumerState<DetailScreen> {
  /// お気に入りの状態。AppBar のハートで切り替える。
  late bool _isFavorite = widget.sentence.isFavorite;

  @override
  void initState() {
    super.initState();
    unawaited(
      ref.read(analyticsServiceProvider).logViewDetail(
            sentenceId: widget.sentence.id,
            source: widget.source,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildScaffold(context);
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).detailTitle),
        actions: [
          // クリップボードにコピーするボタン
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareSentence,
            tooltip: L10n.of(context).detailShare,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          _buildFavoriteAction(context),
        ],
      ),
      // 右スワイプで前の画面（例文ページ）に戻る
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null &&
              details.primaryVelocity! > _swipeBackVelocity) {
            Navigator.of(context).maybePop();
          }
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppConfig.screenPadding,
            AppConfig.defaultPadding,
            AppConfig.screenPadding,
            AppConfig.screenPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 例文カード（タイ語・発音・日本語訳）。学習タブと同じ深藍の面。
              _buildMainSentenceCard(),
              const SizedBox(height: 14),
              // 聞く／話すはカードの外。学習タブと同じ並び。
              SentenceAudioSection(
                sentence: widget.sentence,
                analyticsSource: 'detail_sentence',
                practiceScope: 'detail',
              ),
              const SizedBox(height: 20),
              _buildContextSection(),
              _buildWordSection(),
              const SizedBox(height: 16),
              _buildToneGuideLink(),
              const SizedBox(height: 12),
              _buildCreatedAtLabel(),
            ],
          ),
        ),
      ),
    );
  }

  /// AppBar のお気に入り。学習タブのカード足元と同じ操作をここに置く。
  Widget _buildFavoriteAction(BuildContext context) {
    final id = widget.sentence.id;
    if (id == null) return const SizedBox(width: 8);
    final l10n = L10n.of(context);
    return IconButton(
      icon: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border),
      color: _isFavorite
          ? AppColors.vermilion
          : Theme.of(context).colorScheme.onSurfaceVariant,
      tooltip: _isFavorite ? l10n.detailFavoriteRemove : l10n.detailFavoriteAdd,
      onPressed: () => unawaited(_toggleFavorite(id)),
    );
  }

  Future<void> _toggleFavorite(String id) async {
    final next = !_isFavorite;
    setState(() => _isFavorite = next);
    await ref.read(sentenceRepositoryProvider).toggleFavorite(id, next);
    // 学習タブに出ているのが同じ例文なら、そちらのハートも合わせる。
    // 履歴から開いた別の例文で今日の例文を置き換えないよう、idで確かめる。
    final state = ref.read(sentenceControllerProvider);
    if (state is SentenceStateSuccess && state.sentence.id == id) {
      ref
          .read(sentenceControllerProvider.notifier)
          .showSentence(state.sentence.copyWith(isFavorite: next));
    }
  }

  /// 区切りの見出し。細い罫を右へ伸ばして、次の塊の始まりだけを示す。
  Widget _buildSectionHeading(String label) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.08 * 12,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
        ],
      ),
    );
  }

  /// メイン例文カード。
  ///
  /// 学習単語は金で光らせ、タイ文字と読みで同じ語が対応して見えるようにする。
  Widget _buildMainSentenceCard() {
    final borderRadius = BorderRadius.circular(AppConfig.heroBorderRadius);
    // 深藍の面に載る中身は、テーマごと差し替えて色を合わせる。
    return Theme(
      data: Theme.of(context).copyWith(colorScheme: AppColors.onIndigo),
      child: Builder(
        builder: (context) {
          final cs = Theme.of(context).colorScheme;
          return Card(
            // 初回ガイドの1段目はカード全体を指す。
            color: AppColors.indigo,
            shape: RoundedRectangleBorder(borderRadius: borderRadius),
            child: Padding(
              padding: const EdgeInsets.all(AppConfig.defaultPadding * 1.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    buildHighlightedThaiText(
                      widget.sentence.thaiText,
                      widget.sentence.targetWords ?? const [],
                      Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w500,
                                height: 1.5,
                                fontSize: 32,
                              ) ??
                          TextStyle(fontSize: 32, color: cs.onSurface),
                      cs.primary,
                      words: widget.sentence.wordBreakdowns,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    buildHighlightedPronunciation(
                      widget.sentence,
                      Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ) ??
                          TextStyle(
                            color: cs.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // 金の細罫。タイ語と訳文のあいだに一本だけ引いて面を分ける。
                  Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.gold,
                          AppColors.gold.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.sentence.japaneseTranslation,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: cs.onSurface),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Set<String> get _targetWordSet => widget.sentence.targetWords?.toSet() ?? {};

  /// 単語のセクション。
  ///
  /// 折りたたみは持たない。詳細を開いた目的がここなので、毎回開く手間を挟まない。
  Widget _buildWordSection() {
    final words = widget.sentence.wordBreakdowns;
    if (words.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeading(L10n.of(context).detailWordsSection),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < words.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: AppConfig.defaultPadding,
                    endIndent: AppConfig.defaultPadding,
                  ),
                _buildWordBreakdownItem(words[i], i),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 単語の詳細（声調解説）を開く。
  Future<void> _openWordDetail(WordBreakdown word, int index) async {
    await ToneExplanationDialog.show(
      context,
      word.wordText,
      wordBreakdown: word,
    );
  }

  /// 個別の単語。タイ語・読み・品詞・意味を1行ずつ。押すと声調解説が開く。
  Widget _buildWordBreakdownItem(WordBreakdown word, int index) {
    final isTarget = _targetWordSet.contains(word.wordText);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: () => unawaited(_openWordDetail(word, index)),
      child: Container(
        // 学習単語の行は左の金の罫と、語そのものの金で示す。記号を1つ足す
        // より、行として「ここ」と分かる方が並びの中で見つけやすい。
        decoration: isTarget
            ? const BoxDecoration(
                border: Border(
                  left: BorderSide(color: AppColors.goldInk, width: 3),
                ),
              )
            : null,
        padding: EdgeInsets.fromLTRB(isTarget ? 13 : 16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Semantics(
                        // 色と罫でしか出していないので、読み上げにも乗せる。
                        label: isTarget
                            ? '${word.wordText}、${L10n.of(context).todaysWords(1)}'
                            : null,
                        child: Text(
                          word.wordText,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                            color: isTarget ? AppColors.goldInk : null,
                          ),
                        ),
                      ),
                      Text(
                        word.pronunciation,
                        // 読みは金にしない。全行が金だと、学習単語の金が
                        // 埋もれて何の色なのか読み取れない。
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      if (word.grammaticalRole != null)
                        _buildRoleTag(word.grammaticalRole!),
                    ],
                  ),
                ),
                // 単語だけをゆっくり鳴らす。声調解説には音が無いので、
                // ここを外すと語単位で聞く手が無くなる。
                IconButton(
                  icon: const Icon(Icons.volume_up, size: 18),
                  color: cs.onSurfaceVariant,
                  constraints: const BoxConstraints.tightFor(
                    width: AppConfig.minTapTarget,
                    height: AppConfig.minTapTarget,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    unawaited(
                      ref.read(analyticsServiceProvider).logPlayTts(
                            contentType: 'word',
                            text: word.wordText,
                            sentenceId: widget.sentence.id,
                            source: 'detail_word',
                          ),
                    );
                    ref
                        .read(ttsServiceProvider)
                        .speak(word.wordText, slow: true);
                  },
                  tooltip: L10n.of(context).quizPlayWord,
                ),
                Icon(Icons.chevron_right, size: 20, color: cs.outline),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              word.meaning,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (word.notes != null && word.notes!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                word.notes!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onTertiaryContainer,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRoleTag(String role) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        role,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 使い方のセクション。場面・文体・解説を左のラベルで引き当てる。
  /// 文脈情報が無い例文では丸ごと出さない。
  Widget _buildContextSection() {
    final sentenceContext = widget.sentence.context;
    if (sentenceContext == null) return const SizedBox.shrink();

    final l10n = L10n.of(context);
    final items = <(String, String)>[
      if (sentenceContext.topic != null)
        // サーバーが決めたテーマ識別子（日本語）。表示だけ訳す。
        (l10n.detailContextTopic, topicShortLabel(l10n, sentenceContext.topic)),
      if (sentenceContext.style != null)
        // 文体は履歴の集計キーなので日本語のまま返る。表示だけ訳す。
        (l10n.detailContextStyle, styleLabel(l10n, sentenceContext.style!)),
      if (sentenceContext.emotion != null)
        (l10n.detailContextEmotion, sentenceContext.emotion!),
      if (sentenceContext.usageScenarios != null)
        (l10n.detailContextUsage, sentenceContext.usageScenarios!),
      if (sentenceContext.culturalNotes != null)
        (l10n.detailContextCulture, sentenceContext.culturalNotes!),
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeading(l10n.detailUsageSection),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            // ラベルの列は中身に合わせて伸ばす。固定幅にすると、語の長い
            // 言語でラベルが単語の途中で折れる（英語の Cultural background）。
            child: Table(
              columnWidths: const {
                0: IntrinsicColumnWidth(),
                1: FlexColumnWidth(),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              children: [
                for (var i = 0; i < items.length; i++)
                  _buildContextRow(items[i].$1, items[i].$2, isFirst: i == 0),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  /// 使い方の1項目。ラベルの列幅は [Table] が揃えるので、内容の頭は縦に通る。
  TableRow _buildContextRow(String label, String content,
      {required bool isFirst}) {
    final theme = Theme.of(context);
    final top = isFirst ? 0.0 : 12.0;
    return TableRow(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(0, top, 12, 0),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.gold,
              fontWeight: FontWeight.w700,
              // ラベルと内容で行の高さが違うと、1行の項目で頭がずれる。
              height: 1.5,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: top),
          child: Text(
            content,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ),
      ],
    );
  }

  /// 声調ガイドへの導線。単語を見て「なぜこの声調か」が気になった流れで開ける。
  Widget _buildToneGuideLink() {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: ToneGuideScreen.routeName),
            builder: (context) => const ToneGuideScreen(),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              const Icon(Icons.show_chart, size: 20, color: AppColors.gold),
              const SizedBox(width: 12),
              Text(
                l10n.settingsToneGuide,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.settingsToneGuideSubtitle,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 20, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }

  /// 作成日。読むための情報ではないので、面を持たせず小さく置く。
  Widget _buildCreatedAtLabel() {
    final createdAt = widget.sentence.createdAt;
    final formattedDate = createdAt != null
        ? '${createdAt.year}/${createdAt.month}/${createdAt.day}'
        : L10n.of(context).commonUnknown;
    final theme = Theme.of(context);
    return Text(
      L10n.of(context).detailCreatedAt(formattedDate),
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    );
  }

  /// 例文をクリップボードにコピーする。
  ///
  /// タイ語テキスト・発音・日本語訳をフォーマットしてクリップボードに設定し、
  /// コピー完了をスナックバーで通知する。
  void _shareSentence() {
    final text = '''
${widget.sentence.thaiText}
${widget.sentence.pronunciation}

${widget.sentence.japaneseTranslation}
''';

    Clipboard.setData(ClipboardData(text: text));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(L10n.of(context).detailCopied),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
