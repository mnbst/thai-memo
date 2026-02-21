import 'dart:math';

import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  final Random _random = Random();
  bool _isInitialized = false;
  List<Map<String, String>> _thaiVoices = [];

  Future<void> _init() async {
    if (_isInitialized) return;
    await _tts.setLanguage('th-TH');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    // タイ語の音声一覧を取得
    final voices = await _tts.getVoices;
    if (voices != null) {
      _thaiVoices = (voices as List)
          .where((v) =>
              v['locale']?.toString().startsWith('th') == true)
          .map<Map<String, String>>(
              (v) => {'name': v['name'].toString(), 'locale': v['locale'].toString()})
          .toList();
    }

    _isInitialized = true;
  }

  Future<void> _pickRandomVoice() async {
    if (_thaiVoices.isEmpty) return;
    final voice = _thaiVoices[_random.nextInt(_thaiVoices.length)];
    await _tts.setVoice({'name': voice['name']!, 'locale': voice['locale']!});
  }

  Future<void> speak(String text, {bool slow = false}) async {
    await _init();
    await _pickRandomVoice();
    await _tts.setSpeechRate(slow ? 0.3 : 0.5);
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }

  void dispose() {
    _tts.stop();
  }
}
