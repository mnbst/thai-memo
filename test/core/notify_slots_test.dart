import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/notify_slots.dart';

void main() {
  group('notifySlotsForPlan', () {
    test('free はオンの中でいちばん早い1つだけ残す', () {
      final slots = [
        const NotifySlot(7, enabled: false),
        const NotifySlot(20),
        const NotifySlot(10),
      ];
      expect(
        notifySlotsForPlan(slots, premium: false, fallbackHour: 10),
        [const NotifySlot(10)],
      );
    });

    test('free でオンが無ければ先頭をオンで残す', () {
      final slots = [
        const NotifySlot(9, enabled: false),
        const NotifySlot(21, enabled: false),
      ];
      expect(
        notifySlotsForPlan(slots, premium: false, fallbackHour: 10),
        [const NotifySlot(9)],
      );
    });

    test('premium は今の時刻を残して3枠まで既定時刻のオフで足す', () {
      expect(
        notifySlotsForPlan(
          [const NotifySlot(10)],
          premium: true,
          fallbackHour: 10,
        ),
        [
          const NotifySlot(7, enabled: false),
          const NotifySlot(10),
          const NotifySlot(20, enabled: false),
        ],
      );
    });

    test('premium で既定時刻が埋まっていれば別の時刻を足す', () {
      final result = notifySlotsForPlan(
        [const NotifySlot(7), const NotifySlot(20)],
        premium: true,
        fallbackHour: 10,
      );
      expect(result.map((s) => s.hour), [7, 12, 20]);
      expect(result.where((s) => s.enabled).length, 2);
    });

    test('空なら既定時刻の1枠', () {
      expect(
        notifySlotsForPlan(const [], premium: false, fallbackHour: 8),
        [const NotifySlot(8)],
      );
    });
  });

  test('enabledNotifyHours は早い順', () {
    expect(
      enabledNotifyHours([
        const NotifySlot(20),
        const NotifySlot(7, enabled: false),
        const NotifySlot(9),
      ]),
      [9, 20],
    );
  });

  group('encode / decode', () {
    test('往復できる', () {
      final slots = [
        const NotifySlot(7, enabled: false),
        const NotifySlot(10),
        const NotifySlot(20, enabled: false),
      ];
      expect(decodeNotifySlots(encodeNotifySlots(slots)), slots);
    });

    test('壊れた要素・重複は捨てる', () {
      expect(
        decodeNotifySlots('20:1,x,25:1,9:0,20:0'),
        [const NotifySlot(9, enabled: false), const NotifySlot(20)],
      );
    });

    test('読めなければ null', () {
      expect(decodeNotifySlots(null), isNull);
      expect(decodeNotifySlots(''), isNull);
      expect(decodeNotifySlots('x'), isNull);
    });
  });
}
