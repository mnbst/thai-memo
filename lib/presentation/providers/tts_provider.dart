import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/tts_service.dart';

final ttsServiceProvider = Provider<TtsService>((ref) {
  final service = TtsService();
  ref.onDispose(() => service.dispose());
  return service;
});
