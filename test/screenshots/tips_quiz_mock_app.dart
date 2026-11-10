// =============================================================================
// tips_quiz_mock_app.dart
// まとめクイズが5問に満たないとき、足りない分をガイド（発音・語順）の
// コツ問題で埋める案のモック。まとめクイズの AppBar・上端の金の帯・4択・
// 正誤の枠・下端の固定バーは QuizScreen（_QuizQuestionView）と同じ組み方で
// 描き、コツ問題だけ中身を差し替える。選ぶと正誤と解説、ガイドへの導線が出る。
// Firebase なし。下の切り替えで 4問目（発音）/ 5問目（語順）。
//
//
//   flutter run -t test/screenshots/tips_quiz_mock_app.dart
// =============================================================================

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thai_memo/core/config/app_config.dart';
import 'package:thai_memo/core/theme/app_colors.dart';
import 'package:thai_memo/core/theme/app_theme.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/analytics_provider.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';
import 'package:thai_memo/presentation/providers/tts_provider.dart';
import 'package:thai_memo/presentation/screens/pronunciation_guide_screen.dart';
import 'package:thai_memo/presentation/screens/word_order_guide_screen.dart';
import 'package:thai_memo/services/analytics_service.dart';
import 'package:thai_memo/services/tts_service.dart';

void main() => runApp(const _MockApp());

/// コツ問題1問。出題カードに出すタイ語の組（読み付き）と、日本語の問い。
class _TipQuestion {
  final String prompt;
  final List<(String thai, String reading)> words;
  final bool contrast;
  final String question;
  final List<String> choices;
  final List<String> choiceReadings;
  final int correct;
  final String explanation;
  final String guideLabel;
  final Widget Function() guide;
  final String guideRoute;

  const _TipQuestion({
    required this.prompt,
    required this.words,
    this.contrast = false,
    required this.question,
    required this.choices,
    this.choiceReadings = const [],
    required this.correct,
    required this.explanation,
    required this.guideLabel,
    required this.guide,
    required this.guideRoute,
  });

  bool get thaiChoices => choiceReadings.isNotEmpty;
}

final _questions = [
  _TipQuestion(
    prompt: '発音のコツ',
    words: const [('ไก่', 'kài'), ('ไข่', 'khài')],
    contrast: true,
    question: '「鶏」と「卵」。2つの語の違いは？',
    choices: const ['息を強く出すかどうか', '声調の高さ', '母音の長さ', '最後の子音'],
    correct: 0,
    explanation:
        'kh・th・ph・ch は息を強く出し、k・t・p・j は息を出さずに言います。日本語では区別しませんが、タイ語では別の語になります。',
    guideLabel: '発音について詳しく学ぶ',
    guide: () => const PronunciationGuideScreen(),
    guideRoute: PronunciationGuideScreen.routeName,
  ),
  _TipQuestion(
    prompt: '語順のコツ',
    words: const [('บ้าน', 'bâan'), ('ใหญ่', 'yài')],
    question: '「大きい家」はどちら？',
    choices: const ['บ้านใหญ่', 'ใหญ่บ้าน'],
    choiceReadings: const ['bâan yài', 'yài bâan'],
    correct: 0,
    explanation: '形容詞は名詞の後ろ。「〜の」も持ち主が後ろです。',
    guideLabel: '語順について詳しく学ぶ',
    guide: () => const WordOrderGuideScreen(),
    guideRoute: WordOrderGuideScreen.routeName,
  ),
];

class _MockApp extends StatelessWidget {
  const _MockApp();

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        analyticsServiceProvider.overrideWithValue(_NoopAnalytics()),
        ttsServiceProvider.overrideWithValue(_SilentTtsService()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('ja'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: buildAppLightTheme(ThaiFont.sarabun),
        home: const _Home(),
      ),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  /// 実際の例文から出たのが3問、残り2問をコツで埋めた想定。
  static const _total = 5;
  static const _firstTipIndex = 3;
  int _tip = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final index = _firstTipIndex + _tip;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.learnSummaryQuizTitle),
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppConfig.screenPadding),
            child: Center(
              child: Text(
                '${index + 1} / $_total',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: (index + 1) / _total,
            minHeight: 4,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            color: AppColors.gold,
          ),
          Expanded(
            child: _TipQuestionView(
              key: ValueKey(_tip),
              question: _questions[_tip],
              isLast: index + 1 >= _total,
              onNext: () => setState(() => _tip = (_tip + 1) % 2),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('4問目 発音')),
              ButtonSegment(value: 1, label: Text('5問目 語順')),
            ],
            selected: {_tip},
            onSelectionChanged: (s) => setState(() => _tip = s.first),
          ),
        ),
      ),
    );
  }
}

class _TipQuestionView extends StatefulWidget {
  const _TipQuestionView({
    super.key,
    required this.question,
    required this.isLast,
    required this.onNext,
  });

  final _TipQuestion question;
  final bool isLast;
  final VoidCallback onNext;

  @override
  State<_TipQuestionView> createState() => _TipQuestionViewState();
}

class _TipQuestionViewState extends State<_TipQuestionView> {
  int? _selected;

  bool get _hasResult => _selected != null;
  bool get _isCorrect => _selected == widget.question.correct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = widget.question;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                AppConfig.screenPadding, 16, AppConfig.screenPadding, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  q.prompt,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _buildCard(context),
                const SizedBox(height: 16),
                ...List.generate(
                  q.choices.length,
                  (i) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildChoiceTile(context, i),
                  ),
                ),
                if (_hasResult) ...[
                  const SizedBox(height: 4),
                  _buildFeedbackBox(context),
                  _buildGuideButton(context),
                ],
              ],
            ),
          ),
        ),
        if (_hasResult) _buildActionBar(context),
      ],
    );
  }

  /// 出題カード。タイ語の組は意味4択の出題語と同じ級数、読みはその下。
  Widget _buildCard(BuildContext context) {
    final theme = Theme.of(context);
    final q = widget.question;
    final base = (theme.textTheme.headlineMedium ?? const TextStyle()).copyWith(
      fontSize: 28,
      fontWeight: FontWeight.w500,
      height: 1.6,
    );
    // 語ごとにタイ文字と読みを縦に組む。対比の印は発音ガイドと同じ swap_horiz。
    final words = [
      for (final w in q.words)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(w.$1, style: base),
            Text(
              w.$2,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (final (i, w) in words.indexed) ...[
                  if (i > 0)
                    q.contrast
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Icon(Icons.swap_horiz,
                                size: 22, color: theme.colorScheme.outline),
                          )
                        : const SizedBox(width: 16),
                  w,
                ],
              ],
            ),
            const SizedBox(height: 14),
            Text(q.question, style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }

  /// QuizScreen._buildChoiceTile と同じ面・罫線・正誤の色。
  Widget _buildChoiceTile(BuildContext context, int index) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final q = widget.question;
    final isSelected = _selected == index;
    final isCorrectChoice = _hasResult && index == q.correct;
    final isWrongSelection = isSelected && !_isCorrect;

    Color? accent;
    IconData? resultIcon;
    if (isCorrectChoice) {
      accent = AppColors.jade;
      resultIcon = Icons.check_rounded;
    } else if (isWrongSelection) {
      accent = AppColors.vermilion;
      resultIcon = Icons.close_rounded;
    }
    final isDimmed = _hasResult && accent == null;
    final foreground = accent ??
        (isDimmed
            ? colorScheme.onSurfaceVariant.withValues(alpha: 0.6)
            : colorScheme.onSurface);
    final reading =
        index < q.choiceReadings.length ? q.choiceReadings[index] : '';

    return ElevatedButton(
      onPressed: _hasResult ? null : () => setState(() => _selected = index),
      style: ElevatedButton.styleFrom(
        elevation: 0,
        alignment: Alignment.centerLeft,
        backgroundColor: accent?.withValues(alpha: 0.08) ?? colorScheme.surface,
        disabledBackgroundColor:
            accent?.withValues(alpha: 0.08) ?? colorScheme.surface,
        foregroundColor: foreground,
        disabledForegroundColor: foreground,
        side: BorderSide(
          color: accent ?? colorScheme.outlineVariant,
          width: accent != null ? 1.5 : 1,
        ),
        minimumSize: const Size.fromHeight(58),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
        ),
      ),
      child: Row(
        children: [
          // 日本語の選択肢は長いので、読みが無いときは横幅いっぱいに使う。
          (reading.isEmpty ? Expanded.new : Flexible.new)(
            child: Text(
              q.choices[index],
              style: TextStyle(
                fontSize: q.thaiChoices ? 24 : 18,
                fontWeight: FontWeight.w500,
                color: foreground,
              ),
            ),
          ),
          if (reading.isNotEmpty) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                reading,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: colorScheme.onSurfaceVariant
                      .withValues(alpha: isDimmed ? 0.6 : 1),
                ),
              ),
            ),
          ],
          if (reading.isNotEmpty) const Spacer(),
          if (resultIcon != null) ...[
            const SizedBox(width: 8),
            Icon(resultIcon, color: accent),
          ],
        ],
      ),
    );
  }

  /// QuizScreen._buildFeedbackBox と同じ枠。本文はガイドの文言。
  Widget _buildFeedbackBox(BuildContext context) {
    final l10n = L10n.of(context);
    final accent = _isCorrect ? AppColors.jade : AppColors.vermilion;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConfig.defaultPadding),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isCorrect ? Icons.check_rounded : Icons.close_rounded,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 6),
              Text(
                _isCorrect ? l10n.quizCorrect : l10n.quizIncorrect,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.question.explanation,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  /// 語順・タイ文字ガイドへのボタン（_WordOrderGuideButton）と同じ形。
  Widget _buildGuideButton(BuildContext context) {
    final q = widget.question;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            CupertinoPageRoute(
              settings: RouteSettings(name: q.guideRoute),
              builder: (_) => q.guide(),
            ),
          ),
          icon: const Icon(Icons.school),
          label: Text(q.guideLabel),
        ),
      ),
    );
  }

  /// QuizScreen._QuizActionBar と同じ下端の固定バー。
  Widget _buildActionBar(BuildContext context) {
    final l10n = L10n.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(
          AppConfig.screenPadding, 12, AppConfig.screenPadding, 12),
      child: Row(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: widget.onNext,
              child: Text(
                  widget.isLast ? l10n.quizSeeResults : l10n.quizNextQuestion),
            ),
          ),
        ],
      ),
    );
  }
}

class _SilentTtsService extends Fake implements TtsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();

  @override
  void dispose() {}
}

class _NoopAnalytics extends Fake implements AnalyticsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class Fake {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
