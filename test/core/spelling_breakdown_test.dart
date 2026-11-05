import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/core/spelling_breakdown.dart';
import 'package:thai_memo/data/models/syllable.dart';

void main() {
  final index = SpellingIndex.fromJson(
    jsonDecode(File('assets/spelling_forms.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  SpellingBreakdown one(String word) {
    final items = index.items(word);
    expect(items, hasLength(1));
    return items.single.breakdown;
  }

  List<String> cells(String word) => one(word)
      .parts
      .map((p) => '${p.role}:${p.text}:${p.sound}${p.tone}')
      .toList();

  test('頭子音・母音・末子音・声調に分ける', () {
    expect(cells('กิน'), [
      'onset:ก:k',
      'vowel:ิ:i',
      'coda:น:n',
      'tone::mid',
    ]);
    // ไ は母音と末子音を兼ねるので、末子音に字は付かない。
    expect(cells('ไม่'), [
      'onset:ม:m',
      'vowel:ไ:a',
      'coda::i',
      'tone:่:falling',
    ]);
  });

  test('読まない字は別の枠にする', () {
    expect(cells('จริง').last, 'silent:ร:');
  });

  test('書く順の字と声調の3要素を返す', () {
    final b = one('เพื่อน');
    expect(b.glyphs.first.text, 'เ');
    expect(b.glyphs.first.role, 'vowel');
    expect(b.toneRule?.consonantClass, 'low');
    expect(b.toneRule?.syllable, 'live');
    expect(b.toneRule?.mark, '่');
  });

  test('基本の音節を分解できる', () {
    for (final s in ['ความ', 'ตัว', 'จะ', 'ประ', 'มา', 'นา', 'ถึง', 'ครั้ง']) {
      expect(index.items(s), hasLength(1), reason: s);
    }
    expect(cells('มา')[1], 'vowel:า:aa');
  });

  test('短い ə の綴りを分解できる', () {
    expect(cells('เงิน')[1], startsWith('vowel:'));
    expect(cells('เงิน')[1], endsWith(':ə'));
    expect(cells('เยอะ')[1], endsWith(':ə'));
  });

  test('先頭の字だけで「オー」を読む綴りも2つに分ける', () {
    final items = index.items('บริ');
    expect(items.map((e) => e.text), ['บ', 'ริ']);
    expect(items[0].breakdown.parts[1].sound, 'ɔɔ');
  });

  test('表に無い綴りは空', () {
    expect(index.items('สวัสดี'), isEmpty);
    expect(index.items('ๆ'), isEmpty);
    // 発音が区切られる略語は1音節として扱わない。
    expect(index.items('อ.ส.'), isEmpty);
  });

  test('先頭の字だけで a を読む綴りは2つに分け、階級は前の字から借りる', () {
    final items = index.items('ตลาด');
    expect(items.map((e) => e.text), ['ต', 'ลาด']);
    final head = items[0].breakdown;
    expect(head.parts[1].text, '');
    expect(head.parts[1].sound, 'a');
    final tail = items[1].breakdown;
    expect(tail.toneRule?.consonantClass, 'mid');
    expect(tail.toneLeader, 'ต');
    final s = tail.applyTo(Syllable.fromText('ลาด'));
    expect(s.tone, 'low');
    expect(s.initialConsonant, 'ตล');
  });

  test('読みと合わないときは前の字から階級を借りない', () {
    final tail = index.items('ขโมย')[1].breakdown;
    expect(tail.toneLeader, isNull);
    expect(tail.toneRule?.consonantClass, 'low');
  });

  test('語が1音節ならそのまま、違えば分解できる音節だけ返す', () {
    expect(
      index.forWord('ไม่', const ['ไม่']).map((e) => e.text),
      ['ไม่'],
    );
    expect(
      index.forWord('ภาษา', const ['ภา', 'ษา']).map((e) => e.text),
      ['ภา', 'ษา'],
    );
    expect(
      index.forWord('สวัสดี', const ['สวัส', 'ดี']).map((e) => e.text),
      ['ส', 'วัส', 'ดี'],
    );
    expect(
      index.forWord('ๆๆ', const ['ๆ', 'ดี']).map((e) => e.text),
      ['ดี'],
    );
  });
  test('音節の声調情報を分解に合わせる', () {
    // 外来語は規則どおりでなく、辞書由来の対応表では高声。
    final s = one('กราฟ').applyTo(Syllable.fromText('กราฟ'));
    expect(s.tone, 'high');
    expect(s.consonantClass, 'middle');
    expect(s.syllableType, 'dead');
    expect(s.toneMark, 'none');
  });
}
