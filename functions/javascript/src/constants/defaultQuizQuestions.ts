/**
 * クイズ用デフォルト例文データ（頻度順位227位以内）
 *
 * 【クイズ生成の仕組み】
 * 本アプリでは毎日のタイ語復習クイズ（穴埋め4択形式）を提供している。
 * クイズの出題元は以下の2段階で決まる：
 *
 * 1. SRSベースのリアルタイム選出（優先）
 *    - generateQuiz Cloud Function呼び出し時に、ユーザーの学習履歴から
 *      SRS（間隔反復）で復習すべき例文をリアルタイムに選出する
 *    - 最大15問から5問をランダム抽出し、OpenAIで穴埋め問題・選択肢・解説を動的生成
 *
 * 2. デフォルト例文（フォールバック）
 *    - ユーザー例文がない（新規ユーザー等）または例文数が不足する場合に使用
 *    - 下記の汎用タイ語例文から不足分を補填する
 *    - ユーザーの estimated_vocab ± 10 の帯域内の単語を優先選出する
 *
 * ※ 穴埋め箇所は key_word からルールベースで生成し、選択肢・解説文は OpenAI が毎回生成する
 */
export interface DefaultSentence {
  sentence_id: string;
  thai_text: string;
  /** 発音記号（ローマ字表記） */
  pronunciation: string;
  japanese_translation: string;
  /** pronunciation の空白区切りで数えた単語数 */
  word_count: number;
  /** 穴埋め対象として優先したい単語 */
  key_word: string;
  /** key_word 単体の発音記号（クイズ正解音声表示用） */
  key_word_pronunciation: string;
  /** 出現頻度順位（freq_rank_top10000.json 準拠） */
  rank: number;
}

export interface DefaultQuizDifficulty {
  maxVocab: number;
  label: string;
}

// prompts.py の DIFFICULTY_LEVELS / _compute_length_hint と揃える。
// デフォルトクイズは LLM 生成文ではないため、同じ基準で候補を事前フィルタする。
export const DEFAULT_QUIZ_DIFFICULTY_LEVELS: DefaultQuizDifficulty[] = [
  { maxVocab: 100, label: '入門' },
  { maxVocab: 300, label: '初級' },
  { maxVocab: 600, label: '初中級' },
  { maxVocab: 1500, label: '中級' },
  { maxVocab: Number.POSITIVE_INFINITY, label: '上級' },
];

export function getDefaultQuizDifficulty(
  estimatedVocab: number,
): DefaultQuizDifficulty {
  return DEFAULT_QUIZ_DIFFICULTY_LEVELS.find(
    (level) => estimatedVocab <= level.maxVocab,
  ) ?? DEFAULT_QUIZ_DIFFICULTY_LEVELS[DEFAULT_QUIZ_DIFFICULTY_LEVELS.length - 1];
}

export function computeDefaultSentenceWordLimit(
  estimatedVocab: number,
): number | null {
  if (estimatedVocab >= 1500) return null;
  if (estimatedVocab <= 100) return 5;
  return Math.round(5 + (estimatedVocab - 100) / 1400 * 7);
}

export function isDefaultSentenceMatchingDifficulty(
  sentence: DefaultSentence,
  estimatedVocab: number,
): boolean {
  const difficulty = getDefaultQuizDifficulty(estimatedVocab);
  if (sentence.rank > difficulty.maxVocab) return false;

  const wordLimit = computeDefaultSentenceWordLimit(estimatedVocab);
  return wordLimit === null || sentence.word_count <= wordLimit;
}

function countWordsFromPronunciation(pronunciation: string): number {
  return pronunciation.trim().split(/\s+/).filter(Boolean).length;
}

type DefaultSentenceTemplate = Omit<
  DefaultSentence,
  | 'sentence_id'
  | 'word_count'
  | 'key_word'
  | 'key_word_pronunciation'
  | 'rank'
>;

interface DefaultSentenceGroup {
  key_word: string;
  /** key_word 単体の発音記号 */
  key_word_pronunciation: string;
  /** 出現頻度順位 */
  rank: number;
  sentences: DefaultSentenceTemplate[];
}

/**
 * 頻度順位1位〜30位は高密度、その先は数語おきに key_word を選出する。
 * 例文・クイズともに estimated_vocab ± 10 帯域で使う前提のため、
 * 初期帯域は欠番を作らず密に持つ。
 * 出現頻度順位は scripts/corpus/freq_rank_top10000.json を参照。
 */
const DEFAULT_SENTENCE_GROUPS: DefaultSentenceGroup[] = [
  // ============================================================
  // Rank 1–100: 高頻度語
  // ============================================================
  {
    key_word: 'ฉัน',
    key_word_pronunciation: 'chǎn',
    rank: 1,
    sentences: [
      {
        thai_text: 'ฉันชอบกินส้มตำ',
        pronunciation: 'chǎn chɔ̂ɔp kin sôm-tam',
        japanese_translation: '私はソムタムが好きです',
      },
    ],
  },
  {
    key_word: 'ไม่',
    key_word_pronunciation: 'mâi',
    rank: 2,
    sentences: [
      {
        thai_text: 'วันนี้ไม่ร้อน',
        pronunciation: 'wan-níi mâi rɔ́ɔn',
        japanese_translation: '今日は暑くないです',
      },
    ],
  },
  {
    key_word: 'จะ',
    key_word_pronunciation: 'jà',
    rank: 3,
    sentences: [
      {
        thai_text: 'พรุ่งนี้จะไปตลาด',
        pronunciation: 'phrûng-níi jà pai talàat',
        japanese_translation: '明日市場に行きます',
      },
    ],
  },
  {
    key_word: 'คุณ',
    key_word_pronunciation: 'khun',
    rank: 4,
    sentences: [
      {
        thai_text: 'คุณชื่ออะไร',
        pronunciation: 'khun chʉ̂ʉ à-rai',
        japanese_translation: 'あなたの名前は何ですか',
      },
    ],
  },
  {
    key_word: 'ที่',
    key_word_pronunciation: 'thîi',
    rank: 5,
    sentences: [
      {
        thai_text: 'ร้านที่อยู่ใกล้บ้าน',
        pronunciation: 'ráan thîi yùu klâi bâan',
        japanese_translation: '家の近くにあるお店',
      },
    ],
  },
  {
    key_word: 'ได้',
    key_word_pronunciation: 'dâai',
    rank: 6,
    sentences: [
      {
        thai_text: 'คุณพูดไทยได้ไหม',
        pronunciation: 'khun phûut thai dâai mǎi',
        japanese_translation: 'タイ語を話せますか',
      },
    ],
  },
  {
    key_word: 'ไป',
    key_word_pronunciation: 'pai',
    rank: 7,
    sentences: [
      {
        thai_text: 'เราไปกินข้าวกัน',
        pronunciation: 'rao pai kin khâao kan',
        japanese_translation: '一緒にご飯を食べに行きましょう',
      },
    ],
  },
  {
    key_word: 'เธอ',
    key_word_pronunciation: 'thəə',
    rank: 8,
    sentences: [
      {
        thai_text: 'เธอชอบกินมะม่วง',
        pronunciation: 'thəə chɔ̂ɔp kin má-mûang',
        japanese_translation: '彼女はマンゴーを食べるのが好きです',
      },
    ],
  },
  {
    key_word: 'มัน',
    key_word_pronunciation: 'man',
    rank: 9,
    sentences: [
      {
        thai_text: 'อาหารมันอร่อยมาก',
        pronunciation: 'aa-hǎan man à-rɔ̀i mâak',
        japanese_translation: '料理がとてもおいしいです',
      },
    ],
  },
  {
    key_word: 'ผม',
    key_word_pronunciation: 'phǒm',
    rank: 10,
    sentences: [
      {
        thai_text: 'ผมมาจากญี่ปุ่น',
        pronunciation: 'phǒm maa jàak yîi-pùn',
        japanese_translation: '私は日本から来ました',
      },
    ],
  },
  {
    key_word: 'ของ',
    key_word_pronunciation: 'khɔ̌ɔng',
    rank: 11,
    sentences: [
      {
        thai_text: 'นี่เป็นของขวัญ',
        pronunciation: 'nîi pen khɔ̌ɔng-khwǎn',
        japanese_translation: 'これはプレゼントです',
      },
    ],
  },
  {
    key_word: 'ว่า',
    key_word_pronunciation: 'wâa',
    rank: 12,
    sentences: [
      {
        thai_text: 'เขาบอกว่าจะมา',
        pronunciation: 'khǎo bɔ̀ɔk wâa jà maa',
        japanese_translation: '彼は来ると言いました',
      },
    ],
  },
  {
    key_word: 'แล้ว',
    key_word_pronunciation: 'lɛ́ɛw',
    rank: 13,
    sentences: [
      {
        thai_text: 'ฉันกินข้าวแล้ว',
        pronunciation: 'chǎn kin khâao lɛ́ɛo',
        japanese_translation: '私はもうご飯を食べました',
      },
    ],
  },
  {
    key_word: 'เป็น',
    key_word_pronunciation: 'pen',
    rank: 14,
    sentences: [
      {
        thai_text: 'พี่ชายเป็นคนใจดี',
        pronunciation: 'phîi-chaai pen khon jai-dii',
        japanese_translation: '兄は親切な人です',
      },
    ],
  },
  {
    key_word: 'อะไร',
    key_word_pronunciation: 'à-rai',
    rank: 15,
    sentences: [
      {
        thai_text: 'คุณกำลังทำอะไรอยู่',
        pronunciation: 'khun kam-lang tham à-rai yùu',
        japanese_translation: '何をしているんですか',
      },
    ],
  },
  {
    key_word: 'ก็',
    key_word_pronunciation: 'kɔ̂ɔ',
    rank: 16,
    sentences: [
      {
        thai_text: 'ฉันก็อยากไปเหมือนกัน',
        pronunciation: 'chǎn kɔ̂ɔ yàak pai mʉ̌an-kan',
        japanese_translation: '私も行きたいです',
      },
    ],
  },
  {
    key_word: 'เรา',
    key_word_pronunciation: 'raw',
    rank: 17,
    sentences: [
      {
        thai_text: 'เราไปตลาดด้วยกัน',
        pronunciation: 'rao pai talàat dûai-kan',
        japanese_translation: '私たちは一緒に市場へ行きます',
      },
    ],
  },
  {
    key_word: 'มี',
    key_word_pronunciation: 'mii',
    rank: 18,
    sentences: [
      {
        thai_text: 'ห้องนี้มีโต๊ะหนึ่งตัว',
        pronunciation: 'hɔ̂ng níi mii tó nʉ̀ng tua',
        japanese_translation: 'この部屋には机が一つあります',
      },
    ],
  },
  {
    key_word: 'เขา',
    key_word_pronunciation: 'khǎo',
    rank: 19,
    sentences: [
      {
        thai_text: 'เขามาจากเชียงใหม่',
        pronunciation: 'khǎo maa jàak chiang-mài',
        japanese_translation: '彼はチェンマイから来ました',
      },
    ],
  },
  {
    key_word: 'มา',
    key_word_pronunciation: 'maa',
    rank: 20,
    sentences: [
      {
        thai_text: 'เพื่อนจะมาหาเย็นนี้',
        pronunciation: 'phʉ̂an jà maa hǎa yen níi',
        japanese_translation: '友だちが今晩会いに来ます',
      },
    ],
  },
  {
    key_word: 'ให้',
    key_word_pronunciation: 'hâi',
    rank: 21,
    sentences: [
      {
        thai_text: 'ช่วยเปิดประตูให้หน่อย',
        pronunciation: 'chûai pə̀ət pràtuu hâi nɔ̀i',
        japanese_translation: 'ドアを開けてもらえますか',
      },
    ],
  },
  {
    key_word: 'อยู่',
    key_word_pronunciation: 'yùu',
    rank: 22,
    sentences: [
      {
        thai_text: 'แม่อยู่ที่บ้าน',
        pronunciation: 'mɛ̂ɛ yùu thîi bâan',
        japanese_translation: '母は家にいます',
      },
    ],
  },
  {
    key_word: 'กับ',
    key_word_pronunciation: 'kàp',
    rank: 23,
    sentences: [
      {
        thai_text: 'ฉันไปคาเฟ่กับเพื่อน',
        pronunciation: 'chǎn pai khaa-fɛ̂ɛ kàp phʉ̂an',
        japanese_translation: '私は友だちとカフェに行きます',
      },
    ],
  },
  {
    key_word: 'นี่',
    key_word_pronunciation: 'nîi',
    rank: 24,
    sentences: [
      {
        thai_text: 'นี่คือหนังสือของฉัน',
        pronunciation: 'nîi khʉʉ năng-sʉ̌ʉ khɔ̌ɔng chǎn',
        japanese_translation: 'これは私の本です',
      },
    ],
  },
  {
    key_word: 'เลย',
    key_word_pronunciation: 'ləəi',
    rank: 25,
    sentences: [
      {
        thai_text: 'วันนี้อากาศดีเลยออกไปเดินเล่น',
        pronunciation: 'wan-níi aa-kàat dii ləəi ɔ̀ɔk pai dəən-lên',
        japanese_translation: '今日は天気がいいので散歩に出かけます',
      },
    ],
  },
  {
    key_word: 'ใน',
    key_word_pronunciation: 'nai',
    rank: 26,
    sentences: [
      {
        thai_text: 'แมวอยู่ในกล่อง',
        pronunciation: 'mɛɛo yùu nai klɔ̀ng',
        japanese_translation: '猫は箱の中にいます',
      },
    ],
  },
  {
    key_word: 'ทำ',
    key_word_pronunciation: 'tham',
    rank: 27,
    sentences: [
      {
        thai_text: 'แม่ทำกับข้าวอยู่ในครัว',
        pronunciation: 'mɛ̂ɛ tham kàp-khâao yùu nai khrua',
        japanese_translation: '母は台所で料理をしています',
      },
    ],
  },
  {
    key_word: 'ใช่',
    key_word_pronunciation: 'châi',
    rank: 28,
    sentences: [
      {
        thai_text: 'นี่ใช่กระเป๋าของคุณไหม',
        pronunciation: 'nîi châi grà-pǎo khɔ̌ɔng khun mǎi',
        japanese_translation: 'これはあなたのかばんですか',
      },
    ],
  },
  {
    key_word: 'และ',
    key_word_pronunciation: 'lɛ́',
    rank: 29,
    sentences: [
      {
        thai_text: 'ฉันชอบชาและกาแฟ',
        pronunciation: 'chǎn chɔ̂ɔp chaa lɛ́ gaa-fɛɛ',
        japanese_translation: '私はお茶とコーヒーが好きです',
      },
    ],
  },
  {
    key_word: 'ต้อง',
    key_word_pronunciation: 'tɔ̂ɔng',
    rank: 30,
    sentences: [
      {
        thai_text: 'เราต้องไปตอนเช้า',
        pronunciation: 'rao tɔ̂ɔng pai tɔɔn cháao',
        japanese_translation: '私たちは朝に行かなければなりません',
      },
    ],
  },
  {
    key_word: 'ด้วย',
    key_word_pronunciation: 'dûuai',
    rank: 38,
    sentences: [
      {
        thai_text: 'ฉันอยากไปด้วย',
        pronunciation: 'chǎn yàak pai dûuai',
        japanese_translation: '私も一緒に行きたいです',
      },
    ],
  },
  {
    key_word: 'นั้น',
    key_word_pronunciation: 'nán',
    rank: 41,
    sentences: [
      {
        thai_text: 'ร้านอาหารนั้นอร่อยมาก',
        pronunciation: 'ráan aa-hǎan nán à-ròi mâak',
        japanese_translation: 'あのレストランはとてもおいしいです',
      },
    ],
  },
  {
    key_word: 'เรื่อง',
    key_word_pronunciation: 'rʉ̂ʉang',
    rank: 45,
    sentences: [
      {
        thai_text: 'เรื่องนี้สำคัญมาก',
        pronunciation: 'rʉ̂ʉang níi sǎm-khan mâak',
        japanese_translation: 'この件はとても重要です',
      },
    ],
  },
  {
    key_word: 'ทำไม',
    key_word_pronunciation: 'tham-mai',
    rank: 46,
    sentences: [
      {
        thai_text: 'ทำไมคุณมาสาย',
        pronunciation: 'tham-mai khun maa sǎai',
        japanese_translation: 'なぜ遅刻したんですか',
      },
    ],
  },
  {
    key_word: 'อยาก',
    key_word_pronunciation: 'yàak',
    rank: 47,
    sentences: [
      {
        thai_text: 'ฉันอยากกินมะม่วง',
        pronunciation: 'chǎn yàak kin má-mûang',
        japanese_translation: '私はマンゴーを食べたいです',
      },
    ],
  },
  {
    key_word: 'นั่น',
    key_word_pronunciation: 'nân',
    rank: 49,
    sentences: [
      {
        thai_text: 'นั่นคือร้านอะไร',
        pronunciation: 'nân khʉʉ ráan à-rai',
        japanese_translation: 'あれは何のお店ですか',
      },
    ],
  },
  {
    key_word: 'เจ้า',
    key_word_pronunciation: 'jâo',
    rank: 58,
    sentences: [
      {
        thai_text: 'เจ้าของร้านใจดีมาก',
        pronunciation: 'jâo khɔ̌ɔng ráan jai-dii mâak',
        japanese_translation: 'お店のオーナーはとても親切です',
      },
    ],
  },
  {
    key_word: 'อย่าง',
    key_word_pronunciation: 'yàang',
    rank: 60,
    sentences: [
      {
        thai_text: 'ทำอย่างนี้ถูกไหม',
        pronunciation: 'tham yàang níi thùuk mǎi',
        japanese_translation: 'このようにやるのは正しいですか',
      },
    ],
  },
  {
    key_word: 'ท่าน',
    key_word_pronunciation: 'thân',
    rank: 65,
    sentences: [
      {
        thai_text: 'ท่านต้องการอะไรครับ',
        pronunciation: 'thân tɔ̂ɔng-kaan à-rai khráp',
        japanese_translation: '何をお求めですか',
      },
    ],
  },
  {
    key_word: 'หรือ',
    key_word_pronunciation: 'rʉ̌ʉ',
    rank: 67,
    sentences: [
      {
        thai_text: 'คุณจะดื่มน้ำหรือกาแฟ',
        pronunciation: 'khun jà dʉ̀ʉm náam rʉ̌ʉ kaa-fɛɛ',
        japanese_translation: '水とコーヒーどちらにしますか',
      },
    ],
  },
  {
    key_word: 'งั้น',
    key_word_pronunciation: 'ngán',
    rank: 69,
    sentences: [
      {
        thai_text: 'งั้นเราไปกันเลย',
        pronunciation: 'ngán rao pai kan ləəi',
        japanese_translation: 'じゃあ行きましょう',
      },
    ],
  },
  {
    key_word: 'กำลัง',
    key_word_pronunciation: 'kam-lang',
    rank: 70,
    sentences: [
      {
        thai_text: 'เขากำลังกินข้าว',
        pronunciation: 'khǎo kam-lang kin khâao',
        japanese_translation: '彼はご飯を食べているところです',
      },
    ],
  },
  {
    key_word: 'พวกเขา',
    key_word_pronunciation: 'phûuak-khǎw',
    rank: 71,
    sentences: [
      {
        thai_text: 'พวกเขาจะมาพรุ่งนี้',
        pronunciation: 'phûak-khǎo jà maa phrûng-níi',
        japanese_translation: '彼らは明日来ます',
      },
    ],
  },
  {
    key_word: 'ที่นี่',
    key_word_pronunciation: 'thîi-nîi',
    rank: 72,
    sentences: [
      {
        thai_text: 'ที่นี่มีอาหารอร่อย',
        pronunciation: 'thîi-nîi mii aa-hǎan à-ròi',
        japanese_translation: 'ここにはおいしい食べ物があります',
      },
    ],
  },
  {
    key_word: 'ยังไง',
    key_word_pronunciation: 'yang-ngai',
    rank: 73,
    sentences: [
      {
        thai_text: 'ไปสนามบินยังไง',
        pronunciation: 'pai sà-nǎam-bin yang-ngai',
        japanese_translation: '空港にはどうやって行きますか',
      },
    ],
  },
  {
    key_word: 'เห็น',
    key_word_pronunciation: 'hěn',
    rank: 75,
    sentences: [
      {
        thai_text: 'คุณเห็นแมวตัวนั้นไหม',
        pronunciation: 'khun hěn mɛɛo tua nán mǎi',
        japanese_translation: 'あの猫が見えますか',
      },
    ],
  },
  {
    key_word: 'กว่า',
    key_word_pronunciation: 'kwàa',
    rank: 76,
    sentences: [
      {
        thai_text: 'วันนี้ร้อนกว่าเมื่อวาน',
        pronunciation: 'wan-níi rɔ́ɔn kwàa mʉ̂a-waan',
        japanese_translation: '今日は昨日より暑いです',
      },
    ],
  },
  {
    key_word: 'ทำให้',
    key_word_pronunciation: 'tham-hâi',
    rank: 77,
    sentences: [
      {
        thai_text: 'ฝนทำให้ถนนลื่น',
        pronunciation: 'fǒn tham-hâi thà-nǒn lʉ̂ʉn',
        japanese_translation: '雨で道路が滑りやすくなりました',
      },
    ],
  },
  {
    key_word: 'อย่า',
    key_word_pronunciation: 'yàa',
    rank: 79,
    sentences: [
      {
        thai_text: 'อย่าลืมเอาร่มไป',
        pronunciation: 'yàa lʉʉm ao rôm pai',
        japanese_translation: '傘を持っていくのを忘れないで',
      },
    ],
  },
  {
    key_word: 'ที่จะ',
    key_word_pronunciation: 'thîi-jà',
    rank: 80,
    sentences: [
      {
        thai_text: 'ฉันมีเวลาที่จะพักผ่อน',
        pronunciation: 'chǎn mii wee-laa thîi-jà phák-phɔ̀ɔn',
        japanese_translation: '私は休む時間があります',
      },
    ],
  },
  {
    key_word: 'ตอนนี้',
    key_word_pronunciation: 'tɔɔn-níi',
    rank: 82,
    sentences: [
      {
        thai_text: 'ตอนนี้ฝนตกหนัก',
        pronunciation: 'tɔɔn-níi fǒn tòk nàk',
        japanese_translation: '今、雨がひどく降っています',
      },
    ],
  },
  {
    key_word: 'เพราะ',
    key_word_pronunciation: 'phrɔ́',
    rank: 83,
    sentences: [
      {
        thai_text: 'ฉันไม่ไปเพราะฝนตก',
        pronunciation: 'chǎn mâi pai phrɔ́ fǒn tòk',
        japanese_translation: '雨が降っているので行きません',
      },
    ],
  },
  {
    key_word: 'หรอก',
    key_word_pronunciation: 'rɔ̀ɔk',
    rank: 84,
    sentences: [
      {
        thai_text: 'ไม่เป็นไรหรอก',
        pronunciation: 'mâi pen rai rɔ̀ɔk',
        japanese_translation: '大丈夫だよ、気にしないで',
      },
    ],
  },
  {
    key_word: 'สิ่ง',
    key_word_pronunciation: 'sìng',
    rank: 85,
    sentences: [
      {
        thai_text: 'สิ่งที่สำคัญคือครอบครัว',
        pronunciation: 'sìng thîi sǎm-khan khʉʉ khrɔ̂ɔp-khrua',
        japanese_translation: '大切なものは家族です',
      },
    ],
  },
  {
    key_word: 'ช่วย',
    key_word_pronunciation: 'chûuai',
    rank: 87,
    sentences: [
      {
        thai_text: 'ช่วยถือกระเป๋าให้หน่อย',
        pronunciation: 'chûai thʉ̌ʉ krà-pǎo hâi nɔ̀i',
        japanese_translation: 'カバンを持ってもらえますか',
      },
    ],
  },
  {
    key_word: 'จริงๆ',
    key_word_pronunciation: 'jing-jing',
    rank: 88,
    sentences: [
      {
        thai_text: 'อาหารที่นี่อร่อยจริงๆ',
        pronunciation: 'aa-hǎan thîi-nîi à-ròi jing-jing',
        japanese_translation: 'ここの料理は本当においしいです',
      },
    ],
  },
  {
    key_word: 'ต้องการ',
    key_word_pronunciation: 'tɔ̂ɔng-kaan',
    rank: 89,
    sentences: [
      {
        thai_text: 'คุณต้องการความช่วยเหลือไหม',
        pronunciation: 'khun tɔ̂ɔng-kaan khwaam-chûai-lʉ̌a mǎi',
        japanese_translation: '助けが必要ですか',
      },
    ],
  },
  {
    key_word: 'ก่อน',
    key_word_pronunciation: 'kɔ̀ɔn',
    rank: 95,
    sentences: [
      {
        thai_text: 'ล้างมือก่อนกินข้าว',
        pronunciation: 'láang mʉʉ kɔ̀ɔn kin khâao',
        japanese_translation: 'ご飯を食べる前に手を洗いなさい',
      },
    ],
  },
  {
    key_word: 'ชั้น',
    key_word_pronunciation: 'chán',
    rank: 96,
    sentences: [
      {
        thai_text: 'ห้องอยู่ชั้นสาม',
        pronunciation: 'hɔ̂ng yùu chán sǎam',
        japanese_translation: '部屋は3階にあります',
      },
    ],
  },
  {
    key_word: 'เพื่อ',
    key_word_pronunciation: 'phʉ̂ʉa',
    rank: 97,
    sentences: [
      {
        thai_text: 'ฉันมาเพื่อกินข้าว',
        pronunciation: 'chǎn maa phʉ̂a kin khâao',
        japanese_translation: '私はご飯を食べるために来ました',
      },
    ],
  },
  {
    key_word: 'ขึ้น',
    key_word_pronunciation: 'khʉ̂n',
    rank: 98,
    sentences: [
      {
        thai_text: 'ราคาข้าวขึ้นอีกแล้ว',
        pronunciation: 'raa-khaa khâao khʉ̂n ìik lɛ́ɛo',
        japanese_translation: 'お米の値段がまた上がりました',
      },
    ],
  },
  {
    key_word: 'พวกเรา',
    key_word_pronunciation: 'phûuak-raw',
    rank: 99,
    sentences: [
      {
        thai_text: 'พวกเราไปเที่ยวทะเลกัน',
        pronunciation: 'phûak-rao pai thîao thá-lee kan',
        japanese_translation: '私たちは一緒に海へ遊びに行きます',
      },
    ],
  },
  {
    key_word: 'หน่อย',
    key_word_pronunciation: 'nɔ̀ɔi',
    rank: 107,
    sentences: [
      {
        thai_text: 'รอหน่อยนะครับ',
        pronunciation: 'rɔɔ nɔ̀i ná khráp',
        japanese_translation: 'ちょっと待ってくださいね',
      },
    ],
  },
  {
    key_word: 'ขอโทษ',
    key_word_pronunciation: 'khɔ̌ɔ-thôot',
    rank: 108,
    sentences: [
      {
        thai_text: 'ขอโทษที่มาสาย',
        pronunciation: 'khɔ̌ɔ-thôot thîi maa sǎai',
        japanese_translation: '遅れてすみません',
      },
    ],
  }
];

export const DEFAULT_SENTENCES: DefaultSentence[] = DEFAULT_SENTENCE_GROUPS.flatMap((group, groupIndex) =>
  group.sentences.map((sentence, sentenceIndex) => ({
    sentence_id: `default_${groupIndex + 1}_${sentenceIndex + 1}`,
    key_word: group.key_word,
    key_word_pronunciation: group.key_word_pronunciation,
    rank: group.rank,
    word_count: countWordsFromPronunciation(sentence.pronunciation),
    ...sentence,
  }))
);
