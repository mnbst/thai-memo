import 'dart:async';
import 'dart:io';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/config/app_config.dart';

class AdMobService {
  static final AdMobService instance = AdMobService._internal();
  factory AdMobService() => instance;
  AdMobService._internal();

  static String get bannerAdUnitId {
    if (AppConfig.isProd) {
      // TODO: 本番AdMobバナー広告ユニットIDに差し替え
      if (Platform.isAndroid) {
        return 'ca-app-pub-XXXXXXXXXX/XXXXXXXXXX'; // Android本番ID
      } else {
        return 'ca-app-pub-XXXXXXXXXX/XXXXXXXXXX'; // iOS本番ID
      }
    }
    // テスト用ID（dev/tester環境）
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/6300978111';
    } else {
      return 'ca-app-pub-3940256099942544/2934735716';
    }
  }

  BannerAd? _bannerAd;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    await MobileAds.instance.initialize();
    _initialized = true;
  }

  BannerAd createBannerAd() {
    unawaited(initialize());
    return BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    )..load();
  }

  void dispose() {
    _bannerAd?.dispose();
  }
}
