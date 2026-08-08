import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// ダウンロード元のストア地域を取得する。初回起動時の言語決定にだけ使う。
///
/// 厳密には「現在のストアアカウントの地域」だが、初回起動時に1回しか読まないので
/// 実質ダウンロード時点の地域と一致する。
class StorefrontService {
  StorefrontService({
    Future<String> Function()? lookup,
    this.timeout = _defaultTimeout,
  }) : _lookup = lookup ?? InAppPurchase.instance.countryCode;

  static const Duration _defaultTimeout = Duration(seconds: 3);

  final Future<String> Function() _lookup;

  /// ストア接続を伴うため初回描画をブロックしないよう必ず打ち切る。
  final Duration timeout;

  /// iOS は Alpha-3（`JPN`）、Android は Alpha-2（`JP`）を返す。
  /// 取得できなければ null（呼び出し側は既定の ja のままにする）。
  Future<String?> countryCode() async {
    try {
      final code = await _lookup().timeout(timeout);
      return code.isEmpty ? null : code;
    } catch (e) {
      debugPrint('storefront lookup failed: $e');
      return null;
    }
  }
}
