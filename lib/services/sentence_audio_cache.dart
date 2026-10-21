import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/config/firebase_config.dart';
import '../data/models/thai_sentence.dart';

/// お手本（例文の全文）のサーバー音声を取ってきて端末に保存する。
///
/// サーバー（getSentenceAudio）は Cloud TTS で作った MP3 を返す。声は例文の中身から
/// 決まるので、同じ文は何度取っても同じ声になる。一度取った文は端末から読むので、
/// オフラインでも鳴る。取れないとき（オフライン・失敗・遅すぎる）は null を返し、
/// 呼び出し側は端末の読み上げに戻す。
///
/// 保存は合計 [maxBytes] まで。超えたら最後に聞いたのが古い順に消す
/// （消した文はもう一度聞いたときに取り直す）。聞くたびに更新日時を付け直し、
/// 新しく保存したときに掃除する。
class SentenceAudioCache {
  SentenceAudioCache({FirebaseFunctions? functions}) : _functions = functions;

  FirebaseFunctions? _functions;
  Future<Directory>? _dir;
  final Map<String, Future<File?>> _inFlight = {};

  /// これ以上待つなら端末の読み上げで先に鳴らす。
  static const Duration timeout = Duration(seconds: 6);

  /// 保存の上限。1文 7〜20KB なので約2,000文。
  static const int maxBytes = 30 * 1024 * 1024;

  /// [source] の全文の音声ファイル。取れなければ null。
  Future<File?> fileFor(SentenceAudioSource source) {
    if (kIsWeb) return Future.value();
    final key = _key(source.text);
    // remove の戻り値（この Future 自身）を返すと whenComplete が自分を待って止まるので、
    // ブロックで包んで何も返さない。
    return _inFlight[key] ??= _load(key, source).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<File?> _load(String key, SentenceAudioSource source) async {
    try {
      final file = File('${(await (_dir ??= _openDir())).path}/$key.mp3');
      if (await file.exists()) {
        // 最後に聞いた日時として使う。掃除に古いと見なされないよう、付け終えてから返す。
        try {
          await file.setLastModified(DateTime.now());
        } catch (_) {}
        return file;
      }

      final functions = _functions ??= FirebaseFunctions.instanceFor(
        region: FirebaseConfig.functionsRegion,
      );
      final result = await functions
          .httpsCallable(
            FirebaseConfig.getSentenceAudioFunctionName,
            options: HttpsCallableOptions(timeout: timeout),
          )
          .call<Map<String, dynamic>>(source.toRequest())
          .timeout(timeout);
      final audio = result.data['audio'];
      if (audio is! String || audio.isEmpty) return null;

      // 書きかけのファイルを再生しないよう、別名で書いてから置き換える。
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(base64Decode(audio), flush: true);
      final saved = await tmp.rename(file.path);
      _pruneInBackground(saved.parent);
      return saved;
    } catch (e) {
      debugPrint('SentenceAudioCache: $e');
      return null;
    }
  }

  Future<void>? _pruning;

  /// 掃除は一度に1本だけ走らせる（同時に走ると数え方がずれる）。
  void _pruneInBackground(Directory dir) {
    _pruning ??= prune(dir, maxBytes).catchError((_) {}).whenComplete(() {
      _pruning = null;
    });
  }

  /// [dir] の mp3 の合計が [limit] を超えていたら、更新日時の古い順に消す。
  /// 数え始めてから聞かれた（更新日時が新しくなった）ものは消さない。
  @visibleForTesting
  static Future<void> prune(Directory dir, int limit) async {
    final startedAt = DateTime.now();
    final files = <(File, FileStat)>[];
    var total = 0;
    await for (final e in dir.list()) {
      if (e is! File || !e.path.endsWith('.mp3')) continue;
      final stat = await e.stat();
      files.add((e, stat));
      total += stat.size;
    }
    if (total <= limit) return;
    files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final (file, stat) in files) {
      if (total <= limit) break;
      try {
        if ((await file.lastModified()).isBefore(startedAt)) {
          await file.delete();
        }
        total -= stat.size;
      } catch (_) {}
    }
  }

  Future<Directory> _openDir() async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/sentence_audio',
    );
    await dir.create(recursive: true);
    return dir;
  }

  /// 端末のファイル名。サーバーと同じく絵文字・空白の違いは同じ文として扱う。
  static String _key(String text) =>
      sha256.convert(utf8.encode(normalize(text))).toString();

  static final RegExp _emoji = RegExp(
    r'[\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}\u{2300}-\u{23FF}\u{2B00}-\u{2BFF}\u{FE00}-\u{FE0F}\u{1F1E6}-\u{1F1FF}\u{200D}]',
    unicode: true,
  );

  static String normalize(String text) =>
      text.replaceAll(_emoji, '').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// サーバーで声を決めるのに要る例文の中身（全文・テーマ・単語分解）。
class SentenceAudioSource {
  const SentenceAudioSource({
    required this.text,
    this.topic,
    this.words = const [],
  });

  factory SentenceAudioSource.of(ThaiSentence sentence) => SentenceAudioSource(
        text: sentence.thaiText,
        topic: sentence.context?.topic,
        words: [
          for (final w in sentence.wordBreakdowns)
            {
              'word': w.wordText,
              'meaning': w.meaning,
              'grammatical_role': w.grammaticalRole ?? '',
            },
        ],
      );

  final String text;
  final String? topic;
  final List<Map<String, String>> words;

  Map<String, dynamic> toRequest() => {
        'thai_text': text,
        'topic': topic ?? '',
        'words': words,
      };
}
