import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import '../core/platform/store_platform.dart';
import 'sentence_audio_cache.dart';

/// お手本の再生速度。[label] は通常速度に対するおおよその倍率。
///
/// iOS（AVSpeechUtterance）は 0.5 未満で遅くなり方が鈍く、0.4 と 0.45 が
/// 同じ長さになる。実測で長さが約1割ずつ伸びる 0.4 / 0.3 / 0.2 を使う。
/// Android は flutter_tts が値を2倍して渡し、ほぼ比例して遅くなる。
///
/// サーバー音声は [factor] で再生側を伸ばす（音程は変わらない）。0.7 倍までなら聞き取れる。
enum TtsSpeed {
  normal('1.0x', 1.0, ios: 0.5, android: 0.5),
  slight('0.9x', 0.9, ios: 0.4, android: 0.45),
  slow('0.8x', 0.8, ios: 0.3, android: 0.4),
  slower('0.7x', 0.7, ios: 0.2, android: 0.35);

  const TtsSpeed(this.label, this.factor,
      {required this.ios, required this.android});

  final String label;
  final double factor;
  final double ios;
  final double android;

  double get rate =>
      StorePlatform.current == StorePlatform.appStore ? ios : android;

  /// ボタンを押すたびに 1.0x → 0.9x → 0.8x → 0.7x → 1.0x と巡る。
  TtsSpeed get next => values[(index + 1) % values.length];
}

class TtsService {
  TtsService({SentenceAudioCache? audioCache}) : _audioCache = audioCache;

  final FlutterTts _tts = FlutterTts();

  /// お手本のサーバー音声。null なら常に端末の読み上げ。
  final SentenceAudioCache? _audioCache;

  /// サーバー音声の再生器。最初に使うときに作る。
  AudioPlayer? _player;
  final Random _random = Random();
  bool _isInitialized = false;
  List<Map<String, String>> _thaiVoices = [];
  Completer<void>? _cancelCompleter;
  int _session = 0;

  /// Android の読み上げエンジンにタイ語が入っていないとき、最初の発話で1回だけ流れる。
  /// iOS は標準でタイ語の声を持つので流れない。
  final StreamController<void> _thaiVoiceMissing = StreamController.broadcast();
  Stream<void> get thaiVoiceMissing => _thaiVoiceMissing.stream;
  bool _thaiVoiceUnavailable = false;
  bool _thaiVoiceMissingNotified = false;

  static const MethodChannel _settingsChannel =
      MethodChannel('thai_memo/tts_settings');

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
    if (StorePlatform.current != StorePlatform.appStore) return;
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

    switch (StorePlatform.current) {
      case StorePlatform.appStore:
        await _applyIosAudioCategory();
        await _tts.setSharedInstance(true);
      case StorePlatform.googlePlay:
        // 端末の読み上げエンジン次第で、タイ語の音声データが無いことがある。
        _thaiVoiceUnavailable =
            await _tts.isLanguageAvailable('th-TH') != true;
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
  /// [slow] は単語のゆっくり読み用で、[speed] より優先する。
  Future<void> speak(
    String text, {
    bool slow = false,
    bool keepVoice = false,
    TtsSpeed speed = TtsSpeed.normal,
  }) async {
    await _init();
    if (_thaiVoiceUnavailable && !_thaiVoiceMissingNotified) {
      _thaiVoiceMissingNotified = true;
      _thaiVoiceMissing.add(null);
    }
    await _applyIosAudioCategory();
    if (!keepVoice) await _pickRandomVoice();
    await _tts.setSpeechRate(slow ? 0.3 : speed.rate);
    await _player?.stop();
    await _tts.stop();
    final sanitized = _stripEmoji(text);
    if (sanitized.isEmpty) return;
    await _tts.speak(sanitized);
  }

  /// これより早く鳴り始めるならローディングを出さない（ちらつかせない）。
  static const Duration loadingDelay = Duration(milliseconds: 300);

  /// お手本（例文の全文）を [fromChar] 文字目から読む。完了（または停止）まで待つ。
  ///
  /// サーバー音声が取れればそれを鳴らし、取れないとき・読み込めないときは端末の読み上げに戻す。
  /// サーバー音声の頭出しは、文字数の比で再生時間を割って位置を決める。
  /// [onProgress] にはどちらの経路でも、[fromChar] からの文字オフセットを渡す。
  /// [onLoading] は取得に [loadingDelay] より長くかかったときに true、
  /// 取得が終わったら false で呼ぶ（端末に保存済みなら呼ばない）。
  /// [stillWanted] が false になったら、そこから先は鳴らさない（待つあいだに一時停止された）。
  ///
  /// 最後まで読み終えたら true。止められた・OS に中断された（着信・ヘッドホンを抜いた等）なら
  /// false を返す。呼び出し側は false のときリピートを続けない。
  Future<bool> speakSentence(
    SentenceAudioSource source, {
    int fromChar = 0,
    bool keepVoice = false,
    TtsSpeed speed = TtsSpeed.normal,
    void Function(bool loading)? onLoading,
    bool Function()? stillWanted,
  }) async {
    final session = _session;
    bool wanted() => session == _session && stillWanted?.call() != false;

    var loading = false;
    final timer = Timer(loadingDelay, () {
      loading = true;
      onLoading?.call(true);
    });
    final file = await _audioCache?.fileFor(source);
    timer.cancel();
    if (loading) onLoading?.call(false);
    if (!wanted()) return false;

    if (file != null) {
      final finished = await _playFile(file, source.text.length,
          fromChar: fromChar, speed: speed, wanted: wanted);
      if (finished != null) return finished;
      // 読み込めなかった（壊れたファイル等）。消して端末の読み上げで読む。次は取り直す。
      try {
        await file.delete();
      } catch (_) {}
      if (!wanted()) return false;
    }
    final text = fromChar > 0 && fromChar < source.text.length
        ? source.text.substring(fromChar)
        : source.text;
    await speak(text, keepVoice: keepVoice, speed: speed);
    // 端末の読み上げは、読み終わりと停止を見分けられない。
    return wanted();
  }

  /// サーバー音声を鳴らす。最後まで鳴ったら true、止められた・中断されたら false、
  /// 読み込めなかったら null。
  Future<bool?> _playFile(
    File file,
    int length, {
    required int fromChar,
    required TtsSpeed speed,
    required bool Function() wanted,
  }) async {
    final player = _player ??= AudioPlayer();
    StreamSubscription<Duration>? sub;
    try {
      await _tts.stop();
      await _applyIosAudioCategory();
      final duration = await player.setFilePath(file.path);
      if (!wanted()) return false;
      // 同じファイルを読み直しても位置は先頭に戻らないので、毎回動かす。
      await player.seek(duration != null && fromChar > 0 && length > 0
          ? duration * (fromChar / length)
          : Duration.zero);
      await player.setSpeed(speed.factor);
      if (!wanted()) return false;
      sub = player.positionStream.listen((pos) {
        if (duration == null || duration == Duration.zero) return;
        final char = (pos.inMilliseconds / duration.inMilliseconds * length)
            .floor()
            .clamp(fromChar, length);
        onProgress?.call(char - fromChar, char - fromChar);
      });
      // 再生の終わり・一時停止・停止のどれかで返る。終わりまで鳴ったかは状態で見分ける。
      await player.play();
      return player.processingState == ProcessingState.completed;
    } on PlayerInterruptedException {
      // 読み込み中に stop された。
      return false;
    } catch (e) {
      debugPrint('TtsService: サーバー音声を鳴らせない: $e');
      return null;
    } finally {
      await sub?.cancel();
      // 最後まで鳴らし終えても playing は true のまま残り、次の play() が
      // 鳴らさずに即座に返ってしまう。止めた状態へ戻しておく。
      if (player.playing) await player.pause();
    }
  }

  /// 発話を停止する。
  ///
  /// iOS のネイティブ実装は stop のメソッド呼び出しを即時に返し、その後で
  /// didCancel が届く。[waitForCancel] はシーク再開時にその通知を待ち、新しい
  /// 発話までキャンセルに巻き込まれる競合を防ぐ。
  Future<void> stop({bool waitForCancel = false}) async {
    final cancelCompleter = waitForCancel ? Completer<void>() : null;
    if (cancelCompleter != null) _cancelCompleter = cancelCompleter;
    await _player?.stop();
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

  /// 読み上げエンジンの音声データのダウンロード画面を開く（Android）。
  Future<void> openVoiceInstaller() async {
    try {
      await _settingsChannel.invokeMethod<void>('openVoiceInstaller');
    } on PlatformException catch (e) {
      debugPrint('openVoiceInstaller failed: $e');
    }
  }

  void dispose() {
    _session++;
    _tts.stop();
    _player?.dispose();
    _thaiVoiceMissing.close();
  }
}
