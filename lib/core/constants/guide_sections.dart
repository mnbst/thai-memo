/// ガイド画面の節。コツ問題の解答から、出題元の節を開いて見せるのに使う。
///
/// 発音ガイドの節は pronunciationSections の添字、語順ガイドの項目は
/// wordOrderRules の添字で指す（どちらもデータの並びがそのまま画面の並び）。
/// 声調・タイ文字ガイドは画面に直接組んであるので、ここで名前を付ける。
library;

/// 発音ガイドの「読みの記号」カード。pronunciationSections には入っていない。
const int pronSymbolsSection = -1;

enum ToneGuideSection { fiveTones, consonantClasses, toneMarks, syllableTypes, shiftTable }

enum ThaiScriptGuideSection { basics, consonants, vowels, toneMarks, words }
