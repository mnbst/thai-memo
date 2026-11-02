import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// 例に出す語。意味は節ごとの `|` 区切りの文言から、出てくる順に引く。
class PronWord {
  final String thai;
  final String reading;

  /// 会話で崩れたときの読み。会話の節だけで使う。
  final String? spoken;

  const PronWord(this.thai, this.reading, [this.spoken]);
}

/// 例の1行。[contrast] なら「A ↔ B」の比べる形、そうでなければ並べるだけ。
class PronRow {
  final List<PronWord> words;
  final bool contrast;

  const PronRow(this.words, {this.contrast = false});
}

/// 発音ガイドの1節。ローディングTips（発音）にもこの並びで出す。
class PronSection {
  final IconData icon;
  final String Function(L10n) title;
  final String Function(L10n) body;
  final List<PronRow> rows;
  final String Function(L10n)? meanings;
  final String Function(L10n)? note;

  const PronSection(this.icon, this.title, this.body, this.rows,
      {this.meanings, this.note});
}

final pronunciationSections = <PronSection>[
  PronSection(
    Icons.compare_arrows,
    (l) => l.pronAspTitle,
    (l) => l.pronAspBody,
    const [
      PronRow([PronWord('ไก่', 'kài'), PronWord('ไข่', 'khài')],
          contrast: true),
      PronRow([PronWord('ตา', 'taa'), PronWord('ทา', 'thaa')], contrast: true),
      PronRow([PronWord('ปา', 'paa'), PronWord('พา', 'phaa')], contrast: true),
    ],
    meanings: (l) => l.pronAspMeanings,
    note: (l) => l.pronAspNote,
  ),
  PronSection(
    Icons.straighten,
    (l) => l.pronLengthTitle,
    (l) => l.pronLengthBody,
    const [
      PronRow([PronWord('เข้า', 'khâw'), PronWord('ข้าว', 'khâaw')],
          contrast: true),
      PronRow([PronWord('เขา', 'khǎw'), PronWord('ขาว', 'khǎaw')],
          contrast: true),
    ],
    meanings: (l) => l.pronLengthMeanings,
  ),
  PronSection(
    Icons.record_voice_over_outlined,
    (l) => l.pronVowelTitle,
    (l) => l.pronVowelBody,
    const [
      PronRow([PronWord('เด็ก', 'dèk'), PronWord('แดด', 'dɛ̀ɛt')],
          contrast: true),
      PronRow([PronWord('โต๊ะ', 'tó'), PronWord('ห้อง', 'hɔ̂ng')],
          contrast: true),
      PronRow([PronWord('ดู', 'duu'), PronWord('มือ', 'mʉʉ')], contrast: true),
      PronRow([PronWord('เงิน', 'ngən'), PronWord('เดิน', 'dəən')]),
    ],
    meanings: (l) => l.pronVowelMeanings,
  ),
  PronSection(
    Icons.stop_circle_outlined,
    (l) => l.pronFinalTitle,
    (l) => l.pronFinalBody,
    const [
      PronRow([
        PronWord('นก', 'nók'),
        PronWord('รถ', 'rót'),
        PronWord('กับ', 'kàp')
      ]),
      PronRow([PronWord('จาน', 'jaan'), PronWord('จาง', 'jaang')],
          contrast: true),
    ],
    meanings: (l) => l.pronFinalMeanings,
    note: (l) => l.pronFinalNote,
  ),
  PronSection(
    Icons.forum_outlined,
    (l) => l.pronCasualTitle,
    (l) => l.pronCasualBody,
    const [
      PronRow([PronWord('รัก', 'rák', 'lák')]),
      PronRow([PronWord('ครับ', 'khráp', 'kháp')]),
      PronRow([PronWord('ไหม', 'mǎi', 'mái')]),
      PronRow([PronWord('ฉัน', 'chǎn', 'chán')]),
    ],
    meanings: (l) => l.pronCasualMeanings,
    note: (l) => l.pronCasualNote,
  ),
];
