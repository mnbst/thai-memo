import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/sentence_audio_cache.dart';
import '../../services/tts_service.dart';

final ttsServiceProvider = Provider<TtsService>((ref) {
  final service = TtsService(audioCache: SentenceAudioCache());
  ref.onDispose(() => service.dispose());
  return service;
});

/// お手本の再生速度。アプリを開いているあいだは例文をまたいで引き継ぐ。
final ttsSpeedProvider = StateProvider<TtsSpeed>((ref) => TtsSpeed.normal);
