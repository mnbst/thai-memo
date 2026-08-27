// =============================================================================
// pronunciation_text.dart
// ローマ字発音表記のサニタイズ。
//
// サーバー側（functions/go/internal/thainlp/pronunciation.go）が扱う発音には、長母音を
// 短母音へ縮める置換の置換文字列が "\@" になっているバグがあり、出力に
// バックスラッシュが混入する（例: เบิ้ล -> "b\ə̂n"）。
// 生成側は修正済みだが、すでにローカルDBへ保存された発音には残っているため、
// 読み込み時に取り除く。バックスラッシュは正しいローマ字表記には現れない。
// =============================================================================

/// 発音表記から表示できない文字を取り除く。
String sanitizePronunciation(String pronunciation) =>
    pronunciation.contains(r'\')
        ? pronunciation.replaceAll(r'\', '')
        : pronunciation;
