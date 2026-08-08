/// アプリ言語の初期値決定のテスト。
///
/// 判定軸はダウンロード元のストア地域だけで、端末ロケールは使わない。
/// 既定は ja で、日本以外のストアだと確認できたときにだけ en へ倒す。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/l10n/app_language.dart';
import 'package:thai_memo/services/storefront_service.dart';

void main() {
  group('AppLanguage.fromStorefront', () {
    test('iOS の Alpha-3（JPN）は ja', () {
      expect(AppLanguage.fromStorefront('JPN'), AppLanguage.ja);
    });

    test('Android の Alpha-2（JP）は ja', () {
      expect(AppLanguage.fromStorefront('JP'), AppLanguage.ja);
    });

    test('小文字・空白混じりでも正規化して ja', () {
      expect(AppLanguage.fromStorefront(' jp '), AppLanguage.ja);
    });

    test('日本以外のストアは en', () {
      expect(AppLanguage.fromStorefront('USA'), AppLanguage.en);
      expect(AppLanguage.fromStorefront('TH'), AppLanguage.en);
    });

    test('取得失敗（null・空文字）は既定の ja に留まる', () {
      // 取得できないだけで en に倒すと、ストア接続に失敗した日本のユーザーが
      // 英語で起動してしまう。確証が無いときは現行の挙動を変えない。
      expect(AppLanguage.fromStorefront(null), AppLanguage.ja);
      expect(AppLanguage.fromStorefront(''), AppLanguage.ja);
    });
  });

  group('AppLanguage.fromCode', () {
    test('保存済みの値を復元する', () {
      expect(AppLanguage.fromCode('en'), AppLanguage.en);
      expect(AppLanguage.fromCode('ja'), AppLanguage.ja);
    });

    test('未知・null は ja', () {
      expect(AppLanguage.fromCode('fr'), AppLanguage.ja);
      expect(AppLanguage.fromCode(null), AppLanguage.ja);
    });
  });

  group('StorefrontService', () {
    test('取得できた地域をそのまま返す', () async {
      final service = StorefrontService(lookup: () async => 'JPN');
      expect(await service.countryCode(), 'JPN');
    });

    test('空文字は null 扱い', () async {
      final service = StorefrontService(lookup: () async => '');
      expect(await service.countryCode(), isNull);
    });

    test('例外は null に落として起動を止めない', () async {
      final service = StorefrontService(lookup: () async => throw 'no store');
      expect(await service.countryCode(), isNull);
    });

    test('応答が返らなければタイムアウトで打ち切る', () async {
      final service = StorefrontService(
        lookup: () => Completer<String>().future,
        timeout: const Duration(milliseconds: 10),
      );
      expect(await service.countryCode(), isNull);
    });
  });
}
