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
/// 学習タブと例文詳細の両方から使う。初回ガイドは2つのボタンをスポットするので、
/// キーはボタン側で受け取る。
class SentenceAudioSection extends ConsumerStatefulWidget {
  const SentenceAudioSection({
    super.key,
    required this.sentence,
    required this.analyticsSource,
    required this.practiceScope,
    this.listenButtonKey,
    this.practiceButtonKey,
    this.resultKey,
    this.contourKey,
    this.recordKey,
    this.singleCycle = false,
    this.onPlaybackEnded,
    this.onPlay,
  });

  final ThaiSentence sentence;

  /// TTS再生の計測に載せる出どころ。
  final String analyticsSource;

  /// 発音練習の判定を持ち回す単位。画面ごとに分けて持ち越さない。
  final String practiceScope;

  final Key? listenButtonKey;
  final Key? practiceButtonKey;
  final GlobalKey? resultKey;
  final GlobalKey? contourKey;

  /// 録音ボタンに付けるキー。初回ガイドがここを指す。
  final GlobalKey? recordKey;

  /// 初回ガイドで押させた回だけ1周で止める。
  final bool singleCycle;
  final VoidCallback? onPlaybackEnded;
  final VoidCallback? onPlay;

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

  /// 「お手本を聞く」。塗りのボタンで、開いている間だけ金にする。
  ///
  /// 深藍と白の役割（主・副）は変えない。開いていることは金で示す。金は
  /// アプリ全体で「いま効いているもの」の色なので、状態の色として読める。
  Widget _listenButton(String label) {
    return ElevatedButton.icon(
      key: widget.listenButtonKey,
      onPressed: _togglePlayer,
      style: _playerOpen
          ? ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: const Color(0xFF2A2007),
            )
          : null,
      icon: const Icon(Icons.play_arrow, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  /// 「発音してみる」。白いままで、開いている間だけ金の枠と薄い金地にする。
  Widget _practiceButton(String label) {
    return OutlinedButton.icon(
      key: widget.practiceButtonKey,
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
    final canPractise = canPractisePronunciation(sentence);
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
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SentenceAudioPlayer(
                    autoPlay: true,
                    text: sentence.thaiText,
                    words:
                        sentence.wordBreakdowns.map((w) => w.wordText).toList(),
                    singleCycle: widget.singleCycle,
                    onPlaybackEnded: widget.onPlaybackEnded,
                    onPlay: () {
                      widget.onPlay?.call();
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
                      resultKey: widget.resultKey,
                      contourKey: widget.contourKey,
                      recordKey: widget.recordKey,
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
