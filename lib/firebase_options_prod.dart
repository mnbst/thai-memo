// Firebase options for production (thai-memo-prod)
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class ProdFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'ProdFirebaseOptions have not been configured for web.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'ProdFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCqngU7iG8P3rS9fdVcCuqPbKDDHBVMtG4',
    appId: '1:219961294368:ios:88e70ed652a72f10b70645',
    messagingSenderId: '219961294368',
    projectId: 'thai-memo-prod',
    storageBucket: 'thai-memo-prod.firebasestorage.app',
    iosBundleId: 'com.thaimemo.thaiMemo',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCbrpdDsWeuOVAD9vk3hTPvQA0nCvSNcR0',
    appId: '1:219961294368:android:e0e4885ac250ce66b70645',
    messagingSenderId: '219961294368',
    projectId: 'thai-memo-prod',
    storageBucket: 'thai-memo-prod.firebasestorage.app',
  );
}
