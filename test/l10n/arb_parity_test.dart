/// ja と en の ARB が同じキーを持つことを検証する。
///
/// 片方にしか無いキーがあると、その言語では `L10n` が ja へフォールバックし、
/// 英語UIの中に日本語が1文だけ混ざる。生成物を見ても気づきにくいのでここで止める。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Set<String> _messageKeys(String path) {
  final json = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return json.keys.where((k) => !k.startsWith('@')).toSet();
}

void main() {
  test('app_ja.arb と app_en.arb のキーが一致する', () {
    final ja = _messageKeys('lib/l10n/app_ja.arb');
    final en = _messageKeys('lib/l10n/app_en.arb');

    expect(ja.difference(en), isEmpty, reason: '英語訳が無いキー');
    expect(en.difference(ja), isEmpty, reason: '日本語側に無いキー');
  });

  test('空の文言が無い', () {
    for (final path in ['lib/l10n/app_ja.arb', 'lib/l10n/app_en.arb']) {
      final json =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      for (final entry in json.entries) {
        if (entry.key.startsWith('@')) continue;
        expect(
          (entry.value as String).trim(),
          isNotEmpty,
          reason: '$path の ${entry.key} が空',
        );
      }
    }
  });
}
