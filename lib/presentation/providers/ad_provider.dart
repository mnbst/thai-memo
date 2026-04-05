import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../services/admob_service.dart';
import 'subscription_provider.dart';

/// バナー広告プロバイダ（プレミアムユーザーにはnull）
final bannerAdProvider = Provider<BannerAd?>((ref) {
  final isPremium = ref.watch(isPremiumProvider);
  if (isPremium) return null;

  final ad = AdMobService.instance.createBannerAd();
  ref.onDispose(() => ad.dispose());
  return ad;
});
