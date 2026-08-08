import '../../l10n/app_localizations.dart';

// =============================================================================
// loading_tips.dart
// 例文生成中のローディング画面に表示する「タイ語ミニ知識」のデータ定義。
//
// Gemini AIによる例文生成は数秒〜数十秒かかるため、待ち時間を有効活用して
// タイ語の母音・子音・声調・数字・日常表現・文化に関するTipsをランダム表示する。
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
class LoadingTips {
  /// インスタンス化を禁止するプライベートコンストラクタ
  LoadingTips._();

  /// Tipsの件数。表示順を決めるだけなら文言を解決する必要はない。
  static const int count = 54;

  /// 添字で1件だけ解決する。
  static LoadingTip at(L10n l10n, int index) => all(l10n)[index];

  /// 全Tipsデータ。文言は言語設定に追従するため、定数ではなく都度組み立てる。
  static List<LoadingTip> all(L10n l10n) => [
        LoadingTip(
          category: l10n.tipCatVowel,
          title: l10n.tip_vowelA_title,
          content: l10n.tip_vowelA_content,
          example: l10n.tip_vowelA_example,
        ),
        LoadingTip(
          category: l10n.tipCatVowel,
          title: l10n.tip_vowelI_title,
          content: l10n.tip_vowelI_content,
          example: l10n.tip_vowelI_example,
        ),
        LoadingTip(
          category: l10n.tipCatVowel,
          title: l10n.tip_vowelU_title,
          content: l10n.tip_vowelU_content,
          example: l10n.tip_vowelU_example,
        ),
        LoadingTip(
          category: l10n.tipCatVowel,
          title: l10n.tip_vowelE_title,
          content: l10n.tip_vowelE_content,
          example: l10n.tip_vowelE_example,
        ),
        LoadingTip(
          category: l10n.tipCatVowel,
          title: l10n.tip_vowelO_title,
          content: l10n.tip_vowelO_content,
          example: l10n.tip_vowelO_example,
        ),
        LoadingTip(
          category: l10n.tipCatVowel,
          title: l10n.tip_vowelUea_title,
          content: l10n.tip_vowelUea_content,
          example: l10n.tip_vowelUea_example,
        ),
        LoadingTip(
          category: l10n.tipCatVowel,
          title: l10n.tip_vowelUu_title,
          content: l10n.tip_vowelUu_content,
          example: l10n.tip_vowelUu_example,
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
          category: l10n.tipCatVowel,
          title: l10n.tip_vowelShortE_title,
          content: l10n.tip_vowelShortE_content,
          example: l10n.tip_vowelShortE_example,
        ),
        LoadingTip(
          category: l10n.tipCatVowel,
          title: l10n.tip_vowelShortAe_title,
          content: l10n.tip_vowelShortAe_content,
          example: l10n.tip_vowelShortAe_example,
        ),
        LoadingTip(
          category: l10n.tipCatVowel,
          title: l10n.tip_vowelOe_title,
          content: l10n.tip_vowelOe_content,
          example: l10n.tip_vowelOe_example,
        ),
        LoadingTip(
          category: l10n.tipCatVowel,
          title: l10n.tip_vowelLength_title,
          content: l10n.tip_vowelLength_content,
          example: l10n.tip_vowelLength_example,
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
          title: l10n.tip_toneFive_title,
          content: l10n.tip_toneFive_content,
          example: l10n.tip_toneFive_example,
        ),
        LoadingTip(
          category: l10n.tipCatTone,
          title: l10n.tip_toneMaiEk_title,
          content: l10n.tip_toneMaiEk_content,
          example: l10n.tip_toneMaiEk_example,
        ),
        LoadingTip(
          category: l10n.tipCatTone,
          title: l10n.tip_toneMaiTho_title,
          content: l10n.tip_toneMaiTho_content,
          example: l10n.tip_toneMaiTho_example,
        ),
        LoadingTip(
          category: l10n.tipCatTone,
          title: l10n.tip_toneMaiTriChat_title,
          content: l10n.tip_toneMaiTriChat_content,
          example: l10n.tip_toneMaiTriChat_example,
        ),
        LoadingTip(
          category: l10n.tipCatTone,
          title: l10n.tip_toneClassRelation_title,
          content: l10n.tip_toneClassRelation_content,
        ),
        LoadingTip(
          category: l10n.tipCatTone,
          title: l10n.tip_toneMistake_title,
          content: l10n.tip_toneMistake_content,
        ),
        LoadingTip(
          category: l10n.tipCatTone,
          title: l10n.tip_toneMidExplain_title,
          content: l10n.tip_toneMidExplain_content,
          example: l10n.tip_toneMidExplain_example,
        ),
        LoadingTip(
          category: l10n.tipCatTone,
          title: l10n.tip_toneRisingExplain_title,
          content: l10n.tip_toneRisingExplain_content,
          example: l10n.tip_toneRisingExplain_example,
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
          title: l10n.tip_consonantFinal_title,
          content: l10n.tip_consonantFinal_content,
          example: l10n.tip_consonantFinal_example,
        ),
        LoadingTip(
          category: l10n.tipCatConsonant,
          title: l10n.tip_consonantAspiration_title,
          content: l10n.tip_consonantAspiration_content,
          example: l10n.tip_consonantAspiration_example,
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
          title: l10n.tip_numberClassifier_title,
          content: l10n.tip_numberClassifier_content,
          example: l10n.tip_numberClassifier_example,
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
          title: l10n.tip_dailyPolite_title,
          content: l10n.tip_dailyPolite_content,
          example: l10n.tip_dailyPolite_example,
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
      ];
}
