// =============================================================================
// push_notification_service.dart
// 毎日例文のプッシュ通知（FCM）まわり。
//
// サーバー（deliverDailySentence）が配信対象を選ぶのに必要なフィールドを
// users/{uid} に書く役割を持つ:
//   fcm_token                 … 送信先。これが無いユーザーには配信されない
//   timezone                  … IANA名。ローカル時刻の判定に使う
//   preferred_generation_hour … 配信希望時刻（時のみ）
//   notify_utc_hour           … 上記2つから導く配信対象クエリ用の絞り込みキー
//
// 通知本文は例文そのものだが、表示はペイロードではなく Firestore から行う
// （DailySentenceService）。通知を開かなくても例文が手元に揃うようにするため。
// =============================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

/// 配信希望時刻のデフォルト（ユーザーのローカル10時）
const int kDefaultGenerationHour = 10;

/// タイムゾーンが取得できなかった場合のフォールバック
const String kFallbackTimezone = 'Asia/Tokyo';

/// 現地の [preferredHour] が UTC の何時の起動に当たるかを返す。
///
/// 配信バッチ（deliverDailySentence）は毎時起動し、users を
/// notify_utc_hour == 現在のUTC時 で絞り込む。全件走査を避けるための
/// 非正規化フィールドで、設定変更を即座に反映させるためクライアントでも書く。
/// （サーバー側は dailyBatch が毎日全ユーザー分を書き直す）
///
/// オフセットの引き算ではなく24通りを実際にローカル変換して探すため、
/// +5:30 / +5:45 のような分単位オフセットや DST でも正しい値になる。
/// その現地時刻が存在しない日（DST春の切り替え）は null を返す。
int? notifyUtcHour(int preferredHour, {DateTime? base}) {
  final now = (base ?? DateTime.now()).toUtc();
  for (var utcHour = 0; utcHour < 24; utcHour++) {
    final candidate = DateTime.utc(now.year, now.month, now.day, utcHour);
    if (candidate.toLocal().hour == preferredHour) return utcHour;
  }
  return null;
}

class PushNotificationService {
  PushNotificationService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  StreamSubscription<String>? _tokenRefreshSubscription;
  bool _registrationEnabled = false;

  DocumentReference<Map<String, dynamic>>? get _userDoc {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid);
  }

  /// アプリ起動時に呼ぶ。アプリ内設定とOSの許可状態を突き合わせて登録を整える。
  ///
  /// 未許可（notDetermined）で通知がオンなら、この時点で許可ダイアログを出す。
  /// OSの設定で後から通知を切られた場合はトークンを消す。
  ///
  /// 実際に通知を受け取れる状態かを返す。false のとき呼び出し側はアプリ内設定を
  /// オフに戻し、UIとOSの状態が食い違わないようにする。
  Future<bool> sync({required bool desiredEnabled}) async {
    _tokenRefreshSubscription ??= _messaging.onTokenRefresh.listen(_saveToken);

    try {
      if (!desiredEnabled) {
        await _disableRegistration(deleteDeviceToken: false);
        return false;
      }

      var settings = await _messaging.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        settings = await _messaging.requestPermission();
      }

      if (_isGranted(settings)) {
        await _enableRegistration();
        return true;
      }
      await _disableRegistration(deleteDeviceToken: false);
      return false;
    } catch (_) {
      // 通信・プラットフォーム側の失敗は次回起動で回復する。
      // ここで false を返すとユーザー設定を勝手にオフにしてしまうため維持する。
      return desiredEnabled;
    }
  }

  bool _isGranted(NotificationSettings settings) =>
      settings.authorizationStatus == AuthorizationStatus.authorized ||
      settings.authorizationStatus == AuthorizationStatus.provisional;

  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
  }

  /// 通知を有効にする。必要なら許可ダイアログを出す。
  ///
  /// 許可が得られたら true を返す。拒否された場合はトークンを登録しないため、
  /// 呼び出し側はトグルをオフに戻す必要がある。
  Future<bool> enable() async {
    try {
      final settings = await _messaging.requestPermission();
      if (!_isGranted(settings)) {
        await _disableRegistration(deleteDeviceToken: false);
        return false;
      }

      await _enableRegistration();
      await _resetNotifyBackoff();
      return true;
    } catch (_) {
      // 許可取得に失敗したまま古い登録が残ると、UIはオフなのに通知だけ届く。
      try {
        await _disableRegistration(deleteDeviceToken: false);
      } catch (_) {
        _registrationEnabled = false;
      }
      return false;
    }
  }

  /// 通知を無効にする。トークンを消すのでサーバー側の配信対象から外れる。
  Future<void> disable() async {
    try {
      await _disableRegistration(deleteDeviceToken: true);
    } catch (_) {
      // 失敗しても daily_reminder_enabled: false が書けていれば配信は止まる
    }
  }

  /// 配信希望時刻（時のみ）を保存する。
  Future<void> setPreferredHour(int hour) async {
    await _userDoc?.set(
      {
        'preferred_generation_hour': hour,
        'timezone': await _resolveTimezone(),
        // 算出できない日（DST春の飛び時刻）は書かず、既存値を残す。
        ...(() {
          final utcHour = notifyUtcHour(hour);
          return utcHour == null ? {} : {'notify_utc_hour': utcHour};
        }()),
      },
      SetOptions(merge: true),
    );
  }

  /// テーマ設定をサーバーへミラーする。
  ///
  /// テーマはローカルの SharedPreferences にしか無く配信バッチから見えないため、
  /// Premium ユーザーの毎日例文に設定を反映させる目的でこれだけ複製する。
  /// null（おまかせ）はフィールドごと消す。
  Future<void> setPreferredTopic(String? topic) async {
    try {
      await _userDoc?.set(
        {
          'preferred_topic': topic ?? FieldValue.delete(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // 反映は次回の設定変更・起動時に再試行される
    }
  }

  /// 通知トグルON＝再開の意思表示として、配信バックオフの段階を0に戻す。
  ///
  /// 停止段階（notify_tier == 4）まで進んだユーザーは自分で例文を生成しない限り
  /// 配信が再開されないため、トグル操作を解除の入口にする。
  /// ルール上クライアントは0へのリセットのみ書ける。
  Future<void> _resetNotifyBackoff() async {
    try {
      await _userDoc?.set(
        {'notify_tier': 0, 'notify_tier_misses': 0},
        SetOptions(merge: true),
      );
    } catch (_) {
      // 失敗しても通知の有効化自体は成立している。段階は次の反応シグナルで戻る
    }
  }

  Future<void> _enableRegistration() async {
    _registrationEnabled = true;
    // iOS はデフォルトだとフォアグラウンド中の通知を表示しない。配信は1日1回で
    // 見逃されると意味がないため、アプリを開いていても出るようにする。
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    final token = await _messaging.getToken();
    if (token != null) await _saveToken(token);
  }

  Future<void> _disableRegistration({required bool deleteDeviceToken}) async {
    _registrationEnabled = false;
    final doc = _userDoc;
    if (doc != null && await _isOwnRegistration(doc)) {
      await doc.update({
        'daily_reminder_enabled': false,
        'fcm_token': FieldValue.delete(),
      });
    }
    // 端末側のトークン破棄はサーバー登録の持ち主に関係なく行う。
    if (deleteDeviceToken) await _messaging.deleteToken();
  }

  /// サーバーに登録されているトークンが自端末のものか。
  ///
  /// fcm_token / daily_reminder_enabled は users/{uid} の単一フィールドで
  /// 端末間で共有される。通知オフの端末を起動しただけで別端末の配信が止まる
  /// のを避けるため、自分が登録した状態のときだけ書き換える。
  /// 判定できない場合は「他端末のもの」とみなして触らない。
  Future<bool> _isOwnRegistration(
    DocumentReference<Map<String, dynamic>> doc,
  ) async {
    try {
      final registered = (await doc.get()).data()?['fcm_token'] as String?;
      if (registered == null) return false;
      return registered == await _messaging.getToken();
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveToken(String token) async {
    if (!_registrationEnabled) return;
    // タイムゾーンはトークン更新のたびに書き直す。端末の移動・DST切り替えに追従させる。
    await _userDoc?.set(
      {
        'daily_reminder_enabled': true,
        'fcm_token': token,
        'timezone': await _resolveTimezone(),
      },
      SetOptions(merge: true),
    );
  }

  Future<String> _resolveTimezone() async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      return kFallbackTimezone;
    }
  }
}
