import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

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
            // 「時刻を決める→そこに届く→同じ時間に開くから続く」の順で並べる。
            // 時刻設定の理由と習慣化の理屈が、読まなくても順番で伝わるようにする。
            _Step(number: 1, text: L10n.of(context).notifCoachStep1),
            const SizedBox(height: 6),
            _Step(number: 2, text: L10n.of(context).notifCoachStep2),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    L10n.of(context).notifCoachHabit,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 10),
          Text(
            L10n.of(context).notifCoachPreviewLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 2),
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

/// 手順を1行で示す行。番号を付けて順序（時刻を決める→届く）を読ませる。
class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(top: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
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
bool shouldShowNotificationCoach({
  required bool coachShown,
  required bool? permissionGranted,
}) {
  if (coachShown) return false;
  return permissionGranted == false;
}
