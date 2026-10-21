// =============================================================================
// notify_slots.dart
// 毎日例文の通知時刻の枠（iPhone のアラーム風）。
//
// free は1枠、premium は [kPremiumNotifySlotCount] 枠を固定で持ち、各枠の
// オン・オフと時刻だけを変える。どの時刻にも新しい例文セットが届く
// （サーバー: deliverDailySentence の notify_hours）。
// プランが変わったら枠は [notifySlotsForPlan] で作り直す。
// =============================================================================

/// premium の枠の数。サーバーの dailysentence.MaxNotifyHours と同じ値。
const int kPremiumNotifySlotCount = 3;

/// premium で足す枠の既定時刻（オフで足す）。
const List<int> _kExtraSlotHours = [7, 20, 12];

class NotifySlot {
  const NotifySlot(this.hour, {this.enabled = true});

  final int hour;
  final bool enabled;

  NotifySlot copyWith({int? hour, bool? enabled}) =>
      NotifySlot(hour ?? this.hour, enabled: enabled ?? this.enabled);

  @override
  bool operator ==(Object other) =>
      other is NotifySlot && other.hour == hour && other.enabled == enabled;

  @override
  int get hashCode => Object.hash(hour, enabled);
}

/// オンの枠の時刻を早い順に。サーバーへ送る notify_hours になる。
List<int> enabledNotifyHours(List<NotifySlot> slots) =>
    [for (final s in slots) if (s.enabled) s.hour]..sort();

/// 時刻順に並べる。表示も保存もこの順。
List<NotifySlot> sortNotifySlots(List<NotifySlot> slots) =>
    [...slots]..sort((a, b) => a.hour.compareTo(b.hour));

/// プランに合わせて枠を作り直す。
///
/// free は1枠: オンの中でいちばん早い時刻（無ければ先頭）を残す。
/// premium は3枠: 今の枠を残し、足りないぶんを既定時刻のオフで足す。
/// どちらも、オンの枠が1つも無ければ先頭をオンにする（通知自体のオフは
/// daily_reminder_enabled が受け持つため、枠はオンを1つ以上持たせる）。
List<NotifySlot> notifySlotsForPlan(
  List<NotifySlot> slots, {
  required bool premium,
  required int fallbackHour,
}) {
  var result = sortNotifySlots(slots);
  if (result.isEmpty) result = [NotifySlot(fallbackHour)];

  if (!premium) {
    final keep = result.firstWhere((s) => s.enabled, orElse: () => result.first);
    return [keep.copyWith(enabled: true)];
  }

  result = result.take(kPremiumNotifySlotCount).toList();
  final taken = {for (final s in result) s.hour};
  final candidates = [
    ..._kExtraSlotHours,
    for (var h = 0; h < 24; h++) h,
  ];
  for (final h in candidates) {
    if (result.length >= kPremiumNotifySlotCount) break;
    if (taken.add(h)) result.add(NotifySlot(h, enabled: false));
  }
  if (!result.any((s) => s.enabled)) {
    result = [result.first.copyWith(enabled: true), ...result.skip(1)];
  }
  return sortNotifySlots(result);
}

/// SharedPreferences 用に "7:0,10:1,20:0" の形へ。
String encodeNotifySlots(List<NotifySlot> slots) =>
    slots.map((s) => '${s.hour}:${s.enabled ? 1 : 0}').join(',');

/// [encodeNotifySlots] の逆。読めない要素は捨て、1つも読めなければ null。
List<NotifySlot>? decodeNotifySlots(String? value) {
  if (value == null || value.isEmpty) return null;
  final slots = <NotifySlot>[];
  final seen = <int>{};
  for (final part in value.split(',')) {
    final pieces = part.split(':');
    if (pieces.length != 2) continue;
    final hour = int.tryParse(pieces[0]);
    if (hour == null || hour < 0 || hour > 23 || !seen.add(hour)) continue;
    slots.add(NotifySlot(hour, enabled: pieces[1] == '1'));
  }
  return slots.isEmpty ? null : sortNotifySlots(slots);
}
