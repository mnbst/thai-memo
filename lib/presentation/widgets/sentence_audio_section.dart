import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/thai_sentence.dart';
import '../../l10n/app_localizations.dart';
import '../providers/analytics_provider.dart';
import '../providers/tts_provider.dart';
import 'pronunciation_practice.dart';
import 'pronunciation_sheet.dart';
import 'sentence_audio_player.dart';

/// 例文の下に置く「お手本を聞く」「発音練習」の2ボタンと、その下に開く中身。
///
/// 聞くと話すは対の操作なので、同じ高さで横に並べ、どちらを先にやってもいい
/// 形にする。平常時はどちらも畳んでおく。頭出しバーや録音UIを常に出しておくと、
/// まだ何も鳴っていない操作パネルが例文の下に居座る。
///
/// 学習タブと例文詳細の両方から使う。
class SentenceAudioSection extends ConsumerStatefulWidget {
  const SentenceAudioSection({
    super.key,
    required this.sentence,
    required this.analyticsSource,
    required this.practiceScope,
    this.showPractice = true,
  });

  final ThaiSentence sentence;

  /// TTS再生の計測に載せる出どころ。
  final String analyticsSource;

  /// 発音練習の判定を持ち回す単位。画面ごとに分けて持ち越さない。
  final String practiceScope;

  /// 「発音練習」を出すか。学習タブでは出さない（false）。
  ///
  /// 録音は押しっぱなし・判定の読み込みまで含めて縦を大きく取る操作なので、
  /// 詳細画面に一本化する。学習タブは 読む → 覚えたか確認 の一本道に保つ。
  final bool showPractice;

  @override
  ConsumerState<SentenceAudioSection> createState() =>
      SentenceAudioSectionState();
}

class SentenceAudioSectionState extends ConsumerState<SentenceAudioSection> {
  bool _expanded = false;
  bool _playerOpen = false;

  @override
  void didUpdateWidget(SentenceAudioSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 次の例文に進んだら畳んだ状態から始める
    if (oldWidget.sentence.id != widget.sentence.id &&
        (_expanded || _playerOpen)) {
      setState(() {
        _expanded = false;
        _playerOpen = false;
      });
    }
  }

  /// 練習セクションを開く。既に開いていれば何もしない。
  ///
  /// 初回ガイドが録音ボタンを指す前に呼ぶ。畳んだままだと指す対象が無く、
  /// 「発音してみる」を押させる段を挟むと、開いた先で案内が消えてしまう。
  void openPractice() {
    if (_expanded) return;
    _toggle();
  }

  void _toggle() {
    // お手本と録音を奪い合わせない。開くときは再生を止める。
    if (!_expanded) unawaited(ref.read(ttsServiceProvider).stopAll());
    setState(() {
      _expanded = !_expanded;
      if (_expanded) _playerOpen = false;
    });
  }

  void _togglePlayer() {
    if (_playerOpen) {
      unawaited(ref.read(ttsServiceProvider).stopAll());
      setState(() => _playerOpen = false);
      return;
    }
    setState(() {
      _playerOpen = true;
      _expanded = false;
    });
  }

  /// 「お手本を聞く」。開いている間だけ金にする。金はアプリ全体で
  /// 「いま効いているもの」の色なので、状態の色として読める。
  ///
  /// 学習タブでは発音練習を並べないぶん全幅になる。そこで塗りのままだと
  /// 面積が大きく、下の「覚えたか確認」（この画面の主導線）より重く見える。
  /// 単独で置く回は枠のボタンに落として、主役を譲る。
  Widget _listenButton(String label) {
    if (!widget.showPractice) return _blendedListenButton(label);
    if (_playerOpen) {
      return ElevatedButton.icon(
        onPressed: _togglePlayer,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: const Color(0xFF2A2007),
        ),
        icon: const Icon(Icons.play_arrow, size: 18),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
    }
    return ElevatedButton.icon(
      onPressed: _togglePlayer,
      icon: const Icon(Icons.play_arrow, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  /// 学習タブ用の「お手本を聞く」。
  ///
  /// 面は持たせない。例文カードに付く操作であって、この画面の主導線
  /// （覚えたか確認）ではない。箱を描くと主導線と同じ重さで並ぶ。
  /// 開いている間は字だけ深藍から金へ替える。金はアプリ全体で「いま効いて
  /// いるもの」の色なので、字の色だけで状態が読める。
  Widget _blendedListenButton(String label) {
    final foreground = _playerOpen ? AppColors.goldInk : AppColors.indigo;
    return TextButton.icon(
      onPressed: _togglePlayer,
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        backgroundColor: Colors.transparent,
        foregroundColor: foreground,
        // 波紋も押下中の面も角丸の矩形で描かれる。面を持たないボタンの上に
        // 出すと、押した瞬間だけ箱が浮き出る。
        overlayColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        shape: const RoundedRectangleBorder(),
      ),
      icon: const Icon(Icons.play_arrow, size: 16),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  /// 「発音してみる」。白いままで、開いている間だけ金の枠と薄い金地にする。
  Widget _practiceButton(String label) {
    return OutlinedButton.icon(
      onPressed: _toggle,
      style: _expanded
          ? OutlinedButton.styleFrom(
              backgroundColor: AppColors.gold.withValues(alpha: 0.14),
              foregroundColor: AppColors.goldInk,
              side: const BorderSide(color: AppColors.goldInk, width: 1.5),
            )
          : null,
      icon: const Icon(Icons.mic_rounded, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sentence = widget.sentence;
    final canPractise =
        widget.showPractice && canPractisePronunciation(sentence);
    final l10n = L10n.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _listenButton(l10n.sentenceListenModel)),
            if (canPractise) ...[
              const SizedBox(width: 10),
              Expanded(child: _practiceButton(l10n.sentencePractice)),
            ],
          ],
        ),
        // 単語単位の頭出しバーは「聞く」を押したときだけ出す。
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _playerOpen
              // バーはボタンの続き。上は詰めて1組に見せ、下だけ空けて
              // 次の見出し（学習単語）とぶつけない。
              ? Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 6),
                  child: SentenceAudioPlayer(
                    autoPlay: true,
                    text: sentence.thaiText,
                    words:
                        sentence.wordBreakdowns.map((w) => w.wordText).toList(),
                    onPlay: () {
                      unawaited(
                        ref.read(analyticsServiceProvider).logPlayTts(
                              contentType: 'sentence',
                              text: sentence.thaiText,
                              sentenceId: sentence.id,
                              source: widget.analyticsSource,
                            ),
                      );
                    },
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: canPractise && _expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  // カード全体が詳細へのタップ領域なので、練習中の空振りで
                  // 画面遷移しないようここでタップを吸収する。
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: PronunciationPractice(
                      scope: widget.practiceScope,
                      sentenceId: sentence.id,
                      words: sentence.wordBreakdowns,
                      thaiText: sentence.thaiText,
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
