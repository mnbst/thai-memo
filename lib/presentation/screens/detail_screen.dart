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
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/generation_labels.dart';
import '../../l10n/app_localizations.dart';
import '../../data/models/thai_sentence.dart';
import '../../data/models/word_breakdown.dart';
import '../providers/analytics_provider.dart';
import '../providers/pronunciation_provider.dart';
import '../providers/tts_provider.dart';
import '../widgets/topic_picker.dart';
import '../widgets/coach_mark_overlay.dart';
import '../tone_explanation_dialog.dart';
import '../widgets/sentence_audio_player.dart';
import '../widgets/pronunciation_practice.dart';

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
  /// 単語分解セクションの展開/折りたたみ状態
  bool _isWordBreakdownExpanded = true;

  /// 文脈情報セクションの展開/折りたたみ状態
  bool _isContextExpanded = true;

  /// 初回ガイドのスポット対象。例文カード → 発音練習 → 単語の分解 →
  /// 文脈・使い方 → 戻る の順に続けて案内する。
  final GlobalKey _sentenceKey = GlobalKey();
  final GlobalKey _playKey = GlobalKey();
  final GlobalKey _pronunciationKey = GlobalKey();
  final GlobalKey _wordItemKey = GlobalKey();

  /// 声調判定の結果を指すキー。ツアーの段ではない（判定した回にだけ出す）。
  final GlobalKey _resultKey = GlobalKey();

  /// 語を選んだときに開くカーブのカードを指すキー。
  final GlobalKey _contourKey = GlobalKey();
  final GlobalKey _contextKey = GlobalKey();
  final GlobalKey _backKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    unawaited(
      ref.read(analyticsServiceProvider).logViewDetail(
            sentenceId: widget.sentence.id,
            source: widget.source,
          ),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_maybeShowDetailCoach()),
    );
  }

  @override
  void dispose() {
    for (final key in _cleanupKeys) {
      CoachMarkOverlay.dismissFor(key);
    }
    _abortCoachWait?.call();
    super.dispose();
  }

  List<GlobalKey> get _coachKeys => [
        _sentenceKey,
        _playKey,
        _pronunciationKey,
        _wordItemKey,
        _contextKey,
        _backKey,
      ];

  /// 画面を離れるときに閉じる対象。ツアーの段に加えて、判定結果の案内も含む。
  List<GlobalKey> get _cleanupKeys => [..._coachKeys, _resultKey, _contourKey];

  /// 待機中の連鎖を打ち切る手。画面を離れて閉じられた場合は onDismiss が
  /// 呼ばれないため、これを呼ばないと案内の連鎖が待ちっぱなしになる。
  VoidCallback? _abortCoachWait;

  /// 詳細画面の初回ガイド。例文カード → お手本再生 → 発音練習 →
  /// 単語の分解と声調詳細 → 文脈・使い方 → 戻る を続けて案内する。
  ///
  /// 1つ閉じたら次へ進む。対象が画面外にあるので、毎回スクロールで見せてから
  /// スポットを当てる。途中で画面を離れた場合は進捗を残し、次に詳細を開いた
  /// ときに残りから再開する（まとめて出し直すと最初の案内を二度読ませる）。
  Future<void> _maybeShowDetailCoach() async {
    final prefs = await SharedPreferences.getInstance();
    await _runDetailCoach(prefs);
  }

  Future<void> _runDetailCoach(SharedPreferences prefs) async {
    var step = prefs.getInt(AppConfig.prefKeyDetailTourStep) ??
        _migratedTourStep(prefs);
    if (step >= _coachKeys.length) return;
    if (CoachMarkOverlay.isVisible) return;

    while (step < _coachKeys.length) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      final pending = _showCoachStep(step);
      // 対象が無い例文（音節データや文脈情報が欠けている）では出せない。
      // 出せた場合はここで進捗を確定し、閉じられるまで待つ。
      step++;
      await prefs.setInt(AppConfig.prefKeyDetailTourStep, step);
      if (pending == null) continue;
      await pending;
      // 押させた段は、その操作が終わるまで次の案内を出さない。録音中や
      // 単語の詳細の上に次の吹き出しを重ねると、どちらも読めなくなる。
      await _awaitStepAction(step - 1);
    }
  }

  /// 発声練習の案内が出た少し後に、マイクの許可を聞く。
  ///
  /// 押しっぱなしで録音する作りなので、押した瞬間に許可ダイアログが出ると
  /// 指が離れていて録音が始まらない。かといって案内より先に出すと、何の
  /// ダイアログか分からないまま断られる。読み始めた頃に重ねる。
  Future<void> _requestMicPermission() async {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    final sentenceId = widget.sentence.id;
    if (sentenceId == null) return;
    // 練習セクションが描かれていない例文（音節データ無し）では聞かない。
    // 使えない機能のために許可だけ求めるのは、断られて終わるだけ。
    final box =
        _pronunciationKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.height <= 0) return;
    await ref
        .read(pronunciationControllerProvider(
          (sentenceId: sentenceId, scope: 'detail'),
        ).notifier)
        .requestPermissionInAdvance();
  }

  /// 押させた段の操作が終わるまで待つ。押させていない段では何もしない。
  Future<void> _awaitStepAction(int step) async {
    // スキップされた段は、その操作を待たない。待つと何も起きないまま
    // [_recordGrace] だけ案内が止まる。
    if (_coachSkipped) return;
    if (step == 1) return _awaitPlaybackFinished();
    if (step == 2) {
      await _awaitPronunciationSettled();
      // 判定が出ていれば、その見かたを続けて案内する。
      await _maybeShowResultCoach();
      return;
    }
    if (step == 3) return _awaitWordDetailClosed();
  }

  /// 単語の詳細（声調解説）を閉じるまで待つ。
  ///
  /// 開いている間は詳細画面が最前面ではないので、待たずに進めると次の段が
  /// 出せないまま初回ガイドが終わる。押されないまま（押し損ね）でも止まら
  /// ないよう、開かない時間が [_recordGrace] を超えたら切り上げる。
  Future<void> _awaitWordDetailClosed() async {
    final deadline = DateTime.now().add(_recordGrace);
    while (mounted && !_wordDetailOpen) {
      if (DateTime.now().isAfter(deadline)) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    while (mounted && _wordDetailOpen) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  /// お手本の再生が終わるまで待つ。1周で自動的に止まる（[_awaitingPlayback]）。
  ///
  /// 押し損ねて再生が始まらないときは [_recordGrace] で切り上げる。
  /// 鳴っている間に次の案内を出すと、読みながら聞くことになる。
  Future<void> _awaitPlaybackFinished() async {
    final gate = _playbackGate;
    if (gate == null) return;
    final deadline = DateTime.now().add(_recordGrace);
    while (mounted && !gate.isCompleted) {
      if (!_playbackStarted && DateTime.now().isAfter(deadline)) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    _playbackGate = null;
    if (mounted) setState(() => _awaitingPlayback = false);
  }

  /// 録音と採点が終わるまで待つ。
  ///
  /// マイクの許可ダイアログを出している間も待つ。許可を選んでいる最中に
  /// 次の案内を出すと、選び終えたときには別の場所を指している。
  ///
  /// 押されないまま（不許可・押し損ね）でも止まらないよう、何も起きない
  /// 時間が [_recordGrace] を超えたら切り上げる。許可した直後は押し直しが
  /// 要るので、そこからまた [_recordGrace] だけ待つ。
  Future<void> _awaitPronunciationSettled() async {
    // 未保存の例文では練習させていない（押させる段も出ない）。
    final sentenceId = widget.sentence.id;
    if (sentenceId == null) return;
    final provider = pronunciationControllerProvider(
      (sentenceId: sentenceId, scope: 'detail'),
    );
    var deadline = DateTime.now().add(_recordGrace);
    while (mounted) {
      final phase = ref.read(provider).phase;
      final busy = phase == PronunciationPhase.recording ||
          phase == PronunciationPhase.analyzing ||
          ref.read(provider.notifier).isRequestingPermission;
      if (busy) {
        deadline = DateTime.now().add(_recordGrace);
      } else if (phase == PronunciationPhase.result ||
          phase == PronunciationPhase.permissionDenied ||
          DateTime.now().isAfter(deadline)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  /// 声調判定の結果の見かたを案内する。
  ///
  /// 語ごとの帯 → （1語を押させる）→ カーブのカード、の2段。帯だけ見せても
  /// 「合っている／違う」しか分からない。どこがどうずれたのかは、押して開く
  /// カーブまで見せて初めて伝わる。
  ///
  /// 呼ぶのは初回ガイドの発声練習の段だけなので、出す回数の管理はしない。
  /// 判定が出ていない回（録音しなかった・不許可）は対象が無いので何もしない。
  Future<void> _maybeShowResultCoach() async {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (CoachMarkOverlay.isVisible) return;
    // 判定が出た直後はまだ結果が描かれていない（次のフレームで組まれる）。
    // 対象が無いからと諦めると、案内を飛ばして次の段へ進んでしまう。
    for (var i = 0; i < 15 && _resultKey.currentContext == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
    }
    if (_resultKey.currentContext == null) return;

    final tapped = await _showResultCoachStep(
      targetKey: _resultKey,
      id: 'pronunciation_result',
      icon: Icons.equalizer,
      titleOf: (l10n) => l10n.coachPronunciationResultTitle,
      messageOf: (l10n) => l10n.coachPronunciationResultMessage,
      // 語を押させる。押して初めてカーブが開くので、ここは読ませて終わらせない。
      forceTap: true,
    );
    if (tapped != 'tapped' || !mounted) return;

    // 押した語のカーブが描かれるまで待つ。
    for (var i = 0; i < 15 && _contourKey.currentContext == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
    }
    if (_contourKey.currentContext == null) return;

    await _showResultCoachStep(
      targetKey: _contourKey,
      id: 'pronunciation_contour',
      icon: Icons.show_chart,
      titleOf: (l10n) => l10n.coachPronunciationContourTitle,
      messageOf: (l10n) => l10n.coachPronunciationContourMessage,
      forceTap: false,
    );
  }

  /// 判定結果の案内を1段出して、閉じ方を返す。出せなければ null。
  Future<String?> _showResultCoachStep({
    required GlobalKey targetKey,
    required String id,
    required IconData icon,
    required String Function(L10n) titleOf,
    required String Function(L10n) messageOf,
    required bool forceTap,
  }) async {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return null;
    final targetContext = targetKey.currentContext;
    if (targetContext == null || !targetContext.mounted) return null;
    await Scrollable.ensureVisible(
      targetContext,
      alignment: 0.4,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return null;

    final l10n = L10n.of(context);
    final completer = Completer<String>();
    _abortCoachWait = () {
      if (!completer.isCompleted) completer.complete('closed');
    };
    final shown = CoachMarkOverlay.show(
      context,
      targetKey: targetKey,
      id: id,
      analytics: ref.read(analyticsServiceProvider),
      icon: icon,
      title: titleOf(l10n),
      message: messageOf(l10n),
      targetTappable: forceTap,
      barrierDismissible: !forceTap,
      confirmLabel: forceTap ? null : l10n.coachGotIt,
      onDismiss: (action) {
        if (!completer.isCompleted) completer.complete(action);
      },
    );
    if (!shown) return null;
    return completer.future;
  }

  /// 発声練習の案内を出してから、マイクの許可を聞くまでの間。
  /// 一読できるだけ置く。すぐ重ねると、何のための許可か分からないまま
  /// 断られる（iOS では一度断られると二度と聞けない）。
  static const _permissionCue = Duration(milliseconds: 1500);

  /// 押させた操作（再生・録音）が始まるのを待つ猶予。
  /// マイクの許可ダイアログを閉じたあとの押し直しにも使う。
  static const _recordGrace = Duration(seconds: 5);

  /// お手本を聞かせた段で、鳴り終わったことを知るための門。
  Completer<void>? _playbackGate;

  /// その段で再生が始まったか。始まらないまま待ち続けないための目印。
  bool _playbackStarted = false;

  /// 初回ガイドで再生を待っている間だけ真。1周で自動停止させる。
  bool _awaitingPlayback = false;

  /// 段を増やす前の進捗を、新しい段番号に読み替える。
  ///
  /// 途中に段を挟むと旧番号は手前を指す（同じ案内を二度読ませる）。
  /// v2 → v3 では単語の詳細を3段目に挟んだので、そこから後ろを1つずらす。
  static int _migratedTourStep(SharedPreferences prefs) {
    final v4 = prefs.getInt(AppConfig.prefKeyDetailTourStepV4);
    if (v4 != null) return _mergedWordSteps(v4);
    final v3 = prefs.getInt(AppConfig.prefKeyDetailTourStepV3);
    if (v3 != null) return _mergedWordSteps(_shiftedForPlayStep(v3));
    final v2 = prefs.getInt(AppConfig.prefKeyDetailTourStepV2);
    if (v2 != null) {
      return _mergedWordSteps(_shiftedForPlayStep(v2 <= 2 ? v2 : v2 + 1));
    }
    return _mergedWordSteps(_shiftedForPlayStep(_migratedTourStepV1(prefs)));
  }

  /// v4 → v5 の読み替え。単語の分解を単独の段から外し、声調詳細と1段に
  /// まとめたので、そこから後ろを1つ詰める。
  static int _mergedWordSteps(int step) => step <= 3 ? step : step - 1;

  /// v3 → v4 の読み替え。お手本再生を2段目に挟んだので、そこから後ろを
  /// 1つずらす（例文カードだけは番号が変わらない）。
  static int _shiftedForPlayStep(int step) => step == 0 ? 0 : step + 1;

  /// 先頭に例文カードの案内を足す前（v1）の進捗の読み替え。
  /// まだ何も見ていない人だけ 0 から。
  static int _migratedTourStepV1(SharedPreferences prefs) {
    final old = prefs.getInt(AppConfig.prefKeyDetailTourStepV1);
    // v1 → v2 で1つ、v2 → v3 でもう1つずれる（v1 の段はすべて 2 段目以降）。
    if (old != null) return old == 0 ? 0 : old + 2;
    // さらに旧版で発音の案内だけ見た人は、その次から始める。
    return (prefs.getBool(AppConfig.prefKeyPronunciationCoachShown) ?? false)
        ? 2
        : 0;
  }

  /// [step] の案内を出す。出せたら「閉じられたら完了する Future」を返す。
  /// 対象が描画されていない場合は null（この段は飛ばす）。
  Future<void>? _showCoachStep(int step) {
    final key = _coachKeys[step];
    final targetContext = key.currentContext;
    final box = targetContext?.findRenderObject() as RenderBox?;
    if (targetContext == null ||
        !targetContext.mounted ||
        box == null ||
        !box.hasSize ||
        box.size.height <= 0) {
      return null;
    }

    final l10n = L10n.of(context);
    final (icon, title, message) = switch (step) {
      0 => (
          Icons.article_outlined,
          l10n.coachSentenceCardTitle,
          l10n.coachSentenceCardMessage,
        ),
      1 => (
          Icons.play_arrow,
          l10n.coachPlayTitle,
          l10n.coachPlayMessage,
        ),
      2 => (
          Icons.mic_none,
          l10n.coachPronunciationTitle,
          l10n.coachPronunciationMessage,
        ),
      3 => (
          Icons.list_alt,
          l10n.coachWordDetailTitle,
          l10n.coachWordDetailMessage,
        ),
      4 => (
          Icons.lightbulb_outline,
          l10n.coachContextTitle,
          l10n.coachContextMessage,
        ),
      _ => (
          Icons.arrow_back,
          l10n.coachDetailBackTitle,
          l10n.coachDetailBackMessage,
        ),
    };

    // 段ごとに引き直す。出せなかった段（onDismiss が来ない）の値を持ち越すと、
    // 次の段の待ちまで飛ばしてしまう。
    _coachSkipped = false;

    final isExit = step == _coachKeys.length - 1;
    // 出口の段も押させる。案内するのが出口そのものなので、「わかった」で
    // 閉じると戻り方を試さないまま終わってしまう。
    final forceTap = isExit || _forcedTapSteps.contains(step);

    // 再生は押されて初めて始まる。終わったことを知らせてもらうため、
    // 押させる前に門を用意しておく。
    if (step == 1) {
      _playbackGate = Completer<void>();
      _playbackStarted = false;
      setState(() => _awaitingPlayback = true);
    }
    final completer = Completer<void>();
    _abortCoachWait = () {
      if (!completer.isCompleted) completer.complete();
      final gate = _playbackGate;
      if (gate != null && !gate.isCompleted) gate.complete();
    };
    unawaited(() async {
      // 対象は画面外にあることが多い。先に見せてから強調する。
      await Scrollable.ensureVisible(
        targetContext,
        alignment: 0.4,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
        if (!completer.isCompleted) completer.complete();
        return;
      }
      final shown = CoachMarkOverlay.show(
        context,
        targetKey: key,
        id: _coachIds[step],
        analytics: ref.read(analyticsServiceProvider),
        icon: icon,
        title: title,
        message: message,
        targetTappable: forceTap,
        barrierDismissible: !forceTap,
        // スキップは基本出さない。やらせたい操作を飛ばせると、案内した機能を
        // 一度も使わないまま終わる。押す先はどの段も1タップで済む。
        // 発音だけは例外（[_skippableSteps]）。
        skippable: _skippableSteps.contains(step),
        confirmLabel: forceTap ? null : l10n.coachGotIt,
        onDismiss: (action) {
          _coachSkipped = action == 'skipped';
          if (!completer.isCompleted) completer.complete();
        },
      );
      if (!shown && !completer.isCompleted) completer.complete();
      if (!shown || step != 2) return;
      await Future<void>.delayed(_permissionCue);
      // スキップされたら許可も聞かない。使わないと決めた機能のために
      // ダイアログを出しても、断られて次に試すときに困るだけ。
      if (_coachSkipped) return;
      await _requestMicPermission();
    }());
    return completer.future;
  }

  static const _coachIds = [
    'sentence_card',
    'play_sentence',
    'pronunciation',
    'word_detail',
    'context',
    'back',
  ];

  /// 押させる段の番号。読むだけでは分からない操作（再生・録音・単語の詳細）は
  /// 「わかった」で流させず、その場で一度やらせる。出口（最後の段）も同じ。
  ///
  /// 単語の詳細（声調解説）も押させる。「そこにある」と伝えるだけでは開かれず、
  /// 声調とつづりの関係を一度も見ないまま終わる。ただし玄人向けの話なので、
  /// 読んだうえで要らないと判断した人は抜けられる（[_skippableSteps]）。
  static const _forcedTapSteps = {1, 2, 3};

  /// 「スキップ」を出す段。押させる段のうち、発音（step 2）と
  /// 単語の詳細（step 3）は抜けられる。
  ///
  /// 発音は、声を出せない場所（電車内・職場）で初回ガイドに当たる人が居る。
  /// ここを塞ぐと初回体験ごと詰まる。再生と違って代わりの進め方が無い。
  /// 単語の詳細は、開くと声調解説がさらに案内を重ねる。今は読みたくない人を
  /// そこへ押し込まない。
  static const _skippableSteps = {2, 3};

  /// 単語の詳細（声調解説）が開いているか。初回ガイドで押させた段の
  /// 待ち（[_awaitWordDetailClosed]）に使う。
  bool _wordDetailOpen = false;

  /// 直前の段がスキップで閉じられたか。スキップされた段では、その操作の
  /// 完了待ち（[_awaitStepAction]）とマイク許可を飛ばす。
  bool _coachSkipped = false;

  @override
  Widget build(BuildContext context) {
    // pop 開始時点で閉じる。dispose まで待つと、戻りアニメーション中も
    // 発音コーチマークが例文画面の上に残り、ちらついて見える。
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        for (final key in _cleanupKeys) {
          CoachMarkOverlay.dismissFor(key);
        }
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // 戻るボタンは初回ガイドの最後で光らせる。位置を取るために
        // 既定の leading ではなく自前で置く。
        leading: Navigator.of(context).canPop()
            ? IconButton(
                key: _backKey,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              )
            : null,
        title: Text(L10n.of(context).detailTitle),
        actions: [
          // クリップボードにコピーするボタン
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareSentence,
            tooltip: L10n.of(context).detailShare,
          ),
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
      ),
    );
  }

  /// メイン例文カードを構築する。
  ///
  /// タイ語テキスト（選択可能）とTTS再生ボタン、ローマ字発音表記、
  /// 日本語訳を縦に並べて表示する。
  Widget _buildMainSentenceCard() {
    return Card(
      // 初回ガイドの1段目はカード全体を指す。タイ文字・読み・再生・訳が
      // 1枚に載っていることを、まとめて見せる。
      key: _sentenceKey,
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding * 1.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // タイ語テキスト（長押しでコピー可能）
                SelectableText(
                  widget.sentence.thaiText,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                        fontSize: 32,
                      ),
                ),
                const SizedBox(height: 8),
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
                const SizedBox(height: 8),
                // TTSの再生位置とリピート状態が分かる全文再生コントロール
                SentenceAudioPlayer(
                  text: widget.sentence.thaiText,
                  words: widget.sentence.wordBreakdowns
                      .map((w) => w.wordText)
                      .toList(),
                  playButtonKey: _playKey,
                  // 初回ガイドで押させた回だけ1周で止める。
                  singleCycle: _awaitingPlayback,
                  onPlaybackEnded: () {
                    final gate = _playbackGate;
                    if (gate != null && !gate.isCompleted) gate.complete();
                  },
                  onPlay: () {
                    _playbackStarted = true;
                    unawaited(
                      ref.read(analyticsServiceProvider).logPlayTts(
                            contentType: 'sentence',
                            text: widget.sentence.thaiText,
                            sentenceId: widget.sentence.id,
                            source: 'detail_sentence',
                          ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            // お手本を聞いたあとに自分で発声して声調を確かめる
            PronunciationPractice(
              key: _pronunciationKey,
              resultKey: _resultKey,
              contourKey: _contourKey,
              scope: 'detail',
              sentenceId: widget.sentence.id,
              words: widget.sentence.wordBreakdowns,
              thaiText: widget.sentence.thaiText,
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
            if (widget.sentence.targetWords != null &&
                widget.sentence.targetWords!.isNotEmpty)
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Set<String> get _targetWordSet => widget.sentence.targetWords?.toSet() ?? {};

  /// 初回ガイドで押させる単語の位置。
  ///
  /// 今日の学習単語を優先する。クイズで問われるのはこの語なので、声調の
  /// 解説を開かせるならここが一番効く。無い例文では先頭の語にする。
  int get _coachWordIndex {
    final words = widget.sentence.wordBreakdowns;
    final index = words.indexWhere((w) => _targetWordSet.contains(w.wordText));
    return index >= 0 ? index : 0;
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
                      L10n.of(context).detailWordBreakdown(
                          widget.sentence.wordBreakdowns.length),
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

  /// 単語の詳細（声調解説）を開く。
  Future<void> _openWordDetail(WordBreakdown word, int index) async {
    _wordDetailOpen = true;
    try {
      await ToneExplanationDialog.show(
        context,
        word.wordText,
        wordBreakdown: word,
      );
    } finally {
      _wordDetailOpen = false;
    }
  }

  /// 個別の単語分解アイテムを構築する。
  ///
  /// 番号付きの円形バッジ、タイ語テキスト、TTS再生ボタン、発音、
  /// 意味、文法的役割（タグ表示）を含む。
  /// タップすると声調解説ダイアログが開き、その単語の声調分析を確認できる。
  Widget _buildWordBreakdownItem(WordBreakdown word, int index) {
    final isTarget = _targetWordSet.contains(word.wordText);
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      // 初回ガイドでは今日の学習単語を押させる。スポットの対象はここ。
      key: index == _coachWordIndex ? _wordItemKey : null,
      onTap: () => unawaited(_openWordDetail(word, index)),
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isTarget
                            ? cs.tertiary.withValues(alpha: 0.15)
                            : cs.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isTarget ? cs.tertiary : cs.primary,
                          ),
                        ),
                      ),
                    ),
                    if (isTarget)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Icon(
                          Icons.auto_awesome,
                          size: 12,
                          color: cs.tertiary,
                        ),
                      ),
                  ],
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
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
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
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.7),
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
            if (word.notes != null && word.notes!.trim().isNotEmpty ||
                isTarget) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: cs.tertiary.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (word.notes != null && word.notes!.trim().isNotEmpty)
                      Text(
                        word.notes!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onTertiaryContainer,
                            ),
                      ),
                    if (isTarget) ...[
                      if (word.notes != null && word.notes!.trim().isNotEmpty)
                        const SizedBox(height: 4),
                      Text(
                        L10n.of(context).detailQuizTarget,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  cs.onTertiaryContainer.withValues(alpha: 0.6),
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
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
                  L10n.of(context).detailTapForTone,
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
      key: _contextKey,
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
                      L10n.of(context).detailContextSection,
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
                      L10n.of(context).detailContextTopic,
                      // サーバーが決めたテーマ識別子（日本語）。表示だけ訳す。
                      topicShortLabel(L10n.of(context), sentenceContext.topic),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // 文体（例: 口語体、書き言葉）
                  if (sentenceContext.style != null) ...[
                    _buildContextItem(
                      Icons.text_fields_outlined,
                      L10n.of(context).detailContextStyle,
                      // 文体は履歴の集計キーなので日本語のまま返る。表示だけ訳す。
                      styleLabel(L10n.of(context), sentenceContext.style!),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // 感情・トーン（例: 丁寧、カジュアル）
                  if (sentenceContext.emotion != null) ...[
                    _buildContextItem(
                      Icons.mood_outlined,
                      L10n.of(context).detailContextEmotion,
                      sentenceContext.emotion!,
                    ),
                    const SizedBox(height: 12),
                  ],
                  // 使用シーン（例: 友人との会話で）
                  if (sentenceContext.usageScenarios != null) ...[
                    _buildContextItem(
                      Icons.tips_and_updates_outlined,
                      L10n.of(context).detailContextUsage,
                      sentenceContext.usageScenarios!,
                    ),
                    const SizedBox(height: 12),
                  ],
                  // 文化的背景（例: タイでは年上への敬語が重要）
                  if (sentenceContext.culturalNotes != null) ...[
                    _buildContextItem(
                      Icons.info_outline,
                      L10n.of(context).detailContextCulture,
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
        : L10n.of(context).commonUnknown;

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
              L10n.of(context).detailCreatedAt(formattedDate),
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
