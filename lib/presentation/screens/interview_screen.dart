import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../services/interview_reporter.dart';
import '../providers/analytics_provider.dart';

/// オンボーディングとコーチマークの間に挟む、タイ語との距離のヒアリング。
///
/// 設問を4問続けて聞き、最後に1画面だけ返す。1問ごとに応答を挟むと画面数が
/// 倍になり、読ませたい肝心の1画面に届く前に離脱する。返す内容も、答えに
/// 寄せた「考え方」だけに絞る。
///
/// 最初に「4つ質問させてください」の1枚を挟む。前置きなしに設問へ入ると、
/// 何のために聞かれているのか分からないまま答えさせることになる。
///
/// スキップは置かない。4問とも答えてから最後の1画面へ進む。
///
/// 回答は例文生成には効かせない（語彙推定はクイズの結果でしか動かさない）。
/// 目的は、考え方を本人の状況に寄せて伝えることと、「自分に合わせて
/// 作られる」という前提をここで納得してもらうこと。
/// 回答は端末に残し、分析にも送る。
class InterviewScreen extends ConsumerStatefulWidget {
  static const routeName = 'interview';

  const InterviewScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  ConsumerState<InterviewScreen> createState() => _InterviewScreenState();
}

/// ヒアリングの設問。回答値は分析でそのまま使うので英字で持つ。
class _Question {
  const _Question({
    required this.key,
    required this.textOf,
    required this.options,
  });

  final String key;
  final String Function(L10n) textOf;
  final List<_Option> options;
}

class _Option {
  const _Option(
      {required this.value, required this.labelOf, required this.icon});

  final String value;
  final String Function(L10n) labelOf;
  final IconData icon;
}

const _questions = <_Question>[
  _Question(
    key: 'level',
    textOf: _qLevel,
    options: [
      _Option(value: 'none', labelOf: _oLevelNone, icon: Icons.egg_outlined),
      _Option(value: 'chars', labelOf: _oLevelChars, icon: Icons.abc),
      _Option(value: 'words', labelOf: _oLevelWords, icon: Icons.translate),
      _Option(value: 'conv', labelOf: _oLevelConv, icon: Icons.forum_outlined),
    ],
  ),
  _Question(
    key: 'goal',
    textOf: _qGoal,
    options: [
      _Option(
          value: 'travel', labelOf: _oGoalTravel, icon: Icons.flight_takeoff),
      _Option(value: 'work', labelOf: _oGoalWork, icon: Icons.work_outline),
      _Option(value: 'live', labelOf: _oGoalLive, icon: Icons.home_outlined),
      _Option(
          value: 'culture', labelOf: _oGoalCulture, icon: Icons.movie_outlined),
    ],
  ),
  _Question(
    key: 'time',
    textOf: _qTime,
    options: [
      _Option(value: 'short', labelOf: _oTimeShort, icon: Icons.bolt_outlined),
      _Option(value: 'medium', labelOf: _oTimeMedium, icon: Icons.schedule),
      _Option(value: 'long', labelOf: _oTimeLong, icon: Icons.self_improvement),
    ],
  ),
  _Question(
    key: 'struggle',
    textOf: _qStruggle,
    options: [
      _Option(
          value: 'none',
          labelOf: _oStruggleNone,
          icon: Icons.sentiment_satisfied_alt),
      _Option(
          value: 'script', labelOf: _oStruggleScript, icon: Icons.text_fields),
      _Option(value: 'tone', labelOf: _oStruggleTone, icon: Icons.graphic_eq),
      _Option(
          value: 'vocab',
          labelOf: _oStruggleVocab,
          icon: Icons.psychology_outlined),
    ],
  ),
];

String _qLevel(L10n l) => l.interviewLevelQuestion;
String _oLevelNone(L10n l) => l.interviewLevelNone;
String _oLevelChars(L10n l) => l.interviewLevelChars;
String _oLevelWords(L10n l) => l.interviewLevelWords;
String _oLevelConv(L10n l) => l.interviewLevelConv;
String _qGoal(L10n l) => l.interviewGoalQuestion;
String _oGoalTravel(L10n l) => l.interviewGoalTravel;
String _oGoalWork(L10n l) => l.interviewGoalWork;
String _oGoalLive(L10n l) => l.interviewGoalLive;
String _oGoalCulture(L10n l) => l.interviewGoalCulture;
String _qTime(L10n l) => l.interviewTimeQuestion;
String _oTimeShort(L10n l) => l.interviewTimeShort;
String _oTimeMedium(L10n l) => l.interviewTimeMedium;
String _oTimeLong(L10n l) => l.interviewTimeLong;
String _qStruggle(L10n l) => l.interviewStruggleQuestion;
String _oStruggleNone(L10n l) => l.interviewStruggleNone;
String _oStruggleScript(L10n l) => l.interviewStruggleScript;
String _oStruggleTone(L10n l) => l.interviewStruggleTone;
String _oStruggleVocab(L10n l) => l.interviewStruggleVocab;

class _InterviewScreenState extends ConsumerState<InterviewScreen> {
  /// 設問キー → 選んだ値。スキップした設問は入らない。
  final Map<String, String> _answers = {};

  /// いま扱っている設問の位置。
  int _index = 0;

  /// 前置きを読み終えて設問に入ったか。
  bool _started = false;

  /// 設問が終わり、最後の1画面（考え方）を出しているか。
  bool _finished = false;

  bool _completing = false;

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(analyticsServiceProvider).logInterview(action: 'start'));
  }

  void _select(String questionKey, String value) {
    setState(() {
      _answers[questionKey] = value;
      // 応答は挟まず、そのまま次の設問へ送る。
      if (_index >= _questions.length - 1) {
        _finished = true;
      } else {
        _index++;
      }
    });
    unawaited(
      ref.read(analyticsServiceProvider).logInterview(
            action: 'answer',
            question: questionKey,
            answer: value,
          ),
    );
  }

  Future<void> _complete() async {
    if (_completing) return;
    _completing = true;
    final prefs = await SharedPreferences.getInstance();
    for (final entry in _answers.entries) {
      await prefs.setString(
        '${AppConfig.prefKeyInterviewPrefix}${entry.key}',
        entry.value,
      );
    }
    // 全問スキップでも立てる。答えなかったことも分析の対象。
    await prefs.setBool(AppConfig.prefKeyInterviewCompleted, true);
    unawaited(
      ref.read(analyticsServiceProvider).logInterview(
            action: 'complete',
            answeredCount: _answers.length,
          ),
    );
    // users doc へ送る。失敗しても次の起動で送り直されるので待たない。
    unawaited(InterviewReporter().report());
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final question = _questions[_index];

    // 戻るは置かない。設問へ引き返す意味がなく、初回導線から抜けさせない。
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: !_started || _finished
              ? null
              : Text(
                  l10n.interviewStepLabel(_index + 1, _questions.length),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
          centerTitle: false,
        ),
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: switch ((_started, _finished)) {
              (false, _) => _IntroView(
                  key: const ValueKey('intro'),
                  onStart: () => setState(() => _started = true),
                ),
              (_, true) => _PhilosophyView(
                  key: const ValueKey('philosophy'),
                  answers: _answers,
                  onStart: _complete,
                ),
              _ => _QuestionView(
                  key: ValueKey(question.key),
                  question: question,
                  selected: _answers[question.key],
                  onSelect: (value) => _select(question.key, value),
                ),
            },
          ),
        ),
      ),
    );
  }
}

/// 設問に入る前の前置き。何問あるか、何のために聞くかだけを伝える。
class _IntroView extends StatelessWidget {
  const _IntroView({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.chat_bubble_outline,
                      size: 28,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.interviewIntroTitle,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.interviewIntroBody,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onStart,
            child: Text(l10n.interviewIntroStart),
          ),
        ],
      ),
    );
  }
}

class _QuestionView extends StatelessWidget {
  const _QuestionView({
    super.key,
    required this.question,
    required this.selected,
    required this.onSelect,
  });

  final _Question question;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Text(
            question.textOf(l10n),
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: ListView.separated(
              itemCount: question.options.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final option = question.options[index];
                final isSelected = option.value == selected;
                return Material(
                  color: isSelected
                      ? cs.primaryContainer
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => onSelect(option.value),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      child: Row(
                        children: [
                          Icon(option.icon, color: cs.primary),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              option.labelOf(l10n),
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// ヒアリングの最後に1度だけ出す画面。回答に寄せて、アプリの考え方を伝える。
///
/// 出すのは箇条書き5点だけ。5点とも本文で、見出しは付けない。
/// 「今日の1文から」のような要約はそれ自体が何も言っておらず、読む対象が
/// 増えるだけだった。
///
/// 5点のうち4点（今の学習段階・使う場面・つまずき・1日に取れる時間）は回答で
/// 切り替わる。残る1点は例文の作り（key_word）で、これは誰にも共通なので固定。
/// 使う場面と時間の2点は「その人が何をできるか」を具体で書く。励ましだけの
/// 一般論にすると、答えさせた意味がなくなる。
///
/// 上から順に1項目ずつフェードインさせる。5点を一度に出すと文字の壁になり、
/// どこから読むのか分からない。順に現れれば、上から1つずつ読む形になる。
class _PhilosophyView extends StatefulWidget {
  const _PhilosophyView({
    super.key,
    required this.answers,
    required this.onStart,
  });

  final Map<String, String> answers;
  final VoidCallback onStart;

  @override
  State<_PhilosophyView> createState() => _PhilosophyViewState();
}

class _PhilosophyViewState extends State<_PhilosophyView>
    with SingleTickerProviderStateMixin {
  /// 1項目ぶんの出現にかける時間と、次の項目までの間。
  static const _fade = Duration(milliseconds: 380);
  static const _stagger = Duration(milliseconds: 220);

  /// 見出し + 箇条書き5点 + ボタン。
  static const _itemCount = 7;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _stagger * (_itemCount - 1) + _fade,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// [index] 番目の項目を、順番が来たらフェードインさせる。
  Widget _staggered(int index, Widget child) {
    final total = _controller.duration!.inMilliseconds;
    final begin = (_stagger.inMilliseconds * index) / total;
    final end = ((_stagger.inMilliseconds * index + _fade.inMilliseconds) /
            total)
        .clamp(0.0, 1.0);
    final animation = CurvedAnimation(
      parent: _controller,
      curve: Interval(begin, end, curve: Curves.easeOut),
    );
    return FadeTransition(
      key: ValueKey('philosophy_stagger_$index'),
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  String _levelLine(L10n l) => switch (widget.answers['level']) {
        'chars' => l.philosophy1Chars,
        'words' => l.philosophy1Words,
        'conv' => l.philosophy1Conv,
        _ => l.philosophy1None,
      };

  String _struggleLine(L10n l) => switch (widget.answers['struggle']) {
        'script' => l.philosophy2Script,
        'tone' => l.philosophy2Tone,
        'vocab' => l.philosophy2Vocab,
        _ => l.philosophy2None,
      };

  String _goalLine(L10n l) => switch (widget.answers['goal']) {
        'work' => l.philosophy3Work,
        'live' => l.philosophy3Live,
        'culture' => l.philosophy3Culture,
        _ => l.philosophy3Travel,
      };

  String _timeLine(L10n l) => switch (widget.answers['time']) {
        'medium' => l.philosophy3TimeMedium,
        'long' => l.philosophy3TimeLong,
        _ => l.philosophy3TimeShort,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final bullets = <({IconData icon, String body})>[
      (icon: Icons.looks_one_outlined, body: _levelLine(l10n)),
      (icon: Icons.key_outlined, body: l10n.philosophyKeyWord),
      (icon: Icons.palette_outlined, body: _goalLine(l10n)),
      (icon: Icons.auto_fix_high_outlined, body: _struggleLine(l10n)),
      (icon: Icons.schedule, body: _timeLine(l10n)),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              children: [
                _staggered(
                  0,
                  Text(
                    l10n.philosophyHeading,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                for (final (index, bullet) in bullets.indexed) ...[
                  const SizedBox(height: 24),
                  _staggered(
                    index + 1,
                    _PhilosophyItem(icon: bullet.icon, body: bullet.body),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _staggered(
            _itemCount - 1,
            FilledButton(
              onPressed: widget.onStart,
              child: Text(l10n.philosophyStart),
            ),
          ),
        ],
      ),
    );
  }
}

/// 文中の `**…**` で囲んだ部分を強調して描く。
///
/// 強調する語は言語ごとに変わる（語順も切れ目も違う）ので、位置は文言側
/// （arb）で持たせる。画面側で部分文字列を探すと、訳文を直すたびに強調が
/// 外れて気づけない。
class _HighlightedText extends StatelessWidget {
  const _HighlightedText(this.text, {required this.style});

  final String text;
  final TextStyle? style;

  static final _marker = RegExp(r'\*\*(.+?)\*\*');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    var index = 0;
    for (final match in _marker.allMatches(text)) {
      if (match.start > index) {
        spans.add(TextSpan(text: text.substring(index, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: TextStyle(
            color: cs.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      index = match.end;
    }
    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index)));
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }
}

class _PhilosophyItem extends StatelessWidget {
  const _PhilosophyItem({
    required this.icon,
    required this.body,
  });

  final IconData icon;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 22, color: cs.onPrimaryContainer),
        ),
        const SizedBox(width: 16),
        Expanded(
          // 見出しが無いぶん、本文を読める大きさで出す。
          child: _HighlightedText(
            body,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: cs.onSurface,
              height: 1.6,
            ),
          ),
        ),
      ],
    );
  }
}
