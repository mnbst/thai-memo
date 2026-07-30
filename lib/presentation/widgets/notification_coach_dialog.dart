import 'package:flutter/material.dart';

/// 毎日例文通知を「継続をサポートする機能」として紹介するコーチングダイアログ。
///
/// このダイアログでは通知をオンにしない。「通知を設定」を選ぶと呼び出し側が
/// 設定画面へ移動し、実際に操作するトグルをコーチマークで示す。OSの許可要求は
/// ユーザーがそのトグルを自分で操作したときに初めて出る。iOSの許可ダイアログは
/// 一度拒否されるとアプリからは二度と出せないため、何のための通知かを伝え、
/// かつ本人の操作を挟んでから聞く。
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
      title: const Text('例文を毎日の習慣に'),
      titlePadding: const EdgeInsets.symmetric(horizontal: 24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('あなたの語彙に合う例文を、毎日お届けします。'),
          const SizedBox(height: 8),
          Text(
            '通知時刻は設定画面で変更できます。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      actionsPadding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('あとで'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('通知を設定'),
        ),
      ],
    );
  }
}

/// コーチングダイアログを表示し、設定画面へ案内してよいかを返す。
///
/// バリアタップなど明示的な選択なしで閉じた場合は false（案内しない）。
Future<bool> showNotificationCoachDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => const NotificationCoachDialog(),
  );
  return result ?? false;
}

/// コーチングダイアログを出すべきか。
///
/// [permissionGranted] はOSの通知許可状態。既に許可済みなら紹介する必要がない。
/// アプリ内設定 `dailyReminderEnabled` は既定オンで、OSが未許可でも
/// syncPushRegistration がオフに倒すまで true のままなので判定には使わない。
bool shouldShowNotificationCoach({
  required bool coachShown,
  required bool permissionGranted,
}) {
  if (coachShown) return false;
  return !permissionGranted;
}
