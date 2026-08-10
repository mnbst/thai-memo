import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  final Random _random = Random();
  bool _isInitialized = false;
  List<Map<String, String>> _thaiVoices = [];
  Completer<void>? _cancelCompleter;
  int _session = 0;

  /// 再生セッションの通し番号。[stopAll] のたびに進む。
  ///
  /// TTSはインスタンスが1つしかないため、リピート再生のループを回している側は
  /// この値が変わっていないかを見て、自分の再生が外から打ち切られたかを判断する。
  int get session => _session;

  /// iOS の共有オーディオセッションを発話向けのカテゴリに戻す。
  ///
  /// defaultToSpeaker は playAndRecord 専用。playback に混ぜると
  /// iOS 側の setCategory が失敗し、カテゴリが soloAmbient のまま残って
  /// 発話音量が着信音量に追従してしまう（＝極端に小さくなる）。
  /// カテゴリを決めてからセッションを activate する順序も必須。
  ///
  /// セッションはアプリ全体で1つしかなく、発音チェックの収録が
  /// playAndRecord に切り替える。収録側でも戻しているが、こちらでも
  /// 毎回かけ直して、誰が触った後でも発話が小さくならないようにする。
  Future<void> _applyIosAudioCategory() async {
    if (!Platform.isIOS) return;
    await _tts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playback,
      [
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
      ],
    );
  }

  Future<void> _init() async {
    if (_isInitialized) return;

    if (Platform.isIOS) {
      await _applyIosAudioCategory();
      await _tts.setSharedInstance(true);
    }

    await _tts.setLanguage('th-TH');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    // [speak] を発話完了まで待つようにする。リピート再生の待ち時間を
    // 「読み終わってから」計るために必要。停止時も future は解決する。
    await _tts.awaitSpeakCompletion(true);
    // 発話中の文字範囲。対応していないプラットフォームでは呼ばれない。
    _tts.setProgressHandler((text, start, end, word) {
      onProgress?.call(start, end);
    });
    _tts.setCancelHandler(() {
      final completer = _cancelCompleter;
      if (completer != null && !completer.isCompleted) completer.complete();
    });

    // タイ語の音声一覧を取得
    final voices = await _tts.getVoices;
    if (voices != null) {
      _thaiVoices = (voices as List)
          .where((v) => v['locale']?.toString().startsWith('th') == true)
          .map<Map<String, String>>((v) =>
              {'name': v['name'].toString(), 'locale': v['locale'].toString()})
          .toList();
    }

    _isInitialized = true;
  }

  Future<void> _pickRandomVoice() async {
    if (_thaiVoices.isEmpty) return;
    final voice = _thaiVoices[_random.nextInt(_thaiVoices.length)];
    await _tts.setVoice({'name': voice['name']!, 'locale': voice['locale']!});
  }

  static final RegExp _emojiRegex = RegExp(
    r'[\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}\u{2300}-\u{23FF}\u{2B00}-\u{2BFF}\u{FE00}-\u{FE0F}\u{1F1E6}-\u{1F1FF}\u{200D}]',
    unicode: true,
  );

  String _stripEmoji(String text) =>
      text.replaceAll(_emojiRegex, '').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// 発話中の位置通知（引数は発話テキスト内の文字オフセット）。
  ///
  /// 単語境界ごとに呼ばれる。タイ語は語間に空白が無く、プラットフォームが
  /// 文全体を1範囲として扱う場合もあるため、届かないことを前提に使う。
  void Function(int start, int end)? onProgress;

  /// 発話する。完了（または停止）まで待つ。
  ///
  /// [keepVoice] が true のときは声を選び直さない。リピート再生の途中で
  /// 話者が変わらないようにするために使う。
  Future<void> speak(
    String text, {
    bool slow = false,
    bool keepVoice = false,
  }) async {
    await _init();
    await _applyIosAudioCategory();
    if (!keepVoice) await _pickRandomVoice();
    await _tts.setSpeechRate(slow ? 0.3 : 0.5);
    await _tts.stop();
    final sanitized = _stripEmoji(text);
    if (sanitized.isEmpty) return;
    await _tts.speak(sanitized);
  }

  /// 発話を停止する。
  ///
  /// iOS のネイティブ実装は stop のメソッド呼び出しを即時に返し、その後で
  /// didCancel が届く。[waitForCancel] はシーク再開時にその通知を待ち、新しい
  /// 発話までキャンセルに巻き込まれる競合を防ぐ。
  Future<void> stop({bool waitForCancel = false}) async {
    final cancelCompleter = waitForCancel ? Completer<void>() : null;
    if (cancelCompleter != null) _cancelCompleter = cancelCompleter;
    await _tts.stop();
    if (cancelCompleter != null) {
      await Future.any<void>([
        cancelCompleter.future,
        // 既に発話が終わっている場合は didCancel が来ないため、上限を設ける。
        Future<void>.delayed(const Duration(milliseconds: 300)),
      ]);
      if (identical(_cancelCompleter, cancelCompleter)) {
        _cancelCompleter = null;
      }
    }
  }

  /// 再生中の発話を止め、リピート再生のループも打ち切る。
  ///
  /// 画面遷移・タブ切り替えのように「再生UIの外」から止めるときに使う。
  /// [stop] だけではループ側が次の周回を再開してしまう。
  Future<void> stopAll() async {
    _session++;
    await stop();
  }

  void dispose() {
    _session++;
    _tts.stop();
  }
}
