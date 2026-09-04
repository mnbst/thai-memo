import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

const int freeVocabScoreLimit = 100;

/// プレミアムで到達しうる語彙スコアの目安。上限ではなく案内用の概算値。
const int premiumVocabScoreGuide = 10000;


/// 語彙レベルの識別子。prefs に保存され `_thresholdForLevel` の判定にも使うため
/// 日本語のまま変えない。表示には [vocabLevelLabel] を使うこと。
String vocabLevel(int vocab) {
  if (vocab < 100) return '入門';
  if (vocab < 300) return '初級';
  if (vocab < 600) return '初中級';
  if (vocab < 1500) return '中級';
  return '上級';
}

/// 語彙レベル識別子の表示ラベル。
String vocabLevelLabel(L10n l10n, String level) => switch (level) {
      '初級' => l10n.vocabLevelBeginner,
      '初中級' => l10n.vocabLevelUpperBeginner,
      '中級' => l10n.vocabLevelIntermediate,
      '上級' => l10n.vocabLevelAdvanced,
      _ => l10n.vocabLevelIntro,
    };

/// 語彙レベルの目印。芽 → 葉 → 花 → 木 → 森 と育つ順に並べる。
///
/// 5段を1つの筋で見せたいので、全部を同じ比喩から取る。段ごとに別の比喩
/// （葉・トロフィー・星…）を混ぜると、並べたときに順序が読めない。
IconData vocabLevelIcon(String level) => switch (level) {
      '初級' => Icons.eco,
      '初中級' => Icons.local_florist,
      '中級' => Icons.park,
      '上級' => Icons.forest,
      _ => Icons.grass,
    };

