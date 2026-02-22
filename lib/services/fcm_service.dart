import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../presentation/providers/review_provider.dart';

class FcmService {
  static final FcmService instance = FcmService._internal();

  factory FcmService() => instance;

  FcmService._internal();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 通知タップ時に復習タブへ切り替えるコールバック
  VoidCallback? onReviewDataReceived;

  /// FCM初期化: 権限リクエスト + トークン保存
  Future<void> initialize() async {
    // 通知権限をリクエスト
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // トークン取得・保存
    final token = await _messaging.getToken();
    if (token != null) {
      await _saveToken(token);
    }

    // トークンリフレッシュ時の自動更新
    _messaging.onTokenRefresh.listen(_saveToken);
  }

  /// 通知タップハンドラのセットアップ
  void setupNotificationHandlers(ReviewNotifier reviewNotifier) {
    // バックグラウンドから復帰時
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotificationTap(message, reviewNotifier);
    });

    // 終了状態から起動時
    _messaging.getInitialMessage().then((message) {
      if (message != null) {
        _handleNotificationTap(message, reviewNotifier);
      }
    });

    // フォアグラウンドでデータ受信時も保存
    FirebaseMessaging.onMessage.listen((message) {
      _saveReviewData(message, reviewNotifier);
    });
  }

  void _handleNotificationTap(
      RemoteMessage message, ReviewNotifier reviewNotifier) {
    _saveReviewData(message, reviewNotifier);
    onReviewDataReceived?.call();
  }

  void _saveReviewData(
      RemoteMessage message, ReviewNotifier reviewNotifier) {
    final data = message.data;
    if (data['type'] != 'review') return;

    final thaiText = data['thai_text'] ?? '';
    if (thaiText.isEmpty) return;

    reviewNotifier.save(ReviewData(
      thaiText: thaiText,
      pronunciation: data['pronunciation'] ?? '',
      japaneseTranslation: data['japanese_translation'] ?? '',
      reviewNotes: data['review_notes'] ?? '',
    ));
  }

  Future<void> _saveToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _firestore.collection('users').doc(user.uid).set({
      'fcm_token': token,
      'notification_enabled': true,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 通知ON/OFF切り替え
  Future<void> setNotificationEnabled(bool enabled) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _firestore.collection('users').doc(user.uid).set({
      'notification_enabled': enabled,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
