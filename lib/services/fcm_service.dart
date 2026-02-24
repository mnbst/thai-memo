import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// バックグラウンドFCMハンドラ（トップレベル関数）
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final data = message.data;
  if (data['type'] != 'quiz') return;

  final questions = data['questions'];
  if (questions == null || (questions as String).isEmpty) return;

  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('quiz_questions', questions);
  // 前回の完了フラグをクリア（洗い替え）
  await prefs.remove('quiz_completed');
  await prefs.remove('quiz_answers');

  if (data['quiz_queue_id'] != null) {
    await prefs.setString('quiz_queue_id', data['quiz_queue_id']);
  }
}

class FcmService {
  static final FcmService instance = FcmService._internal();

  factory FcmService() => instance;

  FcmService._internal();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// 通知タップ時にクイズタブへ切り替えるコールバック
  VoidCallback? onQuizDataReceived;

  /// FCM初期化: 権限リクエスト + トークン保存 + ローカル通知セットアップ
  Future<void> initialize() async {
    // 通知権限をリクエスト
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // iOSフォアグラウンド通知表示設定
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // ローカル通知の初期化（フォアグラウンド表示用）
    await _initLocalNotifications();

    // トークンリフレッシュ時の自動更新（APNSが後から準備できた場合もここで保存される）
    _messaging.onTokenRefresh.listen((token) {
      _saveToken(token);
    });

    // トークン取得・保存（iOS: APNSが未準備なら例外になるのでcatchして待つ）
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _saveToken(token);
      }
    } catch (_) {}
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _localNotifications.initialize(settings);

    // Android通知チャンネル作成
    const channel = AndroidNotificationChannel(
      'review_notifications',
      'クイズ通知',
      description: 'クイズのリマインダー通知',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// 通知タップハンドラのセットアップ
  void setupNotificationHandlers() {
    // バックグラウンドから復帰時
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotificationTap(message);
    });

    // 終了状態から起動時
    _messaging.getInitialMessage().then((message) {
      if (message != null) {
        _handleNotificationTap(message);
      }
    });

    // フォアグラウンドでメッセージ受信時: バナー表示 + データ保存
    FirebaseMessaging.onMessage.listen((message) {
      _showForegroundNotification(message);
      _saveQuizData(message).then((_) {
        if (message.data['type'] == 'quiz') {
          onQuizDataReceived?.call();
        }
      });
    });
  }

  /// フォアグラウンド時にローカル通知でバナー表示
  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      'review_notifications',
      'クイズ通知',
      channelDescription: 'クイズのリマインダー通知',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      details,
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    _saveQuizData(message);
    onQuizDataReceived?.call();
  }

  Future<void> _saveQuizData(RemoteMessage message) =>
      firebaseMessagingBackgroundHandler(message);

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
