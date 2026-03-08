import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/datasources/backend_api_service.dart';
import '../data/models/thai_sentence.dart';
import '../presentation/providers/sentence_provider.dart';

/// バックグラウンドFCMハンドラ（トップレベル関数）
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final data = message.data;
  final type = data['type'];

  if (type == 'daily_sentence') {
    final sentenceJson = data['sentence_json'];
    if (sentenceJson != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('daily_sentence', sentenceJson);
    }
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

  /// 通知タップ時に例文タブへ切り替えるコールバック
  VoidCallback? onSentenceTabRequested;

  /// Riverpodコンテナ（通知から例文をstateに反映するため）
  ProviderContainer? _container;

  /// 終了状態から起動時に遷移待ちの例文を保持
  ThaiSentence? _pendingDailySentence;

  /// main.dartからProviderContainerを設定
  void setContainer(ProviderContainer container) {
    _container = container;
  }

  /// FCM初期化: 権限リクエスト + トークン保存 + ローカル通知セットアップ
  Future<void> initialize() async {
    // 通知権限をリクエスト
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // iOS: フォアグラウンドではローカル通知で表示するため、
    // システム通知を無効化して二重表示を防止
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
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
      settings: settings,
      onDidReceiveNotificationResponse: (_) {
        // ローカル通知タップ時: SharedPreferencesから例文データを復元して遷移
        _handleLocalNotificationTap();
      },
    );

    // Android通知チャンネル作成
    const dailyChannel = AndroidNotificationChannel(
      'daily_sentence',
      '今日のタイ語',
      description: '毎日のタイ語例文通知',
      importance: Importance.high,
    );
    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
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
      _saveDailySentenceData(message.data);
      _showForegroundNotification(message);
    });
  }

  /// フォアグラウンド時にローカル通知でバナー表示
  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      'daily_sentence',
      '今日のタイ語',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _localNotifications.show(
      id: notification.hashCode & 0x7FFFFFFF,
      title: notification.title,
      body: notification.body,
      notificationDetails: details,
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    _saveDailySentenceData(message.data);
    _navigateToDailySentence(message.data);
  }

  /// ローカル通知タップ時の処理
  Future<void> _handleLocalNotificationTap() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('daily_sentence');
    if (json == null) return;
    final sentence = _parseSentenceJson(json);
    if (sentence != null) {
      _navigateToSentenceTab(sentence);
    }
  }

  void _saveDailySentenceData(Map<String, dynamic> data) async {
    final sentenceJson = data['sentence_json'];
    if (sentenceJson == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('daily_sentence', sentenceJson as String);
  }

  void _navigateToDailySentence(Map<String, dynamic> data) {
    final sentenceJson = data['sentence_json'] as String?;
    if (sentenceJson == null) return;
    final sentence = _parseSentenceJson(sentenceJson);
    if (sentence != null) {
      _navigateToSentenceTab(sentence);
    }
  }

  /// 例文タブのstateに反映し、ホーム画面の例文タブへ遷移
  void _navigateToSentenceTab(ThaiSentence sentence) {
    // 例文タブのstateに反映
    _container
        ?.read(sentenceControllerProvider.notifier)
        .showSentence(sentence);

    final navigator = navigatorKey.currentState;
    if (navigator != null) {
      // DetailScreenなどが開いていればホームまで戻る
      navigator.popUntil((route) => route.isFirst);
      onSentenceTabRequested?.call();
    } else {
      // アプリ起動直後でnavigatorがまだ準備できていない場合、保留
      _pendingDailySentence = sentence;
    }
  }

  /// HomeScreenが準備完了時に呼ぶ。保留中の遷移があれば実行する。
  void markHomeReady() {
    if (_pendingDailySentence != null) {
      final sentence = _pendingDailySentence!;
      _pendingDailySentence = null;
      // 少し遅延してnavigatorが確実に有効になるのを待つ
      Future.delayed(const Duration(milliseconds: 300), () {
        _navigateToSentenceTab(sentence);
      });
    }
  }

  /// sentence_json文字列からThaiSentenceを生成
  ThaiSentence? _parseSentenceJson(String jsonStr) {
    try {
      final map = Map<String, dynamic>.from(jsonDecode(jsonStr) as Map);
      return BackendApiService.createThaiSentenceFromJson(map);
    } catch (e) {
      debugPrint('Failed to parse sentence_json: $e');
      return null;
    }
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
