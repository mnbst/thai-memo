import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/services/daily_sentence_service.dart';

MapEntry<String, Map<String, dynamic>> _doc(
  String id, {
  String? setId,
  int? index,
}) =>
    MapEntry(id, {
      'daily': true,
      if (setId != null) 'daily_set_id': setId,
      if (index != null) 'daily_set_index': index,
    });

void main() {
  group('orderSetMembers', () {
    test('同じセットだけを daily_set_index の昇順で返す', () {
      final docs = [
        _doc('c', setId: 'a', index: 2),
        _doc('other', setId: 'z', index: 0),
        _doc('a', setId: 'a', index: 0),
        _doc('b', setId: 'a', index: 1),
      ];

      final got = DailySentenceService.orderSetMembers('a', docs);

      expect([for (final m in got) m.key], ['a', 'b', 'c']);
    });

    test('daily_set_id が無い旧形式は doc ID 自身を1本のセットとして扱う', () {
      final docs = [_doc('old'), _doc('a', setId: 'a', index: 0)];

      expect(
        [
          for (final m in DailySentenceService.orderSetMembers('old', docs))
            m.key
        ],
        ['old'],
      );
    });

    test('index が欠けていても落とさない（0 として並べる）', () {
      final docs = [_doc('b', setId: 'a', index: 1), _doc('a', setId: 'a')];

      expect(
        [
          for (final m in DailySentenceService.orderSetMembers('a', docs)) m.key
        ],
        ['a', 'b'],
      );
    });
  });
}
