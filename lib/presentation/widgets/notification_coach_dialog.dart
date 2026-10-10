import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../services/push_notification_service.dart';
import '../providers/analytics_provider.dart';
import '../providers/settings_provider.dart';

/// 毎日例文通知を「継続をサポートする機能」として紹介するコーチングダイアログ。
///
/// 「通知をオンにする」を押した時点で呼び出し側がOSの許可要求を出す。以前は
/// 設定画面のトグルまで自分で辿らせていたが、承諾した人がトグルに到達せず
/// トークン登録まで届いていなかった（2026-08時点でアクティブの23%しか登録なし）。
/// iOSの許可ダイアログは一度拒否されると二度と出せないため、何のための通知かを
/// このダイアログで伝えてから聞く、という順序自体は変えない。
class NotificationCoachDialog extends StatelessWidget {
  const NotificationCoachDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(
        Icons.notifications_none_rounded,
        color: Theme.of(context).colorScheme.primary,
        size: 32,
      ),
      iconPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      title: Text(L10n.of(context).notifCoachTitle),
      titlePadding: const EdgeInsets.symmetric(horizontal: 24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 何が届くかはタイトルと見本で伝わるので、本文は続けやすい理由の1行だけ。
          Text(
            L10n.of(context).notifCoachHabit,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          const _NotificationPreview(),
        ],
      ),
      // 端末の文字サイズを大きくしている場合でも溢れないようにする。
      scrollable: true,
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      actionsPadding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(L10n.of(context).notifCoachEnable),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(L10n.of(context).notifCoachLater),
        ),
      ],
    );
  }
}

/// 実際に届く通知の見本。
///
/// 文面は Cloud Functions の `build_notification_text`（タイトルに
/// キーワードと意味、本文は タイ文 /（発音）/ → 訳 の3行）と揃えている。
/// OSごとに実物の見た目は違うため、スクリーンショットではなくアプリのテーマで
/// 描いて「何が書かれた通知か」だけを伝える。
class _NotificationPreview extends StatelessWidget {
  const _NotificationPreview();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 読ませる要素ではなく「こういう見た目のものが届く」という印象だけを伝える。
    // 読ませはしないが印象は残す大きさとして、通知本体は12pt相当にする。
    // タイ文字は声調記号が上下に付くため、行高は詰めすぎない。
    final line =
        theme.textTheme.labelSmall?.copyWith(fontSize: 12, height: 1.35);
    final subdued = line?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Image.asset(
                  'assets/appicon.png',
                  width: 14,
                  height: 14,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(L10n.of(context).appTitle, style: subdued)),
              Text(L10n.of(context).notifCoachNow, style: subdued),
            ],
          ),
          const SizedBox(height: 3),
          // 実物の通知も折り返さず省略されるので、見本も1行ずつに収める。
          Text(
            L10n.of(context).notifCoachSampleTitle,
            style: line?.copyWith(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            'ขอบคุณสำหรับกาแฟนะครับ',
            style: line,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '（khop khun samrap kafae na khrap）',
            style: subdued,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            L10n.of(context).notifCoachSampleBody,
            style: line,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// コーチングダイアログを表示し、通知をオンにしてよいかを返す。
///
/// バリアタップなど明示的な選択なしで閉じた場合は false（許可要求を出さない）。
Future<bool> showNotificationCoachDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => const NotificationCoachDialog(),
  );
  return result ?? false;
}

/// コーチングダイアログを出すべきか。
///
/// [permissionGranted] はバナー・音つきの配信が許可されているかで、null は
/// 判定不能（取得失敗）。既に許可済みなら紹介する必要がなく、判定不能なら
/// 出さずに次の機会へ回す。
/// アプリ内設定 `dailyReminderEnabled` は既定オンで、OSが未許可でも
/// syncPushRegistration がオフに倒すまで true のままなので判定には使わない。
///
/// 一度出した人には、[repromptVersion]（このリリースの再案内の印）が
/// [repromptedVersion]（端末に記録した印）と違うときだけもう一度出す。
/// OSの許可を一度も求めていない（[canRequestPermission] が true）人に限る。
/// 拒否済みの人に出しても iOS は許可ダイアログを出せない。
bool shouldShowNotificationCoach({
  required bool coachShown,
  required bool? permissionGranted,
  bool? canRequestPermission,
  String? repromptVersion,
  String? repromptedVersion,
}) {
  if (permissionGranted != false) return false;
  if (!coachShown) return true;
  return canRequestPermission == true &&
      repromptVersion != null &&
      repromptVersion != repromptedVersion;
}

/// 通知の再案内A/Bの群。
enum NotificationRepromptArm {
  /// 再案内を出す群
  show,

  /// 再案内を出さない群（比較対照）
  holdout,
}

/// 再案内A/Bの実験ID。リリースの印ごとに別の実験として扱う。
String notificationRepromptExperimentId(String version) =>
    'notif_reprompt_$version';

/// uid と実験IDから群を決める。
///
/// 端末の乱数ではなく uid のハッシュで決めるので、再インストールしても群が
/// 変わらず、分析側（scripts/notif_reprompt_experiment.py）でも同じ計算で
/// 再現できる。ハッシュは FNV-1a 32bit（UTF-8 バイト列）。
NotificationRepromptArm assignNotificationRepromptArm(
  String uid,
  String experimentId,
) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode('$uid:$experimentId')) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.isEven
      ? NotificationRepromptArm.show
      : NotificationRepromptArm.holdout;
}

/// まとめクイズを終えたときに、毎日例文通知を継続サポート機能として
/// 紹介する。出したら true。
///
/// 体験する前に出すと通知そのものを断られやすい（iOSでは一度拒否されると
/// 二度と要求できない）ため、インストール直後には出さない。設定タブを開いた
/// ときに出していた期間（2026-08-24〜）は承諾率が12%で、まとめクイズ完了時に
/// 出していた期間（45%）より大きく下がったため、ここへ戻した。
/// 「通知をオンにする」を押したらその場でOSの許可要求まで出す。
/// 断った人への再案内はリリースごとに [AppConfig.notificationCoachRepromptVersion] で決める。
Future<bool> maybeShowNotificationCoach(
  BuildContext context,
  WidgetRef ref,
) async {
  final controller = ref.read(settingsControllerProvider.notifier);
  // 初期化前の state は「表示済み」側の既定値なので、読む前に必ず待つ。
  await controller.initialized;
  if (!context.mounted) return false;

  final settings = ref.read(settingsControllerProvider);
  final coachShown = settings.notificationCoachShown;
  const repromptVersion = AppConfig.notificationCoachRepromptVersion;
  final permissionGranted =
      await controller.hasProminentNotificationPermission();
  // 再案内の候補になるときだけ OS の状態を聞く。
  final canRequest = coachShown &&
          permissionGranted == false &&
          repromptVersion != null &&
          repromptVersion != settings.notificationCoachRepromptedVersion
      ? await controller.canRequestNotificationPermission()
      : null;
  if (!shouldShowNotificationCoach(
    coachShown: coachShown,
    permissionGranted: permissionGranted,
    canRequestPermission: canRequest,
    repromptVersion: repromptVersion,
    repromptedVersion: settings.notificationCoachRepromptedVersion,
  )) {
    // 許可済みだと確認できたときだけ、紹介不要として記録する。判定不能（null）
    // で記録すると、一度の取得失敗でそのユーザーが恒久的に案内対象から外れる。
    if (!coachShown && permissionGranted == true) {
      await controller.markNotificationCoachShown();
    }
    return false;
  }
  // 前面に別の画面がある間は出さない。ここで出さなくても表示済みフラグは
  // 立たないため、次のまとめクイズで出し直される。
  if (!context.mounted || ModalRoute.of(context)?.isCurrent != true) {
    return false;
  }

  final analytics = ref.read(analyticsServiceProvider);
  final source = coachShown ? 'reprompt' : 'first';

  // 再案内は半分の人にだけ出し、出さない群と継続率を比べる（A/B）。
  // 出さない群も対象になった時点で記録し、同じリリースでは判定し直さない。
  if (coachShown && repromptVersion != null) {
    final uid = controller.currentUid;
    // uid が無いと群を再現できないので、実験に入れず今回は見送る。
    if (uid == null) return false;
    final experimentId = notificationRepromptExperimentId(repromptVersion);
    final arm = assignNotificationRepromptArm(uid, experimentId);
    unawaited(
      controller.recordNotificationRepromptExperiment(
        experimentId: experimentId,
        arm: arm.name,
      ),
    );
    if (arm == NotificationRepromptArm.holdout) {
      unawaited(
        analytics.logNotificationCoach(action: 'holdout', source: source),
      );
      await controller.markNotificationCoachReprompted(repromptVersion);
      return false;
    }
  }
  unawaited(analytics.logNotificationCoach(action: 'shown', source: source));

  final accepted = await showNotificationCoachDialog(context);
  unawaited(
    analytics.logNotificationCoach(
      action: accepted ? 'accepted' : 'dismissed',
      source: source,
    ),
  );
  // 出したら結果に関わらず記録する。初回もこのリリースの再案内を済ませた
  // 扱いにし、断った直後に同じリリースの再案内が続かないようにする。
  await controller.markNotificationCoachShown();
  if (repromptVersion != null) {
    await controller.markNotificationCoachReprompted(repromptVersion);
  }
  if (!accepted || !context.mounted) return true;

  // ここでOSの許可ダイアログが出る。答えるまで下の await は返らないため、
  // 要求に入ったこと自体を先に記録する。これが無いと「ダイアログを放置して
  // アプリを離れた」と「許可後の登録が終わらなかった」を後から区別できない。
  unawaited(
      analytics.logNotificationCoach(action: 'requesting', source: source));
  final result = await controller.setDailyReminderEnabled(true);
  unawaited(
    analytics.logNotificationCoach(
        action: result?.name ?? 'denied', source: source),
  );
  if (!context.mounted) return true;
  // pending は許可が取れているので、登録待ちでも成功として伝える。
  // quiet（昇格を断られた）は「届きます」と言うと嘘になるので分ける。
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(switch (result) {
        PushEnableResult.denied =>
          L10n.of(context).settingsAllowNotificationInOsSettings,
        PushEnableResult.quiet => L10n.of(context).notifCoachStillQuiet,
        _ => L10n.of(context).notifCoachEnabled,
      }),
    ),
  );
  return true;
}
