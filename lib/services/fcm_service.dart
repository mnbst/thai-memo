import 'dart:convert';

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
  final type = data['type'];

  if (type == 'daily_sentence') {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('daily_sentence', jsonEncode({
      'thai_text': data['thai_text'] ?? '',
      'pronunciation': data['pronunciation'] ?? '',
      'japanese_translation': data['japanese_translation'] ?? '',
    }));
    return;
  }

  if (type != 'quiz' && type != 'review') return;

  final prefs = await SharedPreferences.getInstance();
  if (type == 'review' && data['question_count'] != null) {
    await prefs.setInt(
        'review_question_count', int.tryParse(data['question_count'] ?? '0') ?? 0);
  } else if (data['quiz_queue_id'] != null) {
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

  /// 通知タップ時に例文詳細画面へ遷移するコールバック
  void Function(Map<String, String> sentenceData)? onDailySentenceReceived;

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

    // トークンリフレッシュ時の自動更新
    _messaging.onTokenRefresh.listen((token) {
      _saveToken(token);
    });

    // FCMトークン取得・保存
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _saveToken(token);
      }
    } catch (e) {
      debugPrint('FCMトークン取得失敗: $e');
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (_) {
        // ローカル通知タップ時: SharedPreferencesから例文データを復元して遷移
        _handleLocalNotificationTap();
      },
    );

    // Android通知チャンネル作成
    const reviewChannel = AndroidNotificationChannel(
      'review_notifications',
      'クイズ通知',
      description: 'クイズのリマインダー通知',
      importance: Importance.high,
    );
    const dailyChannel = AndroidNotificationChannel(
      'daily_sentence',
      '今日のタイ語',
      description: '毎日のタイ語例文通知',
      importance: Importance.high,
    );
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(reviewChannel);
    await androidPlugin?.createNotificationChannel(dailyChannel);
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

    // フォアグラウンドでメッセージ受信時: バナー表示
    FirebaseMessaging.onMessage.listen((message) {
      final type = message.data['type'];
      if (type == 'daily_sentence') {
        _saveDailySentenceData(message.data);
        _showForegroundNotification(message, channelId: 'daily_sentence', channelName: '今日のタイ語');
      } else {
        _showForegroundNotification(message);
        _saveQuizData(message).then((_) {
          if (type == 'quiz' || type == 'review') {
            onQuizDataReceived?.call();
          }
        });
      }
    });
  }

  /// フォアグラウンド時にローカル通知でバナー表示
  Future<void> _showForegroundNotification(
    RemoteMessage message, {
    String channelId = 'review_notifications',
    String channelName = 'クイズ通知',
  }) async {
    final notification = message.notification;
    if (notification == null) return;

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.high,
      priority: Priority.high,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(),
    );

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      details,
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    final type = message.data['type'];
    if (type == 'daily_sentence') {
      _saveDailySentenceData(message.data);
      _navigateToDailySentence(message.data);
    } else {
      _saveQuizData(message);
      onQuizDataReceived?.call();
    }
  }

  /// ローカル通知タップ時の処理
  Future<void> _handleLocalNotificationTap() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('daily_sentence');
    if (json != null) {
      final data = Map<String, String>.from(jsonDecode(json) as Map);
      onDailySentenceReceived?.call(data);
    } else {
      onQuizDataReceived?.call();
    }
  }

  void _saveDailySentenceData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('daily_sentence', jsonEncode({
      'thai_text': data['thai_text'] ?? '',
      'pronunciation': data['pronunciation'] ?? '',
      'japanese_translation': data['japanese_translation'] ?? '',
    }));
  }

  void _navigateToDailySentence(Map<String, dynamic> data) {
    onDailySentenceReceived?.call({
      'thai_text': data['thai_text']?.toString() ?? '',
      'pronunciation': data['pronunciation']?.toString() ?? '',
      'japanese_translation': data['japanese_translation']?.toString() ?? '',
    });
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
