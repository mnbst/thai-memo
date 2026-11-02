import '../../l10n/app_localizations.dart';

/// 例文1つ。語ごとにタイ文字・読み・意味を並べ、その項目で見てほしい語を
/// [focus] で色付きにする。意味は `|` 区切りで語と同じ数だけ持つ。
class WordOrderExample {
  final List<String> words;
  final List<String> readings;
  final Set<int> focus;
  final String Function(L10n) gloss;
  final String Function(L10n) meaning;

  const WordOrderExample(
    this.words,
    this.readings,
    this.focus,
    this.gloss,
    this.meaning,
  );
}

/// 語順ガイドの1項目。ローディングTips（文法）にもこの並びで出す。
class WordOrderRule {
  final String Function(L10n) title;
  final String Function(L10n) body;
  final List<WordOrderExample> examples;
  final String Function(L10n)? note;

  const WordOrderRule(this.title, this.body, this.examples, [this.note]);
}

// 表示順はこの並び。キーの番号は追加順で、表示番号とは一致しない。
final wordOrderRules = <WordOrderRule>[
  WordOrderRule(
    (l) => l.wordOrderRule1Title,
    (l) => l.wordOrderRule1Body,
    [
      WordOrderExample(
          ['ทัวร์', 'นี้', 'คน', 'เยอะ'],
          ['thua', 'níi', 'khon', 'yə́'],
          {0, 1},
          (l) => l.wordOrderEx1aGloss,
          (l) => l.wordOrderEx1aMeaning),
      WordOrderExample(
          ['สนามบิน', 'คน', 'เยอะ'],
          ['sà-nǎam-bin', 'khon', 'yə́'],
          {0},
          (l) => l.wordOrderEx1bGloss,
          (l) => l.wordOrderEx1bMeaning),
    ],
    (l) => l.wordOrderRule1Note,
  ),
  WordOrderRule(
    (l) => l.wordOrderRule2Title,
    (l) => l.wordOrderRule2Body,
    [
      WordOrderExample(
          ['รายงาน', 'นี้', 'พรุ่งนี้', 'ใช้', 'ได้', 'ไหม'],
          ['raai-ngaan', 'níi', 'phrûng-níi', 'chái', 'dâai', 'mǎi'],
          {0, 1},
          (l) => l.wordOrderEx2aGloss,
          (l) => l.wordOrderEx2aMeaning),
    ],
  ),
  WordOrderRule(
    (l) => l.wordOrderRule3Title,
    (l) => l.wordOrderRule3Body,
    [
      WordOrderExample(['ผม', 'กิน', 'ข้าว'], ['phǒm', 'kin', 'khâaw'], {1},
          (l) => l.wordOrderEx3aGloss, (l) => l.wordOrderEx3aMeaning),
    ],
    (l) => l.wordOrderRule3Note,
  ),
  WordOrderRule(
    (l) => l.wordOrderRule4Title,
    (l) => l.wordOrderRule4Body,
    [
      WordOrderExample(['บ้าน', 'ใหญ่'], ['bâan', 'yài'], {1},
          (l) => l.wordOrderEx4aGloss, (l) => l.wordOrderEx4aMeaning),
      WordOrderExample(['บ้าน', 'ของ', 'ผม'], ['bâan', 'khɔ̌ɔng', 'phǒm'],
          {1, 2}, (l) => l.wordOrderEx4bGloss, (l) => l.wordOrderEx4bMeaning),
    ],
    (l) => l.wordOrderRule4Note,
  ),
  WordOrderRule(
    (l) => l.wordOrderRule11Title,
    (l) => l.wordOrderRule11Body,
    [
      WordOrderExample(
          ['ร้าน', 'ที่', 'ผม', 'ชอบ'],
          ['ráan', 'thîi', 'phǒm', 'chɔ̂ɔp'],
          {1, 2, 3},
          (l) => l.wordOrderEx11aGloss,
          (l) => l.wordOrderEx11aMeaning),
    ],
  ),
  WordOrderRule(
    (l) => l.wordOrderRule5Title,
    (l) => l.wordOrderRule5Body,
    [
      WordOrderExample(['แมว', 'สอง', 'ตัว'], ['mɛɛw', 'sɔ̌ɔng', 'tua'], {1, 2},
          (l) => l.wordOrderEx5aGloss, (l) => l.wordOrderEx5aMeaning),
      WordOrderExample(
          ['แมว', 'สอง', 'ตัว', 'นี้'],
          ['mɛɛw', 'sɔ̌ɔng', 'tua', 'níi'],
          {1, 2, 3},
          (l) => l.wordOrderEx5bGloss,
          (l) => l.wordOrderEx5bMeaning),
    ],
    (l) => l.wordOrderRule5Note,
  ),
  WordOrderRule(
    (l) => l.wordOrderRule12Title,
    (l) => l.wordOrderRule12Body,
    [
      WordOrderExample(
          ['ผม', 'ไป', 'กับ', 'เพื่อน'],
          ['phǒm', 'pai', 'kàp', 'phʉ̂an'],
          {2, 3},
          (l) => l.wordOrderEx12aGloss,
          (l) => l.wordOrderEx12aMeaning),
      WordOrderExample(
          ['แมว', 'อยู่', 'บน', 'โต๊ะ'],
          ['mɛɛw', 'yùu', 'bon', 'tó'],
          {2, 3},
          (l) => l.wordOrderEx12bGloss,
          (l) => l.wordOrderEx12bMeaning),
    ],
  ),
  WordOrderRule(
    (l) => l.wordOrderRule13Title,
    (l) => l.wordOrderRule13Body,
    [
      WordOrderExample(
          ['อาหาร', 'นี้', 'อร่อย', 'มาก'],
          ['aa-hǎan', 'níi', 'à-rɔ̀i', 'mâak'],
          {3},
          (l) => l.wordOrderEx13aGloss,
          (l) => l.wordOrderEx13aMeaning),
    ],
  ),
  WordOrderRule(
    (l) => l.wordOrderRule14Title,
    (l) => l.wordOrderRule14Body,
    [
      WordOrderExample(
          ['วันนี้', 'ร้อน', 'กว่า', 'เมื่อวาน'],
          ['wan-níi', 'rɔ́ɔn', 'kwàa', 'mʉ̂a-waan'],
          {2, 3},
          (l) => l.wordOrderEx14aGloss,
          (l) => l.wordOrderEx14aMeaning),
      WordOrderExample(
          ['อัน', 'นี้', 'ดี', 'ที่สุด'],
          ['an', 'níi', 'dii', 'thîi-sùt'],
          {3},
          (l) => l.wordOrderEx14bGloss,
          (l) => l.wordOrderEx14bMeaning),
    ],
  ),
  WordOrderRule(
    (l) => l.wordOrderRule6Title,
    (l) => l.wordOrderRule6Body,
    [
      WordOrderExample(
          ['ผม', 'ไม่', 'กิน', 'เผ็ด'],
          ['phǒm', 'mâi', 'kin', 'phèt'],
          {1},
          (l) => l.wordOrderEx6aGloss,
          (l) => l.wordOrderEx6aMeaning),
      WordOrderExample(['ผม', 'ไม่ได้', 'ไป'], ['phǒm', 'mâi dâai', 'pai'], {1},
          (l) => l.wordOrderEx6bGloss, (l) => l.wordOrderEx6bMeaning),
      WordOrderExample(['ไป', 'ไม่ได้'], ['pai', 'mâi dâai'], {1},
          (l) => l.wordOrderEx6cGloss, (l) => l.wordOrderEx6cMeaning),
    ],
    (l) => l.wordOrderRule6Note,
  ),
  WordOrderRule(
    (l) => l.wordOrderRule7Title,
    (l) => l.wordOrderRule7Body,
    [
      WordOrderExample(['คุณ', 'กิน', 'อะไร'], ['khun', 'kin', 'à-rai'], {2},
          (l) => l.wordOrderEx7aGloss, (l) => l.wordOrderEx7aMeaning),
      WordOrderExample(['ไป', 'ไหน'], ['pai', 'nǎi'], {1},
          (l) => l.wordOrderEx7bGloss, (l) => l.wordOrderEx7bMeaning),
      WordOrderExample(['กิน', 'ไหม'], ['kin', 'mǎi'], {1},
          (l) => l.wordOrderEx7cGloss, (l) => l.wordOrderEx7cMeaning),
    ],
  ),
  WordOrderRule(
    (l) => l.wordOrderRule8Title,
    (l) => l.wordOrderRule8Body,
    [
      WordOrderExample(['ผม', 'จะ', 'ไป'], ['phǒm', 'jà', 'pai'], {1},
          (l) => l.wordOrderEx8aGloss, (l) => l.wordOrderEx8aMeaning),
      WordOrderExample(['กิน', 'ข้าว', 'แล้ว'], ['kin', 'khâaw', 'lɛ́ɛw'], {2},
          (l) => l.wordOrderEx8bGloss, (l) => l.wordOrderEx8bMeaning),
    ],
  ),
  WordOrderRule(
    (l) => l.wordOrderRule15Title,
    (l) => l.wordOrderRule15Body,
    [
      WordOrderExample(
          ['ผม', 'อยาก', 'กิน', 'ส้มตำ'],
          ['phǒm', 'yàak', 'kin', 'sôm-tam'],
          {1},
          (l) => l.wordOrderEx15aGloss,
          (l) => l.wordOrderEx15aMeaning),
      WordOrderExample(
          ['ผม', 'พูด', 'ภาษาไทย', 'ได้'],
          ['phǒm', 'phûut', 'phaa-sǎa-thai', 'dâai'],
          {3},
          (l) => l.wordOrderEx15bGloss,
          (l) => l.wordOrderEx15bMeaning),
    ],
  ),
  WordOrderRule(
    (l) => l.wordOrderRule16Title,
    (l) => l.wordOrderRule16Body,
    [
      WordOrderExample(
          ['ผม', 'ไป', 'ซื้อ', 'ของ'],
          ['phǒm', 'pai', 'sʉ́ʉ', 'khɔ̌ɔng'],
          {1, 2},
          (l) => l.wordOrderEx16aGloss,
          (l) => l.wordOrderEx16aMeaning),
      WordOrderExample(['เอา', 'น้ำ', 'มา'], ['ao', 'náam', 'maa'], {2},
          (l) => l.wordOrderEx16bGloss, (l) => l.wordOrderEx16bMeaning),
      WordOrderExample(['เดิน', 'กลับ', 'บ้าน'], ['dəən', 'klàp', 'bâan'],
          {0, 1}, (l) => l.wordOrderEx16cGloss, (l) => l.wordOrderEx16cMeaning),
    ],
  ),
  WordOrderRule(
    (l) => l.wordOrderRule17Title,
    (l) => l.wordOrderRule17Body,
    [
      WordOrderExample(['กิน', 'หมด'], ['kin', 'mòt'], {1},
          (l) => l.wordOrderEx17aGloss, (l) => l.wordOrderEx17aMeaning),
      WordOrderExample(['กิน', 'เสร็จ'], ['kin', 'sèt'], {1},
          (l) => l.wordOrderEx17bGloss, (l) => l.wordOrderEx17bMeaning),
      WordOrderExample(['กิน', 'ต่อ'], ['kin', 'tɔ̀ɔ'], {1},
          (l) => l.wordOrderEx17cGloss, (l) => l.wordOrderEx17cMeaning),
    ],
  ),
  WordOrderRule(
    (l) => l.wordOrderRule18Title,
    (l) => l.wordOrderRule18Body,
    [
      WordOrderExample(['ลองๆ', 'ดู'], ['lɔɔng-lɔɔng', 'duu'], {0},
          (l) => l.wordOrderEx18aGloss, (l) => l.wordOrderEx18aMeaning),
      WordOrderExample(['เดินๆ', 'หยุดๆ'], ['dəən-dəən', 'yùt-yùt'], {0, 1},
          (l) => l.wordOrderEx18bGloss, (l) => l.wordOrderEx18bMeaning),
      WordOrderExample(['ดูๆ', 'ไป', 'ก่อน'], ['duu-duu', 'pai', 'kɔ̀ɔn'], {0},
          (l) => l.wordOrderEx18cGloss, (l) => l.wordOrderEx18cMeaning),
    ],
    (l) => l.wordOrderRule18Note,
  ),
  WordOrderRule(
    (l) => l.wordOrderRule9Title,
    (l) => l.wordOrderRule9Body,
    [
      WordOrderExample(
          ['พรุ่งนี้', 'ผม', 'จะ', 'ไป', 'เชียงใหม่'],
          ['phrûng-níi', 'phǒm', 'jà', 'pai', 'chiang-mài'],
          {0, 4},
          (l) => l.wordOrderEx9aGloss,
          (l) => l.wordOrderEx9aMeaning),
      WordOrderExample(
          ['ผม', 'ทำงาน', 'ที่', 'กรุงเทพฯ'],
          ['phǒm', 'tham-ngaan', 'thîi', 'krung-thêep'],
          {2, 3},
          (l) => l.wordOrderEx9bGloss,
          (l) => l.wordOrderEx9bMeaning),
    ],
  ),
  WordOrderRule(
    (l) => l.wordOrderRule10Title,
    (l) => l.wordOrderRule10Body,
    [
      WordOrderExample(['กิน', 'ไหม', 'คะ'], ['kin', 'mǎi', 'khá'], {2},
          (l) => l.wordOrderEx10aGloss, (l) => l.wordOrderEx10aMeaning),
      WordOrderExample(['กิน', 'แล้ว', 'ค่ะ'], ['kin', 'lɛ́ɛw', 'khâ'], {2},
          (l) => l.wordOrderEx10bGloss, (l) => l.wordOrderEx10bMeaning),
      WordOrderExample(['อร่อย', 'นะ', 'คะ'], ['à-rɔ̀i', 'ná', 'khá'], {1, 2},
          (l) => l.wordOrderEx10cGloss, (l) => l.wordOrderEx10cMeaning),
    ],
  ),
];
