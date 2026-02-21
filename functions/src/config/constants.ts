// ApiConstants.dart から移植
export const STYLES = [
  'ニュース記事体（客観的・フォーマルな報道文体）',
  '口語体（友達同士のカジュアルな話し言葉）',
  '丁寧語（フォーマルな敬語・丁寧な表現）',
  'SNS・テキストメッセージ（略語・絵文字・短い表現）',
  '物語・文学体（描写的・書き言葉的な表現）',
];

export const TOPICS = [
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

export const POLITENESS_LEVELS = [
  'フォーマル（丁寧語・敬語を使用）',
  'カジュアル（くだけた友達同士の表現）',
  '中立（一般的な日常表現）',
];

export const GRAMMAR_FOCUSES = [
  '疑問文（〜ไหม？〜มั้ย？など）',
  '否定文（ไม่〜、ไม่ได้〜など）',
  '条件文（ถ้า〜、หาก〜など）',
  '比較表現（กว่า、เหมือนなど）',
  '命令・依頼（〜นะ、〜ด้วยなど）',
  '可能表現（ได้、เป็นなど）',
  '過去・完了（แล้ว、เคยなど）',
  '助詞・接続詞（แต่、และ、หรือなど）',
];

export const VOCAB_LEVELS = [
  '初級（基本的な日常語彙のみ）',
  '中級（日常会話レベルの語彙）',
  '上級（やや専門的・慣用的な語彙）',
];

export const SENTENCE_LENGTHS = [
  '短文（5〜8単語）',
  '中文（9〜12単語）',
  '長文（13〜18単語）',
];

export const EMOTIONS = [
  '喜び・嬉しさ',
  '悲しみ・落ち込み',
  '驚き',
  '不安・心配',
  '感謝',
  '期待・楽しみ',
  '中立・平静',
];

export const LEARNING_PURPOSES = [
  '会話練習（実際に話せる表現の習得）',
  '語彙習得（新しい単語の導入）',
  '文法理解（文法パターンの習得）',
  '文化理解（タイ文化・習慣の学習）',
];

export const TONE_DENSITIES = [
  '低（同じ声調が多め・声調バリエーション少なめ）',
  '中（複数の声調をバランスよく含む）',
  '高（5種類の声調をまんべんなく含む・声調練習向け）',
];

export const GEMINI_MODEL = 'gemini-2.5-flash';
export const API_TEMPERATURE = 0.8;
export const API_MAX_TOKENS = 8192; // Increased from 6144 to handle longer responses

export interface SentenceGenerationParams {
  topic: string;
  style: string;
  politeness: string;
  grammarFocus: string;
  vocabLevel: string;
  sentenceLength: string;
  emotion: string;
  learningPurpose: string;
  toneDensity: string;
}

export function getSentenceGenerationPrompt(params: SentenceGenerationParams): string {
  const {
    topic,
    style,
    politeness,
    grammarFocus,
    vocabLevel,
    sentenceLength,
    emotion,
    learningPurpose,
    toneDensity,
  } = params;
  return `あなたは日本語話者向けに日々の練習文を作るタイ語教師です。

学習に必要な情報を含むタイ語の新しい文を1つ、JSON形式で生成してください。

要件:
1. 文は実用的な内容にする
2. 今回のトピック: ${topic}
3. 文体スタイル: ${style}
4. 丁寧さのレベル: ${politeness}
5. 文法フォーカス: ${grammarFocus}
6. 語彙レベル: ${vocabLevel}
7. 文の長さ: ${sentenceLength}
8. 感情・トーン: ${emotion}
9. 学習目的: ${learningPurpose}
10. 声調密度: ${toneDensity}
11. 単語分解は最大15単語まで
12. contextの各フィールドは簡潔に（各50文字以内）

重要：音節分割について
- 各単語を声調ルールが適用される語のまとまり単位で分割してください
- 発音には反映されない文字（先頭のอ、หなど）も、その音節のtextに含めてください
- 真の二重頭子音（กร, กล, กว, ขร, ขล, ขว, คร, คล, คว, ปร, ปล, ผล, พร, พล, ตร等）を含む音節は1つの要素として分割しないでください
- 二重頭子音に見えるが実際は2音節に分かれるパターン（สม, ตม等）も、声調ルールの適用単位として1つの要素にまとめてください：
  - 例: สมุด → [สมุด]（sa-mùt, 1要素）
  - 例: สมัย → [สมัย]（sa-mǎi, 1要素）
- 例: สวัสดี → [สวัส, ดี]（2要素）
- 例: คำตอบ → [คำ, ตอบ]（2要素）
- 例: ใช้ชีวิต → [ใช้, ชี, วิต]（3要素）
- 例: อยาก → [อยาก]（1要素。先頭のอは発音されないがtextに含める）
- 例: กรุง → [กรุง]（1要素。กรは真の二重頭子音）
- 例: ประเทศ → [ประ, เทศ]（2要素。ปรは真の二重頭子音なので1要素内に保持）

次の形式の有効なJSONのみを返してください:

{
  "thai_text": "タイ語の文",
  "pronunciation": "拼音風のローマ字発音（声調記号付き）(e.g., ไม่รู้สิ = mâi rúu sì, เหมือนกัน = mʉ̌ʉan kan, สุดท้าย = sùt-tháai, คำตอบ = kham-tɔ̀ɔp, ใช้ชีวิต = chái-chii-wít, ให้รู้ตัว = hâi rúu tua, ไม่ค่อย = mâi khâui, ก็ = kô, แหละ = lɛ̀)",
  "japanese_translation": "日本語訳",
  "word_breakdown": [
    {
      "word": "タイ語の単語",
      "pronunciation": "単語の拼音風発音（声調記号付きローマ字）",
      "meaning": "単語の日本語の意味",
      "grammatical_role": "品詞（例: 名詞, 動詞, 形容詞, 助詞）",
      "syllables": ["音節テキスト1", "音節テキスト2"]
    }
  ],
  "context": {
    "topic": "この表現を使う場面・場所",
    "style": "実際に使用した文体スタイル（例: ニュース記事体、口語体など）",
    "emotion": "感情・トーン（フォーマル/カジュアル/丁寧/親しみ）",
    "usage_scenarios": "具体的に使えるシチュエーション",
    "cultural_notes": "文化的背景やニュアンス"
  }
}`;
}
