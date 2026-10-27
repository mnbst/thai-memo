import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/pronunciation/pass_tier.dart';

void main() {
  group('passTierOf', () {
    test('画面の点数（四捨五入）で段を決める', () {
      expect(passTierOf(79.4), PassTier.none);
      expect(passTierOf(79.5), PassTier.pass);
      expect(passTierOf(89.4), PassTier.pass);
      expect(passTierOf(89.5), PassTier.native);
      expect(passTierOf(100), PassTier.native);
    });
  });
}
