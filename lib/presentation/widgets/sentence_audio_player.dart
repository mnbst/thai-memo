import 'dart:async';

import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/tts_service.dart';
import '../providers/tts_provider.dart';

/// 例文全文の再生コントロール。
///
/// 再生／一時停止、単語単位の頭出しバー、リピート切り替えを持つ。
/// リピート中は1周のあいだに [repeatInterval] だけ間を置くので、
/// 聞き取り→復唱を繰り返す練習に使える。
///
/// バーは「シークバー」だが、TTSからは再生時間も現在位置も取れないため
/// 秒単位のシークではなく[words]（単語分解）の境界へのジャンプになる。
/// 再生位置の表示はプラットフォームが文字範囲を通知する場合のみ進む
/// （タイ語は語間に空白が無く通知されないことがあるため、その場合は
/// 再生中の単語位置＝つまみの位置は動かない）。
class SentenceAudioPlayer extends ConsumerStatefulWidget {
  const SentenceAudioPlayer({
    super.key,
    required this.text,
    this.words = const [],
    this.onPlay,
    this.trailing,
    this.repeatInterval = const Duration(milliseconds: 1000),
    this.playButtonKey,
    this.singleCycle = false,
    this.onPlaybackEnded,
    this.autoPlay = false,
  });

  /// 読み上げる全文。
  final String text;

  /// 頭出しの単位となる単語列（[text] に出現する順）。空なら頭出しバーは出さない。
  final List<String> words;

  /// 再生開始時に呼ばれる（アナリティクス用）。リピートでは呼ばない。
  final VoidCallback? onPlay;

  /// 行末（シークバーの右）に並べる任意のボタン（発音練習など）。
  /// 再生を主役に置いたまま「話す」を同じ行に足すための枠。無ければ出さない。
  final Widget? trailing;

  /// 1周ごとに置く間。
  final Duration repeatInterval;

  /// 再生ボタンを外から指すためのキー（初回ガイドのスポット対象）。
  final GlobalKey? playButtonKey;

  /// 1周で自動的に止める。リピート設定より優先する。
  /// 初回ガイドで押させたときに、鳴りっぱなしのまま次の案内へ進ませないため。
  final bool singleCycle;

  /// 表示された時点で再生を始める。
  /// 「お手本を聞く」を押して開く使い方で、もう一度押させないため。
  final bool autoPlay;

  /// 再生が終わった（1周終了・停止・一時停止）。
  /// 初回ガイドが「聞き終わったか」を知るために使う。
  final VoidCallback? onPlaybackEnded;

  @override
  ConsumerState<SentenceAudioPlayer> createState() =>
      _SentenceAudioPlayerState();
}

class _SentenceAudioPlayerState extends ConsumerState<SentenceAudioPlayer> {
  /// dispose 時にも停止させるため、ref ではなく実体を保持する。
  late final TtsService _tts;
  final _playButtonKey = GlobalKey();

  /// 単語ごとの [SentenceAudioPlayer.text] 内の開始位置。
  late List<int> _wordOffsets;

  bool _playing = false;
  bool _repeatEnabled = true;

  /// 再生位置（0.0〜1.0）。
  double _progress = 0;

  /// つまみをドラッグ中の値。離すまで再生位置には反映しない。
  double? _dragValue;

  /// 停止・シークで進行中のループを無効化するための世代番号。
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _tts = ref.read(ttsServiceProvider);
    _wordOffsets = wordStartOffsets(widget.text, widget.words);
    if (widget.autoPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_start());
      });
    }
  }

  @override
  void didUpdateWidget(SentenceAudioPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _stop();
      _wordOffsets = wordStartOffsets(widget.text, widget.words);
    }
  }

  @override
  void dispose() {
    _generation++;
    _tts.onProgress = null;
    unawaited(_tts.stop());
    super.dispose();
  }

  bool get _seekable => _wordOffsets.length > 1;

  Future<void> _start({
    int fromWord = 0,
    bool notifyPlay = true,
  }) async {
    final generation = ++_generation;
    final session = _tts.session;
    if (notifyPlay) widget.onPlay?.call();

    setState(() {
      _playing = true;
      _progress = _progressOfWord(fromWord);
    });

    var startWord = fromWord;
    while (mounted && generation == _generation) {
      if (_abortedBySession(session)) return;
      final cycleStartWord = startWord;
      // シーク位置は現在の1周にだけ適用する。次の周回はシーク位置を
      // 引き継がず、必ず全文の先頭から始める。
      startWord = 0;
      _tts.onProgress = (start, _) {
        if (!mounted || generation != _generation) return;
        final offset = _wordOffsets.isEmpty ? 0 : _wordOffsets[cycleStartWord];
        setState(
          () => _progress = ((offset + start) / widget.text.length).clamp(0, 1),
        );
      };
      await _tts.speak(
        _textFromWord(cycleStartWord),
        keepVoice: cycleStartWord != 0,
      );
      if (!mounted || generation != _generation) return;
      if (_abortedBySession(session)) return;

      // 読み上げ完了後は、再生モードに関係なく次回に備えて先頭へ戻す。
      setState(() => _progress = 0);
      if (widget.singleCycle) {
        _tts.onProgress = null;
        unawaited(_tts.stop());
        setState(() => _playing = false);
        widget.onPlaybackEnded?.call();
        return;
      }
      if (!_repeatEnabled) {
        _tts.onProgress = null;
        setState(() => _playing = false);
        widget.onPlaybackEnded?.call();
        return;
      }

      await Future<void>.delayed(widget.repeatInterval);
      if (!mounted || generation != _generation) return;
      if (!_repeatEnabled) {
        _tts.onProgress = null;
        setState(() => _playing = false);
        widget.onPlaybackEnded?.call();
        return;
      }
    }
  }

  /// 他画面が [TtsService.stopAll] を呼んで再生が打ち切られたかを判定する。
  ///
  /// 打ち切られていれば再生表示も落とす（ボタンが「一時停止」のまま
  /// 残らないようにする）。
  bool _abortedBySession(int session) {
    if (session == _tts.session) return false;
    _tts.onProgress = null;
    if (mounted) {
      setState(() {
        _playing = false;
        _progress = 0;
      });
    }
    return true;
  }

  void _stop({bool resetProgress = true}) {
    final wasPlaying = _playing;
    _generation++;
    _tts.onProgress = null;
    unawaited(_tts.stop());
    if (mounted) {
      setState(() {
        _playing = false;
        if (resetProgress) _progress = 0;
        _dragValue = null;
      });
    }
    // 途中で止めた回も「聞き終わった」として扱う。待っている側を
    // 鳴り止んだまま待たせない。
    if (wasPlaying) widget.onPlaybackEnded?.call();
  }

  String _textFromWord(int index) {
    if (index <= 0 || index >= _wordOffsets.length) return widget.text;
    return widget.text.substring(_wordOffsets[index]);
  }

  double _progressOfWord(int index) {
    if (index <= 0 || index >= _wordOffsets.length) return 0;
    return _wordOffsets[index] / widget.text.length;
  }

  Future<void> _seekAndResume(int index) async {
    // 旧ループを先に無効化し、ネイティブTTSの停止完了を待ってから再開する。
    // speak と stop が競合すると、シーク先の発話が即座に打ち切られて
    // 旧ループの先頭再生へ戻ることがある。
    final seekGeneration = ++_generation;
    _tts.onProgress = null;
    await _tts.stop(waitForCancel: true);
    if (!mounted || seekGeneration != _generation) return;
    await _start(fromWord: index, notifyPlay: false);
  }

  void _onSeekEnd(double value) {
    final index = wordIndexAtProgress(
      offsets: _wordOffsets,
      textLength: widget.text.length,
      progress: value,
    );
    final progress = _progressOfWord(index);
    setState(() {
      _dragValue = null;
      _progress = progress;
    });
    if (_playing) {
      unawaited(_seekAndResume(index));
    }
  }

  Future<void> _choosePlaybackMode() async {
    final buttonContext = _playButtonKey.currentContext;
    if (buttonContext == null) return;
    final buttonBox = buttonContext.findRenderObject()! as RenderBox;
    final overlayBox =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final buttonRect = Rect.fromPoints(
      buttonBox.localToGlobal(Offset.zero, ancestor: overlayBox),
      buttonBox.localToGlobal(
        buttonBox.size.bottomRight(Offset.zero),
        ancestor: overlayBox,
      ),
    );

    final repeat = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromRect(
        buttonRect,
        Offset.zero & overlayBox.size,
      ),
      items: [
        PopupMenuItem<bool>(
          enabled: false,
          padding: const EdgeInsets.all(6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PlaybackModeOption(
                icon: Icons.repeat,
                label: L10n.of(context).audioRepeat,
                selected: _repeatEnabled,
                onTap: () => Navigator.pop(context, true),
              ),
              const SizedBox(
                height: 36,
                child: VerticalDivider(width: 1),
              ),
              _PlaybackModeOption(
                icon: Icons.play_arrow,
                label: L10n.of(context).audioOnce,
                selected: !_repeatEnabled,
                onTap: () => Navigator.pop(context, false),
              ),
            ],
          ),
        ),
      ],
    );
    if (!mounted || repeat == null) return;
    setState(() => _repeatEnabled = repeat);
  }

  @override
  Widget build(BuildContext context) {
    final progress = _dragValue ?? _progress;

    final playButton = Semantics(
      button: true,
      label:
          _playing ? L10n.of(context).audioPause : L10n.of(context).audioPlay,
      hint: L10n.of(context).audioModeHint(_repeatEnabled
          ? L10n.of(context).audioModeRepeat
          : L10n.of(context).audioModeOnce),
      child: GestureDetector(
        key: _playButtonKey,
        onLongPress: _choosePlaybackMode,
        child: IconButton.filledTonal(
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
          onPressed: () {
            if (_playing) {
              _stop(resetProgress: false);
            } else {
              unawaited(_start(
                fromWord: wordIndexAtProgress(
                  offsets: _wordOffsets,
                  textLength: widget.text.length,
                  progress: _progress >= 1 ? 0 : _progress,
                ),
              ));
            }
          },
        ),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        KeyedSubtree(key: widget.playButtonKey, child: playButton),
        const SizedBox(width: 4),
        Expanded(
          child: Semantics(
            label: L10n.of(context).audioPosition,
            value: '${(progress * 100).round()}%',
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                value: progress,
                onChanged: _seekable
                    ? (value) => setState(() => _dragValue = value)
                    : null,
                onChangeEnd: _seekable ? _onSeekEnd : null,
              ),
            ),
          ),
        ),
        if (widget.trailing != null) ...[
          const SizedBox(width: 4),
          widget.trailing!,
        ],
      ],
    );
  }
}

class _PlaybackModeOption extends StatelessWidget {
  const _PlaybackModeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 88,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [words] が [text] に現れる開始位置を順に返す。
///
/// 単語分解と本文がずれている（見つからない）場合は頭出しできないため
/// 空リストを返す。先頭は常に0。
List<int> wordStartOffsets(String text, List<String> words) {
  if (words.isEmpty) return const [];
  final offsets = <int>[];
  var cursor = 0;
  for (final word in words) {
    if (word.isEmpty) continue;
    final index = text.indexOf(word, cursor);
    if (index < 0) return const [];
    offsets.add(index);
    cursor = index + word.length;
  }
  return offsets;
}

/// 再生位置（0.0〜1.0）に対応する単語の添字を返す。
///
/// その位置以前で最後に始まる単語＝そこから読み直すべき単語を選ぶ。
int wordIndexAtProgress({
  required List<int> offsets,
  required int textLength,
  required double progress,
}) {
  if (offsets.isEmpty || textLength == 0) return 0;
  final target = progress * textLength;
  var index = 0;
  for (var i = 0; i < offsets.length; i++) {
    if (offsets[i] <= target) {
      index = i;
    } else {
      break;
    }
  }
  return index;
}
