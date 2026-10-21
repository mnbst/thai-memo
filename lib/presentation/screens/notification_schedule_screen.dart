// =============================================================================
// notification_schedule_screen.dart
// 毎日例文の通知時刻（iPhone のアラーム風）。
//
// 枠は固定で、トグルだけでオン・オフする。行をタップすると時刻を変える。
// free は1枠＋プレミアム案内、premium は3枠＋例文セットの入れ替えの注意書き。
// 通知そのもののオン・オフ（OSの許可・トークン登録）は dailyReminderEnabled が
// 受け持つ。オンの枠が無くなるときと、オフから1つ目をオンにするときだけそちらを
// 切り替える。
// =============================================================================

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notify_slots.dart';
import '../../l10n/app_localizations.dart';
import '../../services/push_notification_service.dart';
import '../providers/remaining_quota_provider.dart';
import '../providers/settings_provider.dart';
import 'paywall_screen.dart';

class NotificationScheduleScreen extends ConsumerStatefulWidget {
  const NotificationScheduleScreen({super.key});

  static const routeName = 'notification_schedule';

  @override
  ConsumerState<NotificationScheduleScreen> createState() =>
      _NotificationScheduleScreenState();
}

class _NotificationScheduleScreenState
    extends ConsumerState<NotificationScheduleScreen> {
  SettingsController get _controller =>
      ref.read(settingsControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    // プランが変わっていたら枠を作り直してから見せる。
    Future.microtask(
      () => _controller.syncNotifySlotsPlan(
        premium: ref.read(effectivePremiumProvider),
      ),
    );
  }

  Future<void> _toggle(List<NotifySlot> slots, int index, bool on) async {
    // 許可ダイアログやトークン登録を待つ間に画面が閉じられることがある。
    // 閉じたあとに ref を読むと例外になるので、先に取っておく。
    final controller = _controller;
    final reminderOn = ref.read(dailyReminderEnabledProvider);
    if (on) {
      if (!reminderOn) {
        final result = await controller.setDailyReminderEnabled(true);
        if (result == PushEnableResult.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  L10n.of(context).settingsAllowNotificationInOsSettings,
                ),
              ),
            );
          }
          return;
        }
        // 通知がオフの間は全部オフに見えているので、押した1つだけをオンにする。
        await controller.setNotifySlots([
          for (var i = 0; i < slots.length; i++)
            slots[i].copyWith(enabled: i == index),
        ]);
        return;
      }
      await controller.setNotifySlots([
        for (var i = 0; i < slots.length; i++)
          i == index ? slots[i].copyWith(enabled: true) : slots[i],
      ]);
      return;
    }

    final othersOn =
        reminderOn && slots.indexed.any((e) => e.$1 != index && e.$2.enabled);
    if (!othersOn) {
      // 最後の1つ。枠の印は残し、通知そのものを止める（次にオンにすれば戻る）。
      await controller.setDailyReminderEnabled(false);
      return;
    }
    await controller.setNotifySlots([
      for (var i = 0; i < slots.length; i++)
        i == index ? slots[i].copyWith(enabled: false) : slots[i],
    ]);
  }

  Future<void> _changeHour(List<NotifySlot> slots, int index) async {
    final taken = {
      for (var i = 0; i < slots.length; i++)
        if (i != index) slots[i].hour,
    };
    final controller = _controller;
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (_) => _HourSheet(initial: slots[index].hour, taken: taken),
    );
    if (picked == null || picked == slots[index].hour) return;
    await controller.setNotifySlots([
      for (var i = 0; i < slots.length; i++)
        i == index ? slots[i].copyWith(hour: picked) : slots[i],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final premium = ref.watch(effectivePremiumProvider);
    final reminderOn = ref.watch(dailyReminderEnabledProvider);
    final slots = ref.watch(notifySlotsProvider);

    // 開いている間にプランが変わったときも作り直す。
    ref.listen<bool>(effectivePremiumProvider, (_, next) {
      _controller.syncNotifySlotsPlan(premium: next);
    });

    // 作り直す前の一瞬に枠の数がプランと合わないことがあるので、表示で絞る。
    final shown = premium ? slots : slots.take(1).toList();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsDailyNotification)),
      body: ListView(
        children: [
          for (var i = 0; i < shown.length; i++)
            _SlotRow(
              slot: shown[i],
              on: reminderOn && shown[i].enabled,
              onTap: () => _changeHour(shown, i),
              onChanged: (v) => _toggle(shown, i, v),
            ),
          if (premium)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Text(
                l10n.notifyScheduleReplaceNote,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading:
                  Icon(Icons.lock, size: 20, color: theme.colorScheme.primary),
              title: Text(
                l10n.notifySchedulePremiumUpsell(kPremiumNotifySlotCount),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
              trailing:
                  Icon(Icons.chevron_right, color: theme.colorScheme.primary),
              onTap: () =>
                  PaywallScreen.show(context, source: 'settings_notify_slots'),
            ),
        ],
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.slot,
    required this.on,
    required this.onTap,
    required this.onChanged,
  });

  final NotifySlot slot;
  final bool on;
  final VoidCallback onTap;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _formatHour(slot.hour),
                style: TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w300,
                  height: 1.1,
                  color: on
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.outline,
                ),
              ),
            ),
            CupertinoSwitch(
              value: on,
              activeTrackColor: theme.colorScheme.primary,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

String _formatHour(int hour) => '${hour.toString().padLeft(2, '0')}:00';

/// iOS の時刻選択風のホイール。配信は時単位なので「時」だけ回す。
class _HourSheet extends StatefulWidget {
  const _HourSheet({required this.initial, required this.taken});

  final int initial;
  final Set<int> taken;

  @override
  State<_HourSheet> createState() => _HourSheetState();
}

class _HourSheetState extends State<_HourSheet> {
  late int _hour = widget.initial;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final taken = widget.taken.contains(_hour);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.commonCancel),
              ),
              Expanded(
                child: Text(
                  l10n.notifyScheduleChangeTime,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: taken ? null : () => Navigator.pop(context, _hour),
                child: Text(l10n.notifyScheduleSave),
              ),
            ],
          ),
          SizedBox(
            height: 216,
            child: CupertinoPicker(
              itemExtent: 40,
              scrollController:
                  FixedExtentScrollController(initialItem: widget.initial),
              onSelectedItemChanged: (h) => setState(() => _hour = h),
              children: [
                for (var h = 0; h < 24; h++)
                  Center(
                    child: Text(
                      _formatHour(h),
                      style: TextStyle(
                        fontSize: 22,
                        color: widget.taken.contains(h)
                            ? theme.colorScheme.outline
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 28,
            child: taken
                ? Text(
                    l10n.notifyScheduleTimeTaken,
                    style: TextStyle(color: theme.colorScheme.error),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
