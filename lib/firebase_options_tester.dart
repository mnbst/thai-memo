// Firebase options for tester (thai-memo-67139)
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class TesterFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'TesterFirebaseOptions have not been configured for web.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'TesterFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDx77dgIGbYgvcLLR9jGLe_XYFPB48iB10',
    appId: '1:763566155520:ios:c538fb97e81d4f32beb5e5',
    messagingSenderId: '763566155520',
    projectId: 'thai-memo-67139',
    storageBucket: 'thai-memo-67139.firebasestorage.app',
    iosBundleId: 'com.thaimemo.thaiMemo',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCp582Rarddot3NqqBIZTzV_PwRD-8hFtY',
    appId: '1:763566155520:android:34165e13f45eb11bbeb5e5',
    messagingSenderId: '763566155520',
    projectId: 'thai-memo-67139',
    storageBucket: 'thai-memo-67139.firebasestorage.app',
  );
}
