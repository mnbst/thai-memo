import 'dart:ui';

import '../../l10n/app_localizations.dart';
import 'pronunciation_guide_sections.dart';
import 'word_order_rules.dart';

// =============================================================================
// loading_tips.dart
// 例文生成中のローディング画面に表示する「タイ語ミニ知識」のデータ定義。
//
// Gemini AIによる例文生成は数秒〜数十秒かかるため、待ち時間を有効活用して
// タイ語の母音・子音・声調・数字・日常表現・文化に関するTipsをランダム表示する。
// 各ガイド（語順・発音・声調・タイ文字・使い方の「続けるためのコツ」）の内容も
// ガイドの文言からそのまま組み立てて混ぜる。ガイドと重なる固有Tipsは持たない。
// ユーザーは例文生成を待つ間にタイ語の基礎知識を自然に学べる仕組みになっている。
//
// 各Tipはカテゴリ（母音/子音/声調/数字/日常表現/文化）、タイトル、
// 解説テキスト、具体例（任意）で構成される。
// =============================================================================

/// ローディング画面に表示する1件分のTipsデータを保持するクラス。
///
/// 例文生成の待ち時間中に、タイ語学習に役立つミニ知識を表示するために使用する。
class LoadingTip {
  /// Tipsのカテゴリ（例: 母音, 子音, 声調, 数字, 日常表現, 文化）
  final String category;

  /// Tipsのタイトル（簡潔な見出し）
  final String title;

  /// Tipsの解説テキスト（詳しい説明）
  final String content;

  /// 具体的な用例（任意。タイ語とユーザーの母語訳を含む）
  final String? example;

  /// [LoadingTip] のコンストラクタ。
  /// [category]、[title]、[content] は必須、[example] は任意。
  const LoadingTip({
    required this.category,
    required this.title,
    required this.content,
    this.example,
  });
}

/// ローディングTipsの全データを管理する定数クラス。
///
/// [all] リストに全Tipsを保持し、ローディング画面からランダムに1件を
/// 取得して表示する。カテゴリは以下の通り:
///   - 母音: タイ語の短母音・長母音・複合母音の読み方
///   - 文化: タイの挨拶・寺院・祭りなどの文化習慣
///   - 声調: タイ語の5つの声調と声調記号の解説
///   - 子音: タイ語44文字の子音の分類と発音ルール
///   - 数字: タイ数字の読み方と類別詞
///   - 日常表現: 日常会話で頻出するフレーズ
///   - 文法: 語順ガイドの各項目（word_order_rules.dart から組み立てる）
///   - 発音: 発音ガイドの各節（pronunciation_guide_sections.dart から組み立てる）
///   - 文字: タイ文字ガイドの各説明
class LoadingTips {
  /// インスタンス化を禁止するプライベートコンストラクタ
  LoadingTips._();

  /// Tipsの件数。表示順を決めるだけなら文言を解決する必要はない。
  static final int count = all(lookupL10n(const Locale('ja'))).length;

  /// 添字で1件だけ解決する。
  static LoadingTip at(L10n l10n, int index) => all(l10n)[index];

  /// 全Tipsデータ。文言は言語設定に追従するため、定数ではなく都度組み立てる。
  static List<LoadingTip> all(L10n l10n) => [
        LoadingTip(
          category: l10n.tipCatVowel,
          title: l10n.tip_vowelUea_title,
          content: l10n.tip_vowelUea_content,
          example: l10n.tip_vowelUea_example,
        ),
        LoadingTip(
          category: l10n.tipCatVowel,
          title: l10n.tip_vowelIa_title,
          content: l10n.tip_vowelIa_content,
          example: l10n.tip_vowelIa_example,
        ),
        LoadingTip(
          category: l10n.tipCatVowel,
          title: l10n.tip_vowelUa_title,
          content: l10n.tip_vowelUa_content,
          example: l10n.tip_vowelUa_example,
        ),
        LoadingTip(
          category: l10n.tipCatVowel,
          title: l10n.tip_vowelAw_title,
          content: l10n.tip_vowelAw_content,
          example: l10n.tip_vowelAw_example,
        ),
        LoadingTip(
          category: l10n.tipCatVowel,
          title: l10n.tip_vowelAi_title,
          content: l10n.tip_vowelAi_content,
          example: l10n.tip_vowelAi_example,
        ),
        LoadingTip(
          category: l10n.tipCatCulture,
          title: l10n.tip_cultureWai_title,
          content: l10n.tip_cultureWai_content,
        ),
        LoadingTip(
          category: l10n.tipCatCulture,
          title: l10n.tip_cultureTemple_title,
          content: l10n.tip_cultureTemple_content,
        ),
        LoadingTip(
          category: l10n.tipCatCulture,
          title: l10n.tip_cultureSongkran_title,
          content: l10n.tip_cultureSongkran_content,
        ),
        LoadingTip(
          category: l10n.tipCatCulture,
          title: l10n.tip_cultureLoyKrathong_title,
          content: l10n.tip_cultureLoyKrathong_content,
        ),
        LoadingTip(
          category: l10n.tipCatCulture,
          title: l10n.tip_cultureEating_title,
          content: l10n.tip_cultureEating_content,
        ),
        LoadingTip(
          category: l10n.tipCatCulture,
          title: l10n.tip_cultureMaiPenRai_title,
          content: l10n.tip_cultureMaiPenRai_content,
        ),
        LoadingTip(
          category: l10n.tipCatTone,
          title: l10n.tip_toneMistake_title,
          content: l10n.tip_toneMistake_content,
        ),
        LoadingTip(
          category: l10n.tipCatTone,
          title: l10n.tip_toneRelative_title,
          content: l10n.tip_toneRelative_content,
        ),
        LoadingTip(
          category: l10n.tipCatConsonant,
          title: l10n.tip_consonant44_title,
          content: l10n.tip_consonant44_content,
        ),
        LoadingTip(
          category: l10n.tipCatConsonant,
          title: l10n.tip_consonantHigh_title,
          content: l10n.tip_consonantHigh_content,
        ),
        LoadingTip(
          category: l10n.tipCatConsonant,
          title: l10n.tip_consonantMid_title,
          content: l10n.tip_consonantMid_content,
        ),
        LoadingTip(
          category: l10n.tipCatConsonant,
          title: l10n.tip_consonantLow_title,
          content: l10n.tip_consonantLow_content,
        ),
        LoadingTip(
          category: l10n.tipCatConsonant,
          title: l10n.tip_consonantSilent_title,
          content: l10n.tip_consonantSilent_content,
          example: l10n.tip_consonantSilent_example,
        ),
        LoadingTip(
          category: l10n.tipCatConsonant,
          title: l10n.tip_consonantCluster_title,
          content: l10n.tip_consonantCluster_content,
          example: l10n.tip_consonantCluster_example,
        ),
        LoadingTip(
          category: l10n.tipCatNumber,
          title: l10n.tip_numberThai_title,
          content: l10n.tip_numberThai_content,
        ),
        LoadingTip(
          category: l10n.tipCatNumber,
          title: l10n.tip_number1to5_title,
          content: l10n.tip_number1to5_content,
        ),
        LoadingTip(
          category: l10n.tipCatNumber,
          title: l10n.tip_number6to10_title,
          content: l10n.tip_number6to10_content,
        ),
        LoadingTip(
          category: l10n.tipCatNumber,
          title: l10n.tip_number11and21_title,
          content: l10n.tip_number11and21_content,
        ),
        LoadingTip(
          category: l10n.tipCatNumber,
          title: l10n.tip_numberBig_title,
          content: l10n.tip_numberBig_content,
        ),
        LoadingTip(
          category: l10n.tipCatNumber,
          title: l10n.tip_numberPrice_title,
          content: l10n.tip_numberPrice_content,
          example: l10n.tip_numberPrice_example,
        ),
        LoadingTip(
          category: l10n.tipCatDaily,
          title: l10n.tip_dailyHello_title,
          content: l10n.tip_dailyHello_content,
        ),
        LoadingTip(
          category: l10n.tipCatDaily,
          title: l10n.tip_dailyThanks_title,
          content: l10n.tip_dailyThanks_content,
        ),
        LoadingTip(
          category: l10n.tipCatDaily,
          title: l10n.tip_dailySorry_title,
          content: l10n.tip_dailySorry_content,
        ),
        LoadingTip(
          category: l10n.tipCatDaily,
          title: l10n.tip_dailyYesNo_title,
          content: l10n.tip_dailyYesNo_content,
          example: l10n.tip_dailyYesNo_example,
        ),
        LoadingTip(
          category: l10n.tipCatDaily,
          title: l10n.tip_dailyEat_title,
          content: l10n.tip_dailyEat_content,
        ),
        LoadingTip(
          category: l10n.tipCatDaily,
          title: l10n.tip_dailyDelicious_title,
          content: l10n.tip_dailyDelicious_content,
        ),
        LoadingTip(
          category: l10n.tipCatDaily,
          title: l10n.tip_dailyPronouns_title,
          content: l10n.tip_dailyPronouns_content,
          example: l10n.tip_dailyPronouns_example,
        ),
        LoadingTip(
          category: l10n.tipCatStudy,
          title: l10n.tip_studyThaiOnly_title,
          content: l10n.tip_studyThaiOnly_content,
        ),
        ..._guideTips(l10n),
      ];

  /// ガイドの文言から組み立てる Tips。
  static List<LoadingTip> _guideTips(L10n l10n) {
    // タイ文字ガイドの見出しは「1. 」のような番号付きなので外す。
    String script(String title) => title.replaceFirst(RegExp(r'^\d+\.\s*'), '');
    LoadingTip tone(String title, String desc, String example) => LoadingTip(
        category: l10n.tipCatTone,
        title: title,
        content: desc,
        example: example);
    LoadingTip scriptTip(String title, String content) => LoadingTip(
        category: l10n.tipCatScript, title: script(title), content: content);
    LoadingTip study(String content) => LoadingTip(
        category: l10n.tipCatStudy,
        title: l10n.guideTipsTitle,
        content: content);
    return [
      for (final rule in wordOrderRules) _grammarTip(l10n, rule),
      for (final section in pronunciationSections)
        _pronunciationTip(l10n, section),
      LoadingTip(
          category: l10n.tipCatTone,
          title: l10n.toneGuideHeading,
          content: l10n.toneGuideIntro),
      tone(l10n.toneMid, l10n.toneMidDesc, l10n.toneMidExample),
      tone(l10n.toneLow, l10n.toneLowDesc, l10n.toneLowExample),
      tone(l10n.toneFalling, l10n.toneFallingDesc, l10n.toneFallingExample),
      tone(l10n.toneHigh, l10n.toneHighDesc, l10n.toneHighExample),
      tone(l10n.toneRising, l10n.toneRisingDesc, l10n.toneRisingExample),
      scriptTip(l10n.thaiScriptBasicsTitle, l10n.thaiScriptBasicsBody),
      scriptTip(l10n.thaiScriptBasicsTitle, l10n.thaiScriptBasicsDirection),
      scriptTip(l10n.thaiScriptBasicsTitle, l10n.thaiScriptBasicsVowelPosition),
      scriptTip(
          l10n.thaiScriptConsonantsTitle, l10n.thaiScriptConsonantCarrierNote),
      scriptTip(l10n.thaiScriptVowelPairsTitle, l10n.thaiScriptVowelPairsBody),
      scriptTip(l10n.thaiScriptToneMarksTitle, l10n.thaiScriptToneMarksBody),
      scriptTip(l10n.thaiScriptToneMarksTitle, l10n.thaiScriptToneRule),
      study(l10n.guideTipsRepeat),
      study(l10n.guideTipsScript),
      study(l10n.guideTipsSpeak),
    ];
  }

  /// 発音ガイドの1節を Tip にする。例は先頭の1行（会話の崩れは崩れた読みも添える）。
  static LoadingTip _pronunciationTip(L10n l10n, PronSection section) {
    final meanings = section.meanings?.call(l10n).split('|') ?? const [];
    final row = section.rows.first;
    final example = [
      for (final (i, word) in row.words.indexed)
        l10n.tipWordExample(
          word.thai,
          word.spoken == null
              ? word.reading
              : '${word.reading} → ${word.spoken}',
          i < meanings.length ? meanings[i] : '',
        ),
    ].join(' / ');
    final note = section.note?.call(l10n);
    return LoadingTip(
      category: l10n.tipCatPronunciation,
      title: section.title(l10n),
      content:
          note == null ? section.body(l10n) : '${section.body(l10n)}\n$note',
      example: example,
    );
  }

  /// 語順ガイドの1項目を Tip にする。例は先頭の例文。
  static LoadingTip _grammarTip(L10n l10n, WordOrderRule rule) {
    final example = rule.examples.first;
    return LoadingTip(
      category: l10n.tipCatGrammar,
      title: rule.title(l10n),
      content: rule.body(l10n),
      example: l10n.tipGrammarExample(
          example.words.join(' '), example.meaning(l10n)),
    );
  }
}
