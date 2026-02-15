// ApiConstants.dart から移植
export const SITUATIONS = [
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
];

export const GEMINI_MODEL = 'gemini-2.5-flash';
export const API_TEMPERATURE = 0.8;
export const API_MAX_TOKENS = 8192; // Increased from 6144 to handle longer responses

export function getSentenceGenerationPrompt(situation: string): string {
  return `あなたは日本語話者向けに日々の練習文を作るタイ語教師です。

学習に必要な情報を含むタイ語の新しい文を1つ、JSON形式で生成してください。

要件:
1. 文は日常会話で実用的な内容にする
2. 難易度は中級（簡単すぎず難しすぎない）
3. タイ語の文は10〜15単語以内に収める（長文は避ける）
4. 単語分解は最大15単語まで
5. contextの各フィールドは簡潔に（各50文字以内）
6. 今回の話題・シチュエーション: ${situation}

重要：音節分割について
- 各単語を正しくタイ語の音節に分割してください
- 音節は必ず頭子音から始まります（母音のみの音節の場合、อが黙字の頭子音）
- 例: สวัสดี → [สวัส, ดี]（2音節）
- 例: คำตอบ → [คำ, ตอบ]（2音節）
- 例: ใช้ชีวิต → [ใช้, ชี, วิต]（3音節）

各音節について以下を必ず含めてください：
1. tone_mark（声調記号）: 音節に付いている声調記号を確認し、none/maiEk/maiTho/maiTri/maiChattawaのいずれかを指定（記号がない場合はnone）
2. syllable_type（音節タイプ）:
   - live（生音節）: 長母音、または-m,-n,-ng,-y,-wで終わる
   - dead（死音節）: 短母音で末子音なし、または-p,-t,-kで終わる

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
      "syllables": [
        {
          "text": "音節テキスト",
          "initial_consonant": "頭子音",
          "consonant_class": "high | middle | low",
          "tone": "mid | low | falling | high | rising",
          "tone_mark": "none | maiEk | maiTho | maiTri | maiChattawa",
          "syllable_type": "live | dead"
        }
      ]
    }
  ],
  "context": {
    "situation": "この表現を使う場面・場所",
    "emotion": "感情・トーン（フォーマル/カジュアル/丁寧/親しみ）",
    "usage_scenarios": "具体的に使えるシチュエーション",
    "cultural_notes": "文化的背景やニュアンス"
  }
}

今すぐ重複しない新しい文を生成してください。`;
}
