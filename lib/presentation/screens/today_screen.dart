import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/app_config.dart';
import '../../core/quota_error.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../data/models/syllable.dart';
import '../../data/models/thai_sentence.dart';
import '../../data/models/word_breakdown.dart';
import '../providers/daily_set_provider.dart';
import '../providers/analytics_provider.dart';
import '../providers/sentence_provider.dart';
import '../providers/quiz_offer_experiment_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tts_provider.dart';
import '../providers/remaining_quota_provider.dart';
import '../providers/vocab_stats_provider.dart';
import '../widgets/topic_picker.dart';
import '../widgets/quiz_offer.dart';
import '../widgets/sentence_audio_section.dart';
import '../widgets/thai_highlight.dart';
import '../widgets/sign_in_reminder_banner.dart';
import '../widgets/loading_tip_carousel.dart';
import '../widgets/vocab_level.dart';
import 'detail_screen.dart';
import 'paywall_screen.dart';

/// 例文の生成上限に当たった画面から開くペイウォールの source。
/// paywall_banner(shown) と tap_paywall で同じ値を使い、CTR を
/// learning_banner_* と同じ形で比べられるようにしている。
const String _quotaPaywallSource = 'sentence_quota_error';

typedef LearningQuizStartCallback = void Function(
  ThaiSentence sentence,
  String? offerSource,
);

/// 配信セットの進み具合（「1 / 5」）。
///
/// 例文 → 確認クイズ → …（5本）… → まとめクイズ が1サイクルであることは、
/// 全体の本数が見えないと伝わらない。元の課題（サイクルがわかりにくい）への
/// 直接の答えがこの表示で、5本まとめ配信はその前提条件にすぎない。
/// セットを消化していないとき（自発生成）は何も出さない。
class DailySetProgress extends ConsumerWidget {
  const DailySetProgress({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final set = ref.watch(dailySetProvider);
    // 1本だけのもの（旧形式の配信・クォータ残1）は「セット」ではないので出さない。
    if (!set.isActive || set.total <= 1) return const SizedBox.shrink();

    final l10n = L10n.of(context);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // まとめクイズまであと何本か。「今日のセット」だと打ち止めに読めるので、
    // 到達点の側から数える。
    final remaining = set.total - set.position;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                // 残り0本（セットの最後）で「あと0本」にならないよう分ける。
                remaining > 0
                    ? l10n.learnDailySetRemaining(remaining)
                    : l10n.learnDailySetLast,
                style: textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                l10n.learnDailySetProgress(set.position, set.total),
                style: textTheme.labelMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < set.total; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color:
                          i <= set.index ? AppColors.gold : cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Today's sentence screen
class TodayScreen extends ConsumerStatefulWidget {
  final LearningQuizStartCallback? onStartQuiz;

  /// 今日の例文を取り直す。サンプル表示から抜ける唯一の手段なので、
  /// 空状態のカードにこの導線を出す。
  final Future<void> Function()? onReload;

  const TodayScreen({
    super.key,
    this.onStartQuiz,
    this.onReload,
  });

  /// デフォルトの挨拶例文（サンプル、履歴には保存されない）。
  /// 訳・品詞・文脈は表示用の文言なので言語に追従させる。
  static ThaiSentence defaultGreetingSentence(L10n l10n) => ThaiSentence(
        id: null, // idがnullなのでDBには保存されない
        thaiText: 'สวัสดีครับ',
        pronunciation: 'sawatdii khrap',
        japaneseTranslation: l10n.sampleGreetingTranslation,
        wordBreakdowns: [
          WordBreakdown(
            wordText: 'สวัสดี',
            pronunciation: 'sà-wàt-dii',
            meaning: l10n.sampleGreetingWord1Meaning,
            grammaticalRole: l10n.sampleGreetingWord1Role,
            wordOrder: 0,
            syllables: [
              Syllable(
                text: 'สวัส',
                initialConsonant: 'สว',
                consonantClass: 'high',
                tone: 'low',
                toneMark: 'none',
                syllableType: 'dead',
              ),
              Syllable(
                text: 'ดี',
                initialConsonant: 'ด',
                consonantClass: 'middle',
                tone: 'mid',
                toneMark: 'none',
                syllableType: 'live',
              ),
            ],
          ),
          WordBreakdown(
            wordText: 'ครับ',
            pronunciation: 'khráp',
            meaning: l10n.sampleGreetingWord2Meaning,
            grammaticalRole: l10n.sampleGreetingWord2Role,
            wordOrder: 1,
            syllables: [
              Syllable(
                text: 'ครับ',
                initialConsonant: 'คร',
                consonantClass: 'low',
                tone: 'high',
                toneMark: 'none',
                syllableType: 'dead',
                hasShortVowel: true,
              ),
            ],
          ),
        ],
        context: SentenceContext(
          topic: l10n.sampleGreetingTopic,
          style: l10n.sampleGreetingStyle,
          emotion: l10n.sampleGreetingEmotion,
          usageScenarios: l10n.sampleGreetingUsage,
        ),
        createdAt: null,
        generationTier: 'free',
      );

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  /// 「確認クイズへ」ボタンの位置特定用（導線が画面内にあるかの判定に使う）。
  final GlobalKey _quizButtonKey = GlobalKey();
  final GlobalKey _sentenceScrollViewportKey = GlobalKey();
  final ScrollController _sentenceScrollController = ScrollController();
  final Set<String> _scheduledQuizOfferShown = {};
  final Set<String> _loggedQuizOfferShown = {};
  final Set<String> _handledQuizOfferTaps = {};
  bool _quizOfferAssignmentHandled = false;

  /// 再読み込み中か。押しっぱなしを防ぐためだけの状態。
  bool _reloading = false;

  /// 上限到達時のペイウォール導線の shown を二重に送らないためのフラグ。
  /// build はエラー表示のまま何度も走るので、State の生存期間中1回に絞る。
  bool _quotaPaywallImpressionLogged = false;

  @override
  void initState() {
    super.initState();
    _sentenceScrollController.addListener(_maybeLogVisibleQuizOffer);
  }

  @override
  void dispose() {
    _sentenceScrollController
      ..removeListener(_maybeLogVisibleQuizOffer)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(vocabStatsProvider, (prev, next) {
      final prevVocab = prev?.valueOrNull?.estimatedVocab ?? 0;
      final nextVocab = next.valueOrNull?.estimatedVocab ?? 0;
      if (nextVocab > prevVocab) {
        _checkLevelUp(nextVocab);
      }
    });
    final sentenceState = ref.watch(sentenceControllerProvider);
    final quizOfferVariant = ref.watch(quizOfferVariantProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: AppConfig.screenPadding,
        // クイズ・まとめクイズの AppBar（navLearn）と同じ名前にする。
        // 「今日の例文」だと1本で終わる画面に見えるうえ、すぐ下の
        // 「今日のセット 1 / 5」と「今日の」が重なる。日付と本数は
        // その行に持たせ、ここはタブの名前だけを名乗る。
        title: Text(
          L10n.of(context).navLearn,
          style: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
                fontSize: 21,
                letterSpacing: 0.02 * 21,
              ),
        ),
        actions: [
          _buildVocabScoreChip(context),
          const SizedBox(width: AppConfig.screenPadding),
        ],
      ),
      body: _buildSentenceContent(
        context,
        sentenceState,
        quizOfferVariant,
      ),
    );
  }

  /// ヘッダー右の語彙スコア。学習の手応えを常に見える場所に置く。
  /// 内訳は設定画面の語彙スコアカードで見せるので、ここは表示だけ。
  Widget _buildVocabScoreChip(BuildContext context) {
    final stats = ref.watch(vocabStatsProvider).valueOrNull;
    if (stats == null) return const SizedBox.shrink();

    final isPremium = ref.watch(effectivePremiumProvider);
    final vocab = isPremium
        ? stats.estimatedVocab
        : stats.estimatedVocab.clamp(0, freeVocabScoreLimit).toInt();
    final levelId = vocabLevel(vocab);
    final level = vocabLevelLabel(L10n.of(context), levelId);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(vocabLevelIcon(levelId), size: 15, color: AppColors.gold),
          const SizedBox(width: 7),
          Text(
            L10n.of(context).vocabWords(vocab),
            style: textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            level,
            style: textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Build sentence content based on state
  Widget _buildSentenceContent(
    BuildContext context,
    SentenceState state,
    QuizOfferVariant? quizOfferVariant,
  ) {
    if (state is SentenceStateLoading) {
      return _buildLoadingState();
    } else if (state is SentenceStateSuccess) {
      return _buildSuccessState(
        context,
        state.sentence,
        quizOfferVariant,
      );
    } else if (state is SentenceStateError) {
      return _buildErrorState(context, state.message);
    } else if (state is SentenceStateEmpty) {
      return _buildEmptyState(context);
    }
    // 読み込み中。ここでサンプルを出すと、起動処理が終わらないときに
    // 「サンプルのまま切り替わらない」ようにしか見えない。
    return _buildLoadingState();
  }

  /// Build loading state
  Widget _buildLoadingState() {
    return LoadingCard(message: L10n.of(context).sentencePreparing);
  }

  /// Build success state with single sentence
  Widget _buildSuccessState(
    BuildContext context,
    ThaiSentence sentence,
    QuizOfferVariant? quizOfferVariant,
  ) {
    if (quizOfferVariant != null && quizOfferVariant.participatesInExperiment) {
      _scheduleQuizOfferShown(sentence, quizOfferVariant);
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            key: _sentenceScrollViewportKey,
            controller: _sentenceScrollController,
            padding: const EdgeInsets.fromLTRB(
              AppConfig.screenPadding,
              AppConfig.defaultPadding,
              AppConfig.screenPadding,
              AppConfig.screenPadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SignInReminderBanner(),
                // セットの何本目かを最上部に置く。読み始める前に「今日は
                // あと何本で一巡か」が見えるようにするため。
                const DailySetProgress(),
                // 並びはモックのとおり。次に届くテーマ → 例文 → 聞く/話す →
                // 学習単語。例文を先に読ませ、そのあとで単語を確かめる。
                const NextSentenceTopicLabel(
                  paywallSource: 'learn_next_topic',
                  banner: true,
                  // テーマの変更はまとめクイズの後だけ。セットの途中で
                  // 変えてもその5本には効かないので、ここは表示のみ。
                  readOnly: true,
                ),
                const SizedBox(height: 14),
                _buildSentenceCard(context, sentence),
                // 聞くは例文の付属。ここだけ詰めて1組に見せる。
                const SizedBox(height: 8),
                SentenceAudioSection(
                  sentence: sentence,
                  analyticsSource: 'today_sentence',
                  practiceScope: 'home_card',
                  // 発音練習は詳細画面だけに置く。学習タブは
                  // 読む → 覚えたか確認 の一本道に保つ。
                  showPractice: false,
                ),
                // ここで組が変わる（読む → 覚える）。上の間隔より広く取る。
                // ボタン自身が上下に余白を持つので、見た目の差は数値より開く。
                const SizedBox(height: 14),
                _buildTargetWordsSection(context, sentence),
                // 導線は学習単語のすぐ下に置く。「この単語を覚える → 確認する」
                // が一続きに見える距離で、別セクションには見せない。
                if (quizOfferVariant != null) ...[
                  const SizedBox(height: 12),
                  QuizOffer(
                    variant: quizOfferVariant,
                    targetKey: _quizButtonKey,
                    onPressed: () =>
                        _handleQuizOfferTap(sentence, quizOfferVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _quizOfferEventKey(
    ThaiSentence sentence,
    QuizOfferVariant variant,
  ) {
    final sentenceKey = sentence.id ??
        '${sentence.thaiText}|${sentence.createdAt?.millisecondsSinceEpoch}';
    return '$sentenceKey|${variant.analyticsSource}';
  }

  void _scheduleQuizOfferShown(
    ThaiSentence sentence,
    QuizOfferVariant variant,
  ) {
    final eventKey = _quizOfferEventKey(sentence, variant);
    if (_loggedQuizOfferShown.contains(eventKey) ||
        !_scheduledQuizOfferShown.add(eventKey)) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _scheduledQuizOfferShown.remove(eventKey);
      if (!mounted) return;

      final currentState = ref.read(sentenceControllerProvider);
      final currentVariant = ref.read(quizOfferVariantProvider).valueOrNull;
      if (currentState is! SentenceStateSuccess ||
          currentVariant != variant ||
          _quizOfferEventKey(currentState.sentence, variant) != eventKey) {
        return;
      }

      await _logQuizOfferAssignmentOnce(variant);
      if (!mounted) return;

      _logQuizOfferShownIfVisible(eventKey, variant);
    });
  }

  Future<void> _logQuizOfferAssignmentOnce(QuizOfferVariant variant) async {
    if (_quizOfferAssignmentHandled) return;
    _quizOfferAssignmentHandled = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final loggedSource =
          prefs.getString(AppConfig.prefKeyQuizOfferAssignmentLoggedV1);
      if (loggedSource == variant.analyticsSource) return;

      unawaited(
        ref.read(analyticsServiceProvider).logQuizOffer(
              action: 'assigned',
              source: variant.analyticsSource,
            ),
      );
      unawaited(
        prefs.setString(
          AppConfig.prefKeyQuizOfferAssignmentLoggedV1,
          variant.analyticsSource,
        ),
      );
    } catch (_) {
      // 保存領域が使えなくても、この画面ライフサイクル中は上のboolで一度に抑える。
      unawaited(
        ref.read(analyticsServiceProvider).logQuizOffer(
              action: 'assigned',
              source: variant.analyticsSource,
            ),
      );
    }
  }

  void _maybeLogVisibleQuizOffer() {
    if (!mounted) return;
    final sentenceState = ref.read(sentenceControllerProvider);
    final variant = ref.read(quizOfferVariantProvider).valueOrNull;
    if (sentenceState is! SentenceStateSuccess || variant == null) return;

    _logQuizOfferShownIfVisible(
      _quizOfferEventKey(sentenceState.sentence, variant),
      variant,
    );
  }

  void _logQuizOfferShownIfVisible(
    String eventKey,
    QuizOfferVariant variant,
  ) {
    // 割り当て保存に失敗した端末は control UI を見せるだけで実験母集団には
    // 入れない。初回描画だけでなくスクロール経由でも必ず除外する。
    if (!variant.participatesInExperiment ||
        _loggedQuizOfferShown.contains(eventKey) ||
        !_isQuizOfferVisible(variant)) {
      return;
    }
    _loggedQuizOfferShown.add(eventKey);

    unawaited(
      ref.read(analyticsServiceProvider).logQuizOffer(
            action: 'shown',
            source: variant.analyticsSource,
          ),
    );
  }

  bool _isQuizOfferVisible(QuizOfferVariant variant) {
    final targetContext = _quizButtonKey.currentContext;
    final targetBox = targetContext?.findRenderObject() as RenderBox?;
    if (targetContext == null ||
        !targetContext.mounted ||
        !TickerMode.getValuesNotifier(targetContext).value.enabled ||
        ModalRoute.of(context)?.isCurrent != true ||
        targetBox == null ||
        !targetBox.hasSize) {
      return false;
    }

    // 導線は学習単語の直下に必ず描画するので、描画済みなら可視とみなす。
    return true;
  }

  void _handleQuizOfferTap(
    ThaiSentence sentence,
    QuizOfferVariant variant,
  ) {
    if (variant.participatesInExperiment) {
      final eventKey = _quizOfferEventKey(sentence, variant);
      if (!_handledQuizOfferTaps.add(eventKey)) return;

      unawaited(
        ref.read(analyticsServiceProvider).logQuizOffer(
              action: 'tapped',
              source: variant.analyticsSource,
            ),
      );
    }
    widget.onStartQuiz?.call(
      sentence,
      variant.participatesInExperiment ? variant.analyticsSource : null,
    );
  }

  Widget _buildTargetWordsSection(
    BuildContext context,
    ThaiSentence sentence,
  ) {
    final targetWords = sentence.targetWords;
    if (targetWords == null || targetWords.isEmpty) {
      return const SizedBox.shrink();
    }

    final breakdownMap = {
      for (final wb in sentence.wordBreakdowns) wb.wordText: wb,
    };

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 見出しは字だけだと本文に埋もれるので、右へ罫線を伸ばして区切る。
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Text(
                L10n.of(context).todaysWords(targetWords.length),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.08 * 12,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Divider(color: cs.outlineVariant, height: 1)),
            ],
          ),
        ),
        ...targetWords.map((word) {
          final wb = breakdownMap[word] ??
              breakdownMap['$wordๆ'] ??
              (word.endsWith('ๆ')
                  ? breakdownMap[word.replaceAll('ๆ', '')]
                  : null);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            // 面はテーマの Card（白＋1px罫線）に任せる。塗り分けると
            // 例文カードの深藍と競って、どちらが主役か分からなくなる。
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                word,
                                // タイ文字は bold だと声調記号が潰れる。
                                // 色は読みと揃える。例文カードの金と同じ語だと
                                // 一目で結び付く。
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.goldInk,
                                ),
                              ),
                              if (wb != null) ...[
                                const SizedBox(width: 9),
                                Text(
                                  wb.pronunciation,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.goldInk,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (wb != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              wb.meaning,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (wb != null)
                      // 44px の丸を敷いて、押せる場所と大きさを見せる。
                      IconButton(
                        icon: const Icon(Icons.volume_up_outlined, size: 20),
                        onPressed: () {
                          ref.read(ttsServiceProvider).speak(word);
                        },
                        style: IconButton.styleFrom(
                          backgroundColor: cs.surfaceContainerHigh,
                          foregroundColor: cs.primary,
                          minimumSize: const Size.square(
                            AppConfig.minTapTarget,
                          ),
                        ),
                        tooltip: L10n.of(context).playPronunciation,
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  /// Build a sentence card (shared between single and batch views)
  Widget _buildSentenceCard(
    BuildContext context,
    ThaiSentence sentence,
  ) {
    final borderRadius = BorderRadius.circular(AppConfig.heroBorderRadius);
    // カードの中身（再生ボタン・シークバー・ティアバッジ）は ColorScheme から
    // 色を引くので、面を深藍にする代わりにスキームごと差し替える。
    // 各ウィジェットに「濃い面の上か」を渡して回らずに済む。
    return Theme(
      data: Theme.of(context).copyWith(colorScheme: AppColors.onIndigo),
      child: Builder(
          builder: (context) => _buildSentenceCardBody(
                context,
                sentence,
                borderRadius: borderRadius,
              )),
    );
  }

  Widget _buildSentenceCardBody(
    BuildContext context,
    ThaiSentence sentence, {
    required BorderRadius borderRadius,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: AppColors.indigo,
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      child: Stack(
        children: [
          InkWell(
            onTap: () async {
              // 遷移してもこのカードは破棄されない。詳細画面のプレイヤーと
              // TTSを奪い合わないよう、ここで再生を止めておく。
              unawaited(ref.read(ttsServiceProvider).stopAll());
              await Navigator.push(
                context,
                MaterialPageRoute(
                  settings: const RouteSettings(name: DetailScreen.routeName),
                  builder: (context) => DetailScreen(
                    sentence: sentence,
                    source: 'today',
                  ),
                ),
              );
            },
            borderRadius: borderRadius,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConfig.defaultPadding * 1.5,
                AppConfig.defaultPadding * 2.5,
                AppConfig.defaultPadding * 1.5,
                AppConfig.defaultPadding * 1.5,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    buildHighlightedThaiText(
                      sentence.thaiText,
                      sentence.targetWords ?? [],
                      Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w500,
                                height: 1.5,
                                fontSize: 32,
                              ) ??
                          TextStyle(fontSize: 32, color: cs.onSurface),
                      cs.primary,
                      words: sentence.wordBreakdowns,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Pronunciation
                  Text.rich(
                    buildHighlightedPronunciation(
                      sentence,
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
                    sentence.japaneseTranslation,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: cs.onSurface),
                  ),
                  const SizedBox(height: 14),
                  // カードの足元。テーマ・お気に入り・詳細への続きを1行にまとめる。
                  Row(
                    children: [
                      if (sentence.context?.topic != null)
                        _buildSentenceTopicTag(context, sentence),
                      const Spacer(),
                      _buildFavoriteButton(context, sentence),
                      // 「>」だけだと何へ続くのか読めない。語を添える。
                      Text(
                        L10n.of(context).learnOpenDetail,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  cs.onSurfaceVariant.withValues(alpha: 0.85),
                            ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 14,
            right: 16,
            child: _buildSentenceTierBadge(context, sentence),
          ),
        ],
      ),
    );
  }

  /// カード足元のお気に入り。タップ領域は 44px。
  Widget _buildFavoriteButton(BuildContext context, ThaiSentence sentence) {
    if (sentence.id == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await ref
            .read(sentenceRepositoryProvider)
            .toggleFavorite(sentence.id!, !sentence.isFavorite);
        final updated = sentence.copyWith(isFavorite: !sentence.isFavorite);
        ref.read(sentenceControllerProvider.notifier).showSentence(updated);
      },
      child: SizedBox(
        width: AppConfig.minTapTarget,
        height: AppConfig.minTapTarget,
        child: Icon(
          sentence.isFavorite ? Icons.favorite : Icons.favorite_border,
          size: 24,
          color: sentence.isFavorite
              ? AppColors.vermilion
              : cs.onSurfaceVariant.withValues(alpha: 0.8),
        ),
      ),
    );
  }

  /// カード足元のテーマタグ。この例文がどの場面のものかを示す。
  Widget _buildSentenceTopicTag(BuildContext context, ThaiSentence sentence) {
    final cs = Theme.of(context).colorScheme;
    final label = topicShortLabel(L10n.of(context), sentence.context?.topic);
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sell_outlined, size: 14, color: AppColors.gold),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildSentenceTierBadge(
    BuildContext context,
    ThaiSentence sentence,
  ) {
    final cs = Theme.of(context).colorScheme;
    final hasStoredTier = sentence.generationTier != null;
    final showPremium = hasStoredTier
        ? sentence.wasGeneratedWithPremiumSpec
        : _legacySentenceLooksPremium();
    final foreground = cs.onSurfaceVariant;

    return Tooltip(
      message: showPremium
          ? L10n.of(context).badgePremiumSentence
          : L10n.of(context).badgeFreeSentence,
      // カードの角に食い込ませると角丸が欠けて見える。内側のピルにする。
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border.all(
            color: showPremium
                ? AppColors.gold.withValues(alpha: 0.45)
                : cs.outlineVariant.withValues(alpha: 0.55),
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          showPremium ? 'PREMIUM' : 'FREE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
                letterSpacing: 0.6,
                color: showPremium
                    ? AppColors.gold
                    : foreground.withValues(alpha: 0.82),
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }

  bool _legacySentenceLooksPremium() {
    // 体験中も premium スペックで生成しているので premium 表示にする。
    return ref.watch(effectivePremiumProvider);
  }

  static const _levelThresholds = [100, 300, 600, 1500];
  static const _prefKeyLastLevel = 'last_vocab_level';

  String _vocabLevel(int vocab) => vocabLevel(vocab);

  Future<void> _checkLevelUp(int vocab) async {
    final crossedThreshold = _levelThresholds.any((t) => vocab >= t);
    if (!crossedThreshold) return;

    final level = _vocabLevel(vocab);
    final prefs = await SharedPreferences.getInstance();
    final lastLevel = prefs.getString(_prefKeyLastLevel) ?? '入門';

    if (level == lastLevel) return;

    // レベルが上がった場合のみ（下がった場合は無視）
    final lastIndex =
        _levelThresholds.indexWhere((t) => t > (_thresholdForLevel(lastLevel)));
    final newIndex =
        _levelThresholds.indexWhere((t) => t > (_thresholdForLevel(level)));
    final effectiveLastIndex =
        lastIndex == -1 ? _levelThresholds.length : lastIndex;
    final effectiveNewIndex =
        newIndex == -1 ? _levelThresholds.length : newIndex;
    if (effectiveNewIndex <= effectiveLastIndex) return;

    await prefs.setString(_prefKeyLastLevel, level);
  }

  int _thresholdForLevel(String level) {
    switch (level) {
      case '入門':
        return 0;
      case '初級':
        return 100;
      case '初中級':
        return 300;
      case '中級':
        return 600;
      case '上級':
        return 1500;
      default:
        return 0;
    }
  }

  /// Build error state
  Widget _buildErrorState(BuildContext context, String message) {
    final isQuotaError = isQuotaErrorMessage(message);

    // 上限に当たった free だけがアップグレードで解ける状態にある。
    // 判定が付くまで（loading）は出さない。
    final plan = ref.watch(planStatusProvider).valueOrNull;
    final showUpgrade = isQuotaError && plan == PlanStatus.free;

    if (showUpgrade && !_quotaPaywallImpressionLogged) {
      _quotaPaywallImpressionLogged = true;
      unawaited(
        ref.read(analyticsServiceProvider).logPaywallBanner(
              action: 'shown',
              source: _quotaPaywallSource,
            ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isQuotaError ? Icons.lock_outline : Icons.error_outline,
              size: 64,
              color: isQuotaError
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            if (isQuotaError) ...[
              const SizedBox(height: 12),
              Text(
                nextResetText(L10n.of(context)),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.64),
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            // 上限に当たった瞬間は「なぜ premium が要るのか」が最も伝わる場面
            // なので、ここでだけ割り込みなしに訴求する。free 5 に対して
            // premium 20（2026-08-25 に 10→20）と差が付いたため噛み合う。
            // premium で使い切った人には勧める先が無いので出さない。
            if (showUpgrade) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => PaywallBottomSheet.show(
                  context,
                  source: _quotaPaywallSource,
                ),
                icon: const Icon(Icons.lock_open),
                label: Text(
                  L10n.of(context).quotaSentenceUpgradeCta,
                ),
              ),
            ],
            if (!isQuotaError) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  final genParams = ref.read(generationParamsProvider);
                  ref
                      .read(sentenceControllerProvider.notifier)
                      .generateSentence(
                        generationParams: genParams,
                        count: learningSetSize,
                      );
                },
                icon: const Icon(Icons.refresh),
                label: Text(L10n.of(context).commonRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Build empty state with default greeting sentence
  Widget _buildEmptyState(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConfig.defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // サンプル例文のラベル
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(AppConfig.defaultPadding),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      L10n.of(context).sampleSentenceNotice,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // サンプルは「まだ自分の例文が1本も無い」状態の見本でしかない。
          // 取り込みや生成が失敗してここへ来た人が、自分でやり直せるようにする。
          if (widget.onReload != null) ...[
            FilledButton.icon(
              onPressed: _reloading ? null : _reloadToday,
              icon: _reloading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(L10n.of(context).sampleReload),
            ),
            const SizedBox(height: 16),
          ],
          _buildSentenceCard(
            context,
            TodayScreen.defaultGreetingSentence(L10n.of(context)),
          ),
        ],
      ),
    );
  }

  Future<void> _reloadToday() async {
    final reload = widget.onReload;
    if (reload == null) return;
    setState(() => _reloading = true);
    try {
      await reload();
    } finally {
      if (mounted) setState(() => _reloading = false);
    }
  }
}
