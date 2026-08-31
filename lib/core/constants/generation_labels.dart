import '../../l10n/app_localizations.dart';

/// テーマの表示用ラベル。
///
/// `GenerationConstants.topics` の値はサーバーへ送る識別子であり、プロンプトにも
/// そのまま入るので日本語のまま変えない。表示だけをここで差し替える。
class TopicLabel {
  const TopicLabel(this.name, this.sub);

  /// 括弧の前の名称（「旅行」）
  final String name;

  /// 括弧の中身（「ホテル、道案内、…」）。無ければ空文字。
  final String sub;
}

/// 識別子（括弧の前の名称）→ ARB のキー接尾辞。
const _topicKeys = {
  'タイBLドラマ': 'blDrama',
  '恋愛・男女関係': 'romance',
  '仕事': 'work',
  'あいさつ': 'greetings',
  '食べ物': 'food',
  '旅行': 'travel',
  '家族': 'family',
  '買い物': 'shopping',
  '交通': 'transport',
  '健康': 'health',
  '天気': 'weather',
  '趣味': 'hobbies',
  '学校': 'school',
  '宗教・信仰': 'religion',
  '伝統・祭り': 'festivals',
  '礼儀作法': 'etiquette',
};

/// 識別子を分解して素の名称・補足を返す（未知のテーマ用のフォールバック）。
///
/// 括弧は全角・半角の両方を見る。サーバーは英語ユーザーには英語ラベル
/// （`Work (reporting, meetings, ...)`）を返すので、全角だけを見ていると
/// 分解できず、補足まで丸ごと画面に出てしまう。
TopicLabel _rawLabel(String topic) {
  final parenIdx = _parenIndex(topic);
  if (parenIdx <= 0) return TopicLabel(topic, '');
  final inner = topic.substring(parenIdx).trim();
  return TopicLabel(
    topic.substring(0, parenIdx).trim(),
    inner.length >= 2 ? inner.substring(1, inner.length - 1) : '',
  );
}

/// 括弧の開き位置。全角「（」と半角「 (」の早い方。
int _parenIndex(String value) {
  final full = value.indexOf('（');
  final half = value.indexOf(' (');
  if (full < 0) return half;
  if (half < 0) return full;
  return full < half ? full : half;
}

/// 英語ラベルの括弧前 → ARB のキー接尾辞。
///
/// 英語ユーザーの端末にはサーバーが英語ラベルを返すので、日本語の識別子では
/// 引けない。ARB の短い名称に寄せるための対応表（表記が同じものは
/// 素の名称のまま出せるので載せない）。
const _topicKeysEN = {
  'Thai BL drama': 'blDrama',
  'Romance': 'romance',
  'Religion and faith': 'religion',
};

/// テーマ識別子を表示用ラベルに変換する。
///
/// サーバーが返す `context.topic` は生成時の識別子なので、未知の値が来たら
/// そのまま出す（訳せないより日本語で出る方がまし）。
TopicLabel topicLabel(L10n l10n, String topic) {
  final raw = _rawLabel(topic);
  final key = _topicKeys[raw.name] ?? _topicKeysEN[raw.name];
  if (key == null) return raw;
  return TopicLabel(_topicName(l10n, key), _topicSub(l10n, key));
}

String _topicName(L10n l10n, String key) => switch (key) {
      'blDrama' => l10n.topicName_blDrama,
      'romance' => l10n.topicName_romance,
      'work' => l10n.topicName_work,
      'greetings' => l10n.topicName_greetings,
      'food' => l10n.topicName_food,
      'travel' => l10n.topicName_travel,
      'family' => l10n.topicName_family,
      'shopping' => l10n.topicName_shopping,
      'transport' => l10n.topicName_transport,
      'health' => l10n.topicName_health,
      'weather' => l10n.topicName_weather,
      'hobbies' => l10n.topicName_hobbies,
      'school' => l10n.topicName_school,
      'religion' => l10n.topicName_religion,
      'festivals' => l10n.topicName_festivals,
      _ => l10n.topicName_etiquette,
    };

/// 文体識別子 → ARB のキー接尾辞。
///
/// `constants.STYLES` の値。履歴画面の集計キーなのでサーバー側は日本語のまま返す
/// （英語版のスキーマでも enum は変えていない）。表示だけここで差し替える。
/// 括弧の前だけで引く。括弧の中身は日本語の説明なので表示には使わない。
const _styleKeys = {
  'ニュース記事体': 'news',
  '口語体': 'spoken',
  '丁寧語': 'polite',
  'SNS・テキストメッセージ': 'sns',
  '物語・文学体': 'narrative',
};

/// 英語ラベルの括弧前 → ARB のキー接尾辞（[_topicKeysEN] と同じ事情）。
const _styleKeysEN = {
  'News article style': 'news',
  'Casual spoken style': 'spoken',
  'Polite style': 'polite',
  'Social media / text message style': 'sns',
  'Narrative / literary style': 'narrative',
};

/// 文体識別子を表示用ラベルに変換する。未知の値はそのまま出す。
String styleLabel(L10n l10n, String style) {
  final raw = _rawLabel(style).name;
  final key = _styleKeys[raw] ?? _styleKeysEN[raw];
  if (key == null) return raw;
  return switch (key) {
    'news' => l10n.styleName_news,
    'spoken' => l10n.styleName_spoken,
    'polite' => l10n.styleName_polite,
    'sns' => l10n.styleName_sns,
    'narrative' => l10n.styleName_narrative,
    _ => raw,
  };
}

String _topicSub(L10n l10n, String key) => switch (key) {
      'blDrama' => l10n.topicSub_blDrama,
      'romance' => l10n.topicSub_romance,
      'work' => l10n.topicSub_work,
      'greetings' => l10n.topicSub_greetings,
      'food' => l10n.topicSub_food,
      'travel' => l10n.topicSub_travel,
      'family' => l10n.topicSub_family,
      'shopping' => l10n.topicSub_shopping,
      'transport' => l10n.topicSub_transport,
      'health' => l10n.topicSub_health,
      'weather' => l10n.topicSub_weather,
      'hobbies' => l10n.topicSub_hobbies,
      'school' => l10n.topicSub_school,
      'religion' => l10n.topicSub_religion,
      'festivals' => l10n.topicSub_festivals,
      _ => l10n.topicSub_etiquette,
    };
