import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/backend_api_service.dart';
import '../../data/models/vocab_test_step.dart';
import '../../l10n/app_localizations.dart';
import '../providers/analytics_provider.dart';
import '../providers/settings_provider.dart';

/// 語彙テスト。4択でいまの語彙量を測り、estimated_vocab の出発点を決める。
///
/// 出題は1段（4問）ずつサーバーが返す。全員1段目から始め、段を通過すれば
/// 次の段へ上がり、落ちたらそこで終わる。初心者は1段目で落ちて4問で終わる
/// （オンボーディングの末尾に置くので、長いと最初の例文に辿り着く前に離脱する）。
///
/// ヒアリングの申告レベルは渡さない。語彙スコアは測定だけで決める。
///
/// 正解はサーバーにしか無い。選んだ index を送り返して採点してもらう。
class VocabTestScreen extends ConsumerStatefulWidget {
  static const routeName = 'vocab_test';

  const VocabTestScreen({
    super.key,
    this.mandatory = false,
    required this.source,
    this.onFinished,
    this.api,
  });

  /// 逃げ道を塞ぐか。オンボーディングでは必ず測ってから先へ進ませる
  /// （戻る矢印・端末の戻る操作・「あとで」を全て出さない）。
  final bool mandatory;

  /// 分析用の入口（onboarding / settings）。
  final String source;

  /// 閉じるときに一度だけ呼ぶ。測った語彙数（受けずに閉じたら null）。
  final void Function(int? vocab)? onFinished;

  /// 差し替え用（テスト）。既定はこの画面が自分で作る。
  final BackendApiService? api;

  @override
  ConsumerState<VocabTestScreen> createState() => _VocabTestScreenState();
}

enum _Phase { intro, loading, question, result, error }

class _VocabTestScreenState extends ConsumerState<VocabTestScreen> {
  late final BackendApiService _api = widget.api ??
      BackendApiService(lang: () => ref.read(appLanguageProvider).code);

  _Phase _phase = _Phase.intro;
  VocabTestStep? _step;

  /// いま出している設問の位置（段の中）。
  int _index = 0;

  /// 段の回答。選んだ選択肢の index。「わからない」は -1。
  final List<int> _answers = [];

  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    unawaited(_log('start'));
  }

  Future<void> _log(String action, {int? value}) => ref
      .read(analyticsServiceProvider)
      .logVocabTest(action: action, source: widget.source, value: value);

  Future<void> _start() => _call(() => _api.startVocabTest());

  Future<void> _submit() {
    final answers = List<int>.from(_answers);
    final stage = _step?.stage;
    return _call(() => _api.submitVocabTest(answers, stage: stage));
  }

  /// 直前に失敗した通信。エラー画面の再試行で同じものを送り直す。
  ///
  /// 以前は再試行が常に _start だったので、段の送信が通信断で落ちただけでも
  /// テストが最初からやり直しになり、月1回の受験権まで1つ消えていた。
  Future<VocabTestStep> Function()? _retry;

  /// 通信と状態遷移。段が返れば設問へ、done なら結果へ。
  Future<void> _call(Future<VocabTestStep> Function() request) async {
    setState(() => _phase = _Phase.loading);
    try {
      final step = await request();
      if (!mounted) return;
      setState(() {
        _step = step;
        _index = 0;
        _answers.clear();
        _phase = step.done ? _Phase.result : _Phase.question;
      });
      if (step.done) {
        unawaited(_log('complete', value: step.vocab));
      } else {
        unawaited(_log('stage', value: step.stage));
      }
    } on VocabTestUnavailableException catch (e) {
      // プレミアム限定・月1回・セッション切れ。送り直しても同じ結果にしか
      // ならないので再試行は出さない。
      _fail(e.message, retry: null);
    } on BackendApiException catch (e) {
      _fail(e.message, retry: request);
    } catch (e) {
      _fail('$e', retry: request);
    }
  }

  void _fail(String message, {required Future<VocabTestStep> Function()? retry}) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _retry = retry;
      _phase = _Phase.error;
    });
    unawaited(_log('error'));
  }

  /// 回答を1つ記録する。段の最後なら送信する。
  void _answer(int choice) {
    // 2本指で選択肢を同時に叩くと、同じフレームで2回呼ばれて段の問数を超える。
    // 超えた分だけ _submit が重なり、2本目は「次の段の設問を前の段の回答で
    // 採点する」ことになる。設問が出ている間だけ受け付ける。
    if (_phase != _Phase.question) return;
    _answers.add(choice);
    final total = _step?.questions.length ?? 0;
    if (_answers.length >= total) {
      unawaited(_submit());
      return;
    }
    setState(() => _index = _answers.length);
  }

  /// 画面を出るときのイベントを一度だけ送る。
  ///
  /// 出口は「ボタンで閉じる」と「戻る（PopScope）」の2つあり、前者は後者を
  /// 誘発する（onFinished の実体が Navigator.pop）。両方で送ると完了1回が
  /// skip としても数えられ、離脱率が読めなくなる。
  ///
  /// complete / error は到達した時点で送っているので、ここでは足さない。
  bool _leaveLogged = false;

  void _logLeave() {
    if (_leaveLogged) return;
    _leaveLogged = true;
    final event = switch (_phase) {
      _Phase.intro => 'skip', // 測らずに離脱
      _Phase.question || _Phase.loading => 'abandon', // 測っている途中で離脱
      _Phase.result || _Phase.error => null, // 到達時に記録済み
    };
    if (event != null) unawaited(_log(event));
  }

  void _close({int? vocab}) {
    _logLeave();
    widget.onFinished?.call(vocab);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return PopScope(
      // オンボーディングだけ塞ぐ。測る前に抜けられると estimated_vocab が
      // 0 から始まり、初回の例文が入門者向けに固定される。設定からの
      // 再試験では塞がない（途中で抜けてもセッションは次の開始で上書き）。
      canPop: !widget.mandatory,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _logLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.vocabTestTitle),
          automaticallyImplyLeading: !widget.mandatory,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            // どの画面も Spacer で上下に寄せる作りなので、そのままだと
            // 小さい端末や文字サイズを上げた設定で RenderFlex overflow になる。
            // 縦に収まるうちは今までどおり寄せ、溢れたらスクロールへ逃がす。
            child: _fitOrScroll(switch (_phase) {
              _Phase.intro => _buildIntro(l10n),
              _Phase.loading =>
                const Center(child: CircularProgressIndicator()),
              _Phase.question => _buildQuestion(l10n),
              _Phase.result => _buildResult(l10n),
              _Phase.error => _buildError(l10n),
            }),
          ),
        ),
      ),
    );
  }

  /// 画面いっぱいに収まるならそのまま、溢れるならスクロールさせる。
  ///
  /// ConstrainedBox の minHeight で「最低でも画面の高さ」を与えるので、
  /// 中の Spacer は今までどおり効く。中身がそれを超えたぶんだけ伸びる。
  Widget _fitOrScroll(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(child: child),
        ),
      ),
    );
  }

  Widget _buildIntro(L10n l10n) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Icon(Icons.straighten,
            size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: 24),
        Text(l10n.vocabTestIntroBody, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 16),
        Text(
          l10n.vocabTestIntroNote,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const Spacer(),
        FilledButton(
          onPressed: _start,
          child: Text(l10n.vocabTestStart),
        ),
      ],
    );
  }

  Widget _buildQuestion(L10n l10n) {
    final step = _step;
    if (step == null || _index >= step.questions.length) {
      return const Center(child: CircularProgressIndicator());
    }
    final question = step.questions[_index];
    final total = step.questions.length;

    return _questionBody(l10n, question, total);
  }

  Widget _questionBody(L10n l10n, VocabTestQuestion question, int total) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(
          value: total == 0 ? 0 : (_index + 1) / total,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.vocabTestProgress(_index + 1, total),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 32),
        Text(
          l10n.vocabTestQuestion,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Text(
          question.word,
          style: theme.textTheme.displaySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        for (var i = 0; i < question.choices.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              onPressed: () => _answer(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(question.choices[i]),
              ),
            ),
          ),
        const Spacer(),
        // 当てずっぽうを誘わない。推測は測定値を押し上げるだけで本人が損をする。
        TextButton(
          onPressed: () => _answer(-1),
          child: Text(l10n.vocabTestDontKnow),
        ),
      ],
    );
  }

  Widget _buildResult(L10n l10n) {
    final theme = Theme.of(context);
    final step = _step;
    final vocab = step?.vocab ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Text(
          l10n.vocabTestResultTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.vocabTestResultVocab(vocab),
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall
              ?.copyWith(color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 24),
        Text(l10n.vocabTestResultBody, style: theme.textTheme.bodyMedium),
        if (step?.freeCapped ?? false) ...[
          const SizedBox(height: 16),
          Text(
            l10n.vocabTestResultFreeCap,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        const Spacer(),
        FilledButton(
          onPressed: () => _close(vocab: vocab),
          child: Text(l10n.vocabTestResultClose),
        ),
      ],
    );
  }

  Widget _buildError(L10n l10n) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text(
          _errorMessage.isEmpty ? l10n.vocabTestError : _errorMessage,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const Spacer(),
        if (_retry case final retry?)
          FilledButton(
            onPressed: () => _call(retry),
            child: Text(l10n.vocabTestRetry),
          ),
        TextButton(
          onPressed: _close,
          child: Text(l10n.vocabTestResultClose),
        ),
      ],
    );
  }
}
