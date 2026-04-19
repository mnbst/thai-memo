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
  /** 穴埋め対象として優先したい単語 */
  key_word: string;
  /** key_word 単体の発音記号（クイズ正解音声表示用） */
  key_word_pronunciation: string;
  /** 出現頻度順位（freq_rank_top10000.json 準拠） */
  rank: number;
}

type DefaultSentenceTemplate = Omit<
  DefaultSentence,
  'sentence_id' | 'key_word' | 'key_word_pronunciation' | 'rank'
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
        thai_text: 'เธอเรียนภาษาไทย',
        pronunciation: 'thəə rian phaasǎa thai',
        japanese_translation: '彼女はタイ語を勉強しています',
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
        thai_text: 'พี่ชายเป็นหมอ',
        pronunciation: 'phîi-chaai pen mǎaw',
        japanese_translation: '兄は医者です',
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
        pronunciation: 'hɔ̂ng níi mii tó núng tua',
        japanese_translation: 'この部屋には机が一つあります',
      },
    ],
  },
  {
    key_word: 'เขา',
    key_word_pronunciation: 'khǎw',
    rank: 19,
    sentences: [
      {
        thai_text: 'เขามาทำงานแต่เช้า',
        pronunciation: 'khǎo maa tham-ngaan tɛ̀ɛ cháao',
        japanese_translation: '彼は朝早くから仕事に来ました',
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
        pronunciation: 'rao tɔ̂ng pai tɔɔn cháaw',
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
        pronunciation: 'chǎn yàak pai dûai',
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
        pronunciation: 'rʉ̂ang níi sǎm-khan mâak',
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
        thai_text: 'ฉันอยากเรียนภาษาไทย',
        pronunciation: 'chǎn yàak rian phaa-sǎa thai',
        japanese_translation: '私はタイ語を勉強したいです',
      },
    ],
  },
  {
    key_word: 'นั่น',
    key_word_pronunciation: 'nân',
    rank: 49,
    sentences: [
      {
        thai_text: 'นั่นคือวัดอะไร',
        pronunciation: 'nân khʉʉ wát à-rai',
        japanese_translation: 'あれは何というお寺ですか',
      },
    ],
  },
  {
    key_word: 'เจ้า',
    key_word_pronunciation: 'jâaw',
    rank: 58,
    sentences: [
      {
        thai_text: 'เจ้าของร้านใจดีมาก',
        pronunciation: 'jâo-khɔ̌ɔng ráan jai-dii mâak',
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
        pronunciation: 'thân tɔ̂ng-kaan à-rai khráp',
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
        thai_text: 'เขากำลังอ่านหนังสือ',
        pronunciation: 'khǎo kam-lang àan nǎng-sʉ̌ʉ',
        japanese_translation: '彼は本を読んでいるところです',
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
        thai_text: 'ฉันไม่ไปเพราะไม่สบาย',
        pronunciation: 'chǎn mâi pai phrɔ́ mâi sà-baai',
        japanese_translation: '体調が悪いので行きません',
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
        pronunciation: 'mâi pen rai ràwk',
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
        thai_text: 'สิ่งที่สำคัญคือสุขภาพ',
        pronunciation: 'sìng thîi sǎm-khan khʉʉ sùk-khà-phâap',
        japanese_translation: '大切なものは健康です',
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
        pronunciation: 'khun tɔ̂ng-kaan khwaam-chûai-lʉ̌a mǎi',
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
        thai_text: 'เขาออกกำลังกายเพื่อสุขภาพ',
        pronunciation: 'khǎo ɔ̀ɔk-kam-lang-kaai phʉ̂a sùk-khà-phâap',
        japanese_translation: '彼は健康のために運動しています',
      },
    ],
  },
  {
    key_word: 'ขึ้น',
    key_word_pronunciation: 'khʉ̂n',
    rank: 98,
    sentences: [
      {
        thai_text: 'ราคาน้ำมันขึ้นอีกแล้ว',
        pronunciation: 'raa-khaa nám-man khʉ̂n ìik lɛ́ɛo',
        japanese_translation: 'ガソリンの値段がまた上がりました',
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
  },
  {
    key_word: 'สามารถ',
    key_word_pronunciation: 'sǎa-mâat',
    rank: 109,
    sentences: [
      {
        thai_text: 'คุณสามารถพูดไทยได้ไหม',
        pronunciation: 'khun sǎa-mâat phûut thai dâi mǎi',
        japanese_translation: 'タイ語を話せますか',
      },
    ],
  },
  {
    key_word: 'ขอบคุณ',
    key_word_pronunciation: 'khɔ̀ɔp-khun',
    rank: 110,
    sentences: [
      {
        thai_text: 'ขอบคุณมากสำหรับของขวัญ',
        pronunciation: 'khɔ̀ɔp-khun mâak sǎm-ràp khɔ̌ɔng-khwǎn',
        japanese_translation: 'プレゼントをどうもありがとう',
      },
    ],
  },
  {
    key_word: 'เหมือน',
    key_word_pronunciation: 'mʉ̌ʉan',
    rank: 114,
    sentences: [
      {
        thai_text: 'ลูกสาวหน้าเหมือนแม่',
        pronunciation: 'lûuk-sǎao nâa mʉ̌an mɛ̂ɛ',
        japanese_translation: '娘は母親に顔が似ています',
      },
    ],
  },
  {
    key_word: 'สำหรับ',
    key_word_pronunciation: 'sǎm-ràp',
    rank: 117,
    sentences: [
      {
        thai_text: 'ที่นั่งนี้สำหรับผู้สูงอายุ',
        pronunciation: 'thîi-nâng níi sǎm-ràp phûu-sǔung-aa-yú',
        japanese_translation: 'この席はお年寄り用です',
      },
    ],
  },
  {
    key_word: 'แบบนี้',
    key_word_pronunciation: 'bɛ̀ɛp-níi',
    rank: 120,
    sentences: [
      {
        thai_text: 'ฉันชอบอากาศแบบนี้',
        pronunciation: 'chǎn chɔ̂ɔp aa-kàat bɛ̀ɛp-níi',
        japanese_translation: '私はこういう天気が好きです',
      },
    ],
  },
  {
    key_word: 'เกิด',
    key_word_pronunciation: 'kə̀ət',
    rank: 122,
    sentences: [
      {
        thai_text: 'เธอเกิดที่เชียงใหม่',
        pronunciation: 'thəə kə̀ət thîi chiang-mài',
        japanese_translation: '彼女はチェンマイで生まれました',
      },
    ],
  },
  {
    key_word: 'รู้สึก',
    key_word_pronunciation: 'rúu-sʉ̀k',
    rank: 124,
    sentences: [
      {
        thai_text: 'วันนี้ฉันรู้สึกดีมาก',
        pronunciation: 'wan-níi chǎn rúu-sʉ̀k dii mâak',
        japanese_translation: '今日はとても気分がいいです',
      },
    ],
  },
  {
    key_word: 'เข้าใจ',
    key_word_pronunciation: 'khâw-jai',
    rank: 126,
    sentences: [
      {
        thai_text: 'คุณเข้าใจที่ฉันพูดไหม',
        pronunciation: 'khun khâo-jai thîi chǎn phûut mǎi',
        japanese_translation: '私の言ったことが分かりますか',
      },
    ],
  },
  {
    key_word: 'เมื่อ',
    key_word_pronunciation: 'mʉ̂ʉa',
    rank: 128,
    sentences: [
      {
        thai_text: 'เมื่อวานฉันไปหาหมอ',
        pronunciation: 'mʉ̂a-waan chǎn pai hǎa mǎaw',
        japanese_translation: '昨日、私は病院に行きました',
      },
    ],
  },
  {
    key_word: 'กลับ',
    key_word_pronunciation: 'klàp',
    rank: 129,
    sentences: [
      {
        thai_text: 'เขากลับบ้านดึกทุกวัน',
        pronunciation: 'khǎo klàp bâan dʉ̀k thúk wan',
        japanese_translation: '彼は毎日遅くに帰宅します',
      },
    ],
  },
  {
    key_word: 'เด็ก',
    key_word_pronunciation: 'dèk',
    rank: 131,
    sentences: [
      {
        thai_text: 'เด็กๆ เล่นอยู่ในสวน',
        pronunciation: 'dèk-dèk lên yùu nai sǔan',
        japanese_translation: '子供たちは庭で遊んでいます',
      },
    ],
  },
  {
    key_word: 'จริง',
    key_word_pronunciation: 'jing',
    rank: 132,
    sentences: [
      {
        thai_text: 'เรื่องนี้เป็นเรื่องจริง',
        pronunciation: 'rʉ̂ang níi pen rʉ̂ang jing',
        japanese_translation: 'この話は本当の話です',
      },
    ],
  },
  {
    key_word: 'บ้าง',
    key_word_pronunciation: 'bâang',
    rank: 133,
    sentences: [
      {
        thai_text: 'มีอะไรน่ากินบ้าง',
        pronunciation: 'mii à-rai nâa-kin bâang',
        japanese_translation: '何かおいしそうなものはありますか',
      },
    ],
  },
  {
    key_word: 'เร็ว',
    key_word_pronunciation: 'rew',
    rank: 134,
    sentences: [
      {
        thai_text: 'รถไฟฟ้าเร็วกว่ารถเมล์',
        pronunciation: 'rót-fai-fáa rew kwàa rót-mee',
        japanese_translation: '電車はバスより速いです',
      },
    ],
  },
  {
    key_word: 'เวลา',
    key_word_pronunciation: 'wee-laa',
    rank: 135,
    sentences: [
      {
        thai_text: 'ไม่มีเวลาทำอาหาร',
        pronunciation: 'mâi mii wee-laa tham aa-hǎan',
        japanese_translation: '料理をする時間がありません',
      },
    ],
  },
  {
    key_word: 'บ้าน',
    key_word_pronunciation: 'bâan',
    rank: 136,
    sentences: [
      {
        thai_text: 'บ้านของฉันอยู่ใกล้สถานี',
        pronunciation: 'bâan khɔ̌ɔng chǎn yùu klâi sà-thǎa-nii',
        japanese_translation: '私の家は駅の近くにあります',
      },
    ],
  },
  {
    key_word: 'ใช่ไหม',
    key_word_pronunciation: 'châi-mǎi',
    rank: 140,
    sentences: [
      {
        thai_text: 'คุณเป็นคนญี่ปุ่นใช่ไหม',
        pronunciation: 'khun pen khon yîi-pùn châi mǎi',
        japanese_translation: 'あなたは日本人ですよね',
      },
    ],
  },
  {
    key_word: 'หยุด',
    key_word_pronunciation: 'yùt',
    rank: 141,
    sentences: [
      {
        thai_text: 'วันเสาร์ฉันหยุดงาน',
        pronunciation: 'wan sǎo chǎn yùt ngaan',
        japanese_translation: '土曜日は仕事が休みです',
      },
    ],
  },
  {
    key_word: 'เข้า',
    key_word_pronunciation: 'khâw',
    rank: 144,
    sentences: [
      {
        thai_text: 'เชิญเข้ามาข้างในเลย',
        pronunciation: 'chəən khâo maa khâang-nai ləəi',
        japanese_translation: 'どうぞ中にお入りください',
      },
    ],
  },
  {
    key_word: 'กลับมา',
    key_word_pronunciation: 'klàp-maa',
    rank: 145,
    sentences: [
      {
        thai_text: 'เขากลับมาจากต่างประเทศ',
        pronunciation: 'khǎo klàp-maa jàak tàang-prà-thêet',
        japanese_translation: '彼は海外から帰ってきました',
      },
    ],
  },
  {
    key_word: 'ทั้งหมด',
    key_word_pronunciation: 'tháng-mòt',
    rank: 150,
    sentences: [
      {
        thai_text: 'ทั้งหมดราคาเท่าไหร่',
        pronunciation: 'tháng-mòt raa-khaa thâo-rài',
        japanese_translation: '全部でいくらですか',
      },
    ],
  },
  {
    key_word: 'ที่สุด',
    key_word_pronunciation: 'thîi-sùt',
    rank: 153,
    sentences: [
      {
        thai_text: 'ส้มตำเป็นอาหารที่ชอบที่สุด',
        pronunciation: 'sôm-tam pen aa-hǎan thîi chɔ̂ɔp thîi-sùt',
        japanese_translation: 'ソムタムは一番好きな料理です',
      },
    ],
  },
  {
    key_word: 'อย่างนั้น',
    key_word_pronunciation: 'yàang-nán',
    rank: 156,
    sentences: [
      {
        thai_text: 'ไม่ควรพูดอย่างนั้น',
        pronunciation: 'mâi khuan phûut yàang-nán',
        japanese_translation: 'そんなふうに言うべきではありません',
      },
    ],
  },
  {
    key_word: 'ทุกคน',
    key_word_pronunciation: 'thúk-khon',
    rank: 157,
    sentences: [
      {
        thai_text: 'ทุกคนพร้อมแล้วหรือยัง',
        pronunciation: 'thúk-khon phrɔ́ɔm lɛ́ɛo rʉ̌ʉ yang',
        japanese_translation: 'みんな準備はできましたか',
      },
    ],
  },
  {
    key_word: 'ไม่ต้อง',
    key_word_pronunciation: 'mâi-tɔ̂ɔng',
    rank: 158,
    sentences: [
      {
        thai_text: 'วันนี้ไม่ต้องใส่ชุดยูนิฟอร์ม',
        pronunciation: 'wan-níi mâi-tɔ̂ng sài chút yuu-ní-fɔɔm',
        japanese_translation: '今日は制服を着なくていいです',
      },
    ],
  },
  {
    key_word: 'ทำงาน',
    key_word_pronunciation: 'tham-ngaan',
    rank: 160,
    sentences: [
      {
        thai_text: 'ฉันทำงานวันจันทร์ถึงศุกร์',
        pronunciation: 'chǎn tham-ngaan wan-jan thʉ̌ng wan-sùk',
        japanese_translation: '私は月曜から金曜まで働いています',
      },
    ],
  },
  {
    key_word: 'ได้ยิน',
    key_word_pronunciation: 'dâai-yin',
    rank: 161,
    sentences: [
      {
        thai_text: 'คุณได้ยินเสียงนั้นไหม',
        pronunciation: 'khun dâi-yin sǐang nán mǎi',
        japanese_translation: 'あの音が聞こえますか',
      },
    ],
  },
  {
    key_word: 'เกี่ยวกับ',
    key_word_pronunciation: 'kìiaw-kàp',
    rank: 162,
    sentences: [
      {
        thai_text: 'ฉันอ่านข่าวเกี่ยวกับเศรษฐกิจ',
        pronunciation: 'chǎn àan khàaw kìaw-kàp sèet-thà-kìt',
        japanese_translation: '私は経済に関するニュースを読みました',
      },
    ],
  },
  {
    key_word: 'ก็ได้',
    key_word_pronunciation: 'kɔ̂ɔ-dâai',
    rank: 168,
    sentences: [
      {
        thai_text: 'ไปวันไหนก็ได้',
        pronunciation: 'pai wan nǎi kɔ̂ɔ dâi',
        japanese_translation: 'いつ行ってもいいですよ',
      },
    ],
  },
  {
    key_word: 'ผู้หญิง',
    key_word_pronunciation: 'phûu-yǐng',
    rank: 171,
    sentences: [
      {
        thai_text: 'ผู้หญิงคนนั้นสวยมาก',
        pronunciation: 'phûu-yǐng khon nán sǔai mâak',
        japanese_translation: 'あの女性はとてもきれいです',
      },
    ],
  },
  {
    key_word: 'วันนี้',
    key_word_pronunciation: 'wan-níi',
    rank: 172,
    sentences: [
      {
        thai_text: 'วันนี้อากาศดีมาก',
        pronunciation: 'wan-níi aa-kàat dii mâak',
        japanese_translation: '今日はとてもいい天気です',
      },
    ],
  },
  {
    key_word: 'พยายาม',
    key_word_pronunciation: 'phá-yaa-yaam',
    rank: 174,
    sentences: [
      {
        thai_text: 'ฉันพยายามตื่นเช้าทุกวัน',
        pronunciation: 'chǎn phá-yaa-yaam tʉ̀ʉn cháao thúk wan',
        japanese_translation: '私は毎日早起きするよう努力しています',
      },
    ],
  },
  {
    key_word: 'เริ่ม',
    key_word_pronunciation: 'rə̂əm',
    rank: 176,
    sentences: [
      {
        thai_text: 'ประชุมเริ่มตอนเก้าโมง',
        pronunciation: 'prà-chum rə̂əm tɔɔn kâo moong',
        japanese_translation: '会議は9時に始まります',
      },
    ],
  },
  {
    key_word: 'หนึ่ง',
    key_word_pronunciation: 'nʉ̀ng',
    rank: 178,
    sentences: [
      {
        thai_text: 'ขอน้ำเปล่าหนึ่งขวด',
        pronunciation: 'khɔ̌ɔ náam-plàao nʉ̀ng khùat',
        japanese_translation: '水を一本ください',
      },
    ],
  },
  {
    key_word: 'เหมือนกัน',
    key_word_pronunciation: 'mʉ̌ʉan-kan',
    rank: 179,
    sentences: [
      {
        thai_text: 'ฉันคิดเหมือนกัน',
        pronunciation: 'chǎn khít mʉ̌an-kan',
        japanese_translation: '私も同じことを思います',
      },
    ],
  },
  {
    key_word: 'ตัวเอง',
    key_word_pronunciation: 'tuua-eeng',
    rank: 182,
    sentences: [
      {
        thai_text: 'เขาทำอาหารกินเองตัวเอง',
        pronunciation: 'khǎo tham aa-hǎan kin eeng tua-eeng',
        japanese_translation: '彼は自分で料理を作って食べます',
      },
    ],
  },
  {
    key_word: 'ทุกอย่าง',
    key_word_pronunciation: 'thúk-yàang',
    rank: 183,
    sentences: [
      {
        thai_text: 'ทุกอย่างเรียบร้อยแล้ว',
        pronunciation: 'thúk-yàang rîap-rɔ́ɔi lɛ́ɛo',
        japanese_translation: 'すべて準備が整いました',
      },
    ],
  },
  {
    key_word: 'เชื่อ',
    key_word_pronunciation: 'chʉ̂ʉa',
    rank: 184,
    sentences: [
      {
        thai_text: 'ฉันเชื่อว่าเขาพูดจริง',
        pronunciation: 'chǎn chʉ̂a wâa khǎo phûut jing',
        japanese_translation: '彼が本当のことを言っていると信じます',
      },
    ],
  },
  {
    key_word: 'ไม่เป็นไร',
    key_word_pronunciation: 'mâi-pen-rai',
    rank: 185,
    sentences: [
      {
        thai_text: 'ไม่เป็นไรครับ ไม่ต้องกังวล',
        pronunciation: 'mâi-pen-rai khráp mâi tɔ̂ng kang-won',
        japanese_translation: '大丈夫ですよ、心配しないでください',
      },
    ],
  },
  {
    key_word: 'เดี๋ยว',
    key_word_pronunciation: 'dǐiaw',
    rank: 188,
    sentences: [
      {
        thai_text: 'เดี๋ยวฉันโทรกลับนะ',
        pronunciation: 'dǐaw chǎn thoo klàp ná',
        japanese_translation: 'あとで折り返し電話しますね',
      },
    ],
  },
  {
    key_word: 'ใหม่',
    key_word_pronunciation: 'mài',
    rank: 190,
    sentences: [
      {
        thai_text: 'ฉันซื้อโทรศัพท์ใหม่',
        pronunciation: 'chǎn sʉ́ʉ thoo-rá-sàp mài',
        japanese_translation: '私は新しい携帯電話を買いました',
      },
    ],
  },
  {
    key_word: 'เพื่อน',
    key_word_pronunciation: 'phʉ̂ʉan',
    rank: 191,
    sentences: [
      {
        thai_text: 'เพื่อนชวนฉันไปดูหนัง',
        pronunciation: 'phʉ̂an chuan chǎn pai duu nǎng',
        japanese_translation: '友達が映画を見に行こうと誘ってくれました',
      },
    ],
  },
  {
    key_word: 'ปล่อย',
    key_word_pronunciation: 'plɔ̀ɔi',
    rank: 194,
    sentences: [
      {
        thai_text: 'ปล่อยให้เด็กเล่นเถอะ',
        pronunciation: 'plɔ̀i hâi dèk lên thə̀',
        japanese_translation: '子供に遊ばせてあげなよ',
      },
    ],
  },
  {
    key_word: 'ชื่อ',
    key_word_pronunciation: 'chʉ̂ʉ',
    rank: 199,
    sentences: [
      {
        thai_text: 'คุณชื่ออะไรครับ',
        pronunciation: 'khun chʉ̂ʉ à-rai khráp',
        japanese_translation: 'お名前は何ですか',
      },
    ],
  },
  {
    key_word: 'เล่น',
    key_word_pronunciation: 'lêen',
    rank: 201,
    sentences: [
      {
        thai_text: 'น้องชายชอบเล่นฟุตบอล',
        pronunciation: 'nɔ́ɔng-chaai chɔ̂ɔp lên fút-bɔɔn',
        japanese_translation: '弟はサッカーをするのが好きです',
      },
    ],
  },
  {
    key_word: 'นะคะ',
    key_word_pronunciation: 'ná-khá',
    rank: 202,
    sentences: [
      {
        thai_text: 'ระวังด้วยนะคะ',
        pronunciation: 'rá-wang dûai ná khá',
        japanese_translation: '気をつけてくださいね',
      },
    ],
  },
  {
    key_word: 'ที่ไหน',
    key_word_pronunciation: 'thîi-nǎi',
    rank: 204,
    sentences: [
      {
        thai_text: 'ห้องน้ำอยู่ที่ไหนครับ',
        pronunciation: 'hɔ̂ng-náam yùu thîi-nǎi khráp',
        japanese_translation: 'トイレはどこですか',
      },
    ],
  },
  {
    key_word: 'ออกมา',
    key_word_pronunciation: 'ɔ̀ɔk-maa',
    rank: 207,
    sentences: [
      {
        thai_text: 'แมวออกมาจากใต้โต๊ะ',
        pronunciation: 'mɛɛo ɔ̀ɔk-maa jàak tâi tó',
        japanese_translation: '猫がテーブルの下から出てきました',
      },
    ],
  },
  {
    key_word: 'เรียก',
    key_word_pronunciation: 'rîiak',
    rank: 208,
    sentences: [
      {
        thai_text: 'ช่วยเรียกแท็กซี่ให้หน่อย',
        pronunciation: 'chûai rîak thɛ́k-sîi hâi nɔ̀i',
        japanese_translation: 'タクシーを呼んでもらえますか',
      },
    ],
  },
  {
    key_word: 'โปรด',
    key_word_pronunciation: 'pròot',
    rank: 209,
    sentences: [
      {
        thai_text: 'สีโปรดของฉันคือสีฟ้า',
        pronunciation: 'sǐi pròot khɔ̌ɔng chǎn khʉʉ sǐi fáa',
        japanese_translation: '私のお気に入りの色は水色です',
      },
    ],
  },
  {
    key_word: 'น่าจะ',
    key_word_pronunciation: 'nâa-jà',
    rank: 211,
    sentences: [
      {
        thai_text: 'วันนี้น่าจะฝนตก',
        pronunciation: 'wan-níi nâa-jà fǒn tòk',
        japanese_translation: '今日は雨が降りそうです',
      },
    ],
  },
  {
    key_word: 'ได้รับ',
    key_word_pronunciation: 'dâai-ráp',
    rank: 213,
    sentences: [
      {
        thai_text: 'ฉันได้รับอีเมลจากบริษัท',
        pronunciation: 'chǎn dâi-ráp ii-meo jàak bɔɔ-rí-sàt',
        japanese_translation: '会社からメールを受け取りました',
      },
    ],
  },
  {
    key_word: 'ชีวิต',
    key_word_pronunciation: 'chii-wít',
    rank: 214,
    sentences: [
      {
        thai_text: 'ชีวิตในกรุงเทพฯ สนุกมาก',
        pronunciation: 'chii-wít nai krung-thêep sà-nùk mâak',
        japanese_translation: 'バンコクでの生活はとても楽しいです',
      },
    ],
  },
  {
    key_word: 'แล้วก็',
    key_word_pronunciation: 'lɛ́ɛw-kɔ̂ɔ',
    rank: 216,
    sentences: [
      {
        thai_text: 'ฉันซื้อผักแล้วก็ผลไม้',
        pronunciation: 'chǎn sʉ́ʉ phàk lɛ́ɛo-kɔ̂ɔ phǒn-lá-máai',
        japanese_translation: '私は野菜と果物を買いました',
      },
    ],
  },
  {
    key_word: 'รู้จัก',
    key_word_pronunciation: 'rúu-jàk',
    rank: 218,
    sentences: [
      {
        thai_text: 'คุณรู้จักร้านนี้ไหม',
        pronunciation: 'khun rúu-jàk ráan níi mǎi',
        japanese_translation: 'このお店を知っていますか',
      },
    ],
  },
  {
    key_word: 'แน่นอน',
    key_word_pronunciation: 'nɛ̂ɛ-nɔɔn',
    rank: 219,
    sentences: [
      {
        thai_text: 'แน่นอนว่าฉันจะไป',
        pronunciation: 'nɛ̂ɛ-nɔɔn wâa chǎn jà pai',
        japanese_translation: 'もちろん私は行きます',
      },
    ],
  },
  {
    key_word: 'เข้าไป',
    key_word_pronunciation: 'khâw-pai',
    rank: 220,
    sentences: [
      {
        thai_text: 'อย่าเข้าไปในห้องนั้น',
        pronunciation: 'yàa khâo-pai nai hɔ̂ng nán',
        japanese_translation: 'あの部屋に入らないでください',
      },
    ],
  },
  {
    key_word: 'กำลังจะ',
    key_word_pronunciation: 'kam-lang-jà',
    rank: 221,
    sentences: [
      {
        thai_text: 'ฉันกำลังจะออกจากบ้าน',
        pronunciation: 'chǎn kam-lang-jà ɔ̀ɔk jàak bâan',
        japanese_translation: '私はちょうど家を出るところです',
      },
    ],
  },
  {
    key_word: 'เกิดขึ้น',
    key_word_pronunciation: 'kə̀ət-khʉ̂n',
    rank: 224,
    sentences: [
      {
        thai_text: 'เกิดอะไรขึ้นที่นี่',
        pronunciation: 'kə̀ət à-rai khʉ̂n thîi-nîi',
        japanese_translation: 'ここで何が起きたんですか',
      },
    ],
  },
  {
    key_word: 'ห้อง',
    key_word_pronunciation: 'hɔ̂ɔng',
    rank: 225,
    sentences: [
      {
        thai_text: 'ห้องนี้กว้างและสะอาด',
        pronunciation: 'hɔ̂ng níi kwâang lɛ́ sà-àat',
        japanese_translation: 'この部屋は広くて清潔です',
      },
    ],
  },
  {
    key_word: 'ตอนที่',
    key_word_pronunciation: 'tɔɔn-thîi',
    rank: 227,
    sentences: [
      {
        thai_text: 'ตอนที่ฉันมาถึงฝนตกพอดี',
        pronunciation: 'tɔɔn-thîi chǎn maa thʉ̌ng fǒn tòk phɔɔ-dii',
        japanese_translation: '私が着いたとき、ちょうど雨が降っていました',
      },
    ],
  },


];

export const DEFAULT_SENTENCES: DefaultSentence[] = DEFAULT_SENTENCE_GROUPS.flatMap((group, groupIndex) =>
  group.sentences.map((sentence, sentenceIndex) => ({
    sentence_id: `default_${groupIndex + 1}_${sentenceIndex + 1}`,
    key_word: group.key_word,
    key_word_pronunciation: group.key_word_pronunciation,
    rank: group.rank,
    ...sentence,
  }))
);
