/// 例文生成パラメータの選択肢定義
class GenerationConstants {
  GenerationConstants._();

  static const styles = [
    'ニュース記事体（客観的・フォーマルな報道文体）',
    '口語体（友達同士のカジュアルな話し言葉）',
    '丁寧語（フォーマルな敬語・丁寧な表現）',
    'SNS・テキストメッセージ（略語・絵文字・短い表現）',
    '物語・文学体（描写的・書き言葉的な表現）',
  ];

  static const topics = [
    'あいさつ（朝、昼、夜のあいさつ、初対面、久しぶりの再会など）',
    '食べ物（レストランでの注文、料理の感想、食材の購入など）',
    '旅行（ホテル予約、道案内、観光地での会話など）',
    '感情（喜び、悲しみ、驚き、不安などの表現）',
    '仕事（職場での会話、ビジネスマナー、打ち合わせなど）',
    '家族（家族の紹介、日常会話、家族行事など）',
    '買い物（値段交渉、商品の質問、支払いなど）',
    '交通（タクシー、電車、バスでの会話）',
    '健康（病院、薬局、体調不良の説明など）',
    '天気（天気の話題、季節の挨拶など）',
    '趣味（スポーツ、音楽、映画などの趣味について）',
    '学校（授業、宿題、学校生活について）',
    '宗教・信仰（寺院訪問、お参り、托鉢、僧侶との会話、仏教行事など）',
    '伝統・祭り（ソンクラーン、ロイクラトン、王室行事、伝統儀式など）',
    '礼儀作法（ワイ（合掌）、年長者への敬意、タブー、社会的マナーなど）',
    '恋愛・男女関係（告白、デート、口説き文句、恋人同士の会話、別れなど）',
  ];

  static const politenessLevels = [
    'フォーマル（丁寧語・敬語を使用）',
    'カジュアル（くだけた友達同士の表現）',
    '中立（一般的な日常表現）',
  ];

  static const grammarFocuses = [
    '疑問文（〜ไหม？〜มั้ย？など）',
    '否定文（ไม่〜、ไม่ได้〜など）',
    '条件文（ถ้า〜、หาก〜など）',
    '比較表現（กว่า、เหมือนなど）',
    '命令・依頼（〜นะ、〜ด้วยなど）',
    '可能表現（ได้、เป็นなど）',
    '過去・完了（แล้ว、เคยなど）',
    '助詞・接続詞（แต่、และ、หรือなど）',
  ];

  static const vocabLevels = [
    '初級（基本的な日常語彙のみ）',
    '中級（日常会話レベルの語彙）',
    '上級（やや専門的・慣用的な語彙）',
  ];

  static const sentenceLengths = [
    '短文（5〜8単語）',
    '中文（9〜12単語）',
    '長文（13〜18単語）',
  ];

  static const emotions = [
    '喜び・嬉しさ',
    '悲しみ・落ち込み',
    '驚き',
    '不安・心配',
    '感謝',
    '期待・楽しみ',
    '中立・平静',
  ];

  static const learningPurposes = [
    '会話練習（実際に話せる表現の習得）',
    '語彙習得（新しい単語の導入）',
    '文法理解（文法パターンの習得）',
    '文化理解（タイ文化・習慣の学習）',
  ];

  static const toneDensities = [
    '低（同じ声調が多め・声調バリエーション少なめ）',
    '中（複数の声調をバランスよく含む）',
    '高（5種類の声調をまんべんなく含む・声調練習向け）',
  ];

  /// 自由入力パラメータのキー
  static const customPromptKey = 'customPrompt';

  /// 自由入力の最大文字数
  static const customPromptMaxLength = 20;

  /// パラメータ名とラベルの定義
  static const parameterLabels = {
    'style': 'スタイル',
    'topic': 'トピック',
    'politeness': '丁寧さ',
    'grammarFocus': '文法フォーカス',
    'vocabLevel': '語彙レベル',
    'sentenceLength': '文の長さ',
    'emotion': '感情・トーン',
    'learningPurpose': '学習目的',
    'toneDensity': '声調密度',
  };

  /// パラメータキーと選択肢のマッピング
  static const parameterOptions = {
    'style': styles,
    'topic': topics,
    'politeness': politenessLevels,
    'grammarFocus': grammarFocuses,
    'vocabLevel': vocabLevels,
    'sentenceLength': sentenceLengths,
    'emotion': emotions,
    'learningPurpose': learningPurposes,
    'toneDensity': toneDensities,
  };
}
