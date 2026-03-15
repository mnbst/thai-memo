/**
 * クイズ用デフォルト例文データ（32問、頻度順位500位以内）
 *
 * 【クイズ生成の仕組み】
 * 本アプリでは毎日のタイ語復習クイズ（穴埋め4択形式）を提供している。
 * クイズの出題元は以下の2段階で決まる：
 *
 * 1. SRSベースのリアルタイム選出（優先）
 *    - generateQuiz Cloud Function呼び出し時に、ユーザーの学習履歴から
 *      SRS（間隔反復）で復習すべき例文をリアルタイムに選出する
 *    - 最大15問から5問をランダム抽出し、Gemini APIで穴埋め問題・選択肢・解説を動的生成
 *
 * 2. デフォルト例文（フォールバック）
 *    - ユーザー例文がない（新規ユーザー等）または例文数が不足する場合に使用
 *    - 下記の汎用タイ語例文から不足分を補填する
 *
 * ※ 選択肢・穴埋め箇所・解説文はここには含まれず、Geminiが毎回生成する
 */
export interface DefaultSentence {
  sentence_id: string;
  thai_text: string;
  /** 発音記号（ローマ字表記） */
  pronunciation: string;
  japanese_translation: string;
  /** 穴埋め対象として優先したい単語 */
  key_word: string;
}

type DefaultSentenceTemplate = Omit<DefaultSentence, 'sentence_id' | 'key_word'>;

interface DefaultSentenceGroup {
  key_word: string;
  sentences: DefaultSentenceTemplate[];
}

/**
 * 1位-500位をバケットに分割し、各帯域から1つずつ key_word を選ぶ。
 * 同じ key_word に紐づく例文数を、その単語に割り当てる問題数として扱う。
 * 上位語ほど複数例文、下位語ほど少ない例文数にしている。
 * 出現頻度順位は scripts/corpus/freq_rank_top10000.json を参照。
 */
const DEFAULT_SENTENCE_GROUPS: DefaultSentenceGroup[] = [
  {
    // rank帯: 1-25 / 出現頻度順位: 26位 / 出題頻度: 高（3例文）
    key_word: 'ทำ',
    sentences: [
      {
        thai_text: 'แม่ทำอาหารให้ทุกคน',
        pronunciation: 'mɛ̂ɛ tham aa-hǎan hâi thúk-khon',
        japanese_translation: '母はみんなに料理を作ります',
      },
      {
        thai_text: 'ฉันทำการบ้านเสร็จแล้ว',
        pronunciation: 'chǎn tham kaan-bâan sèt lɛ́ɛo',
        japanese_translation: '私は宿題を終えました',
      },
      {
        thai_text: 'เขาทำงานที่โรงพยาบาล',
        pronunciation: 'khǎo tham-ngaan thîi roong-phá-yaa-baan',
        japanese_translation: '彼は病院で働いています',
      },
    ],
  },
  {
    // rank帯: 26-50 / 出現頻度順位: 40位 / 出題頻度: 中（2例文）
    key_word: 'คิด',
    sentences: [
      {
        thai_text: 'ฉันคิดว่าพรุ่งนี้ฝนจะตก',
        pronunciation: 'chǎn khít wâa phrûng-níi fǒn jà tòk',
        japanese_translation: '明日は雨が降ると思います',
      },
      {
        thai_text: 'เขาคิดถึงบ้านทุกวัน',
        pronunciation: 'khǎo khít-thʉ̌ng bâan thúk wan',
        japanese_translation: '彼は毎日家を恋しく思います',
      },
    ],
  },
  {
    // rank帯: 51-75 / 出現頻度順位: 75位 / 出題頻度: 中（2例文）
    key_word: 'เห็น',
    sentences: [
      {
        thai_text: 'ฉันเห็นแมวอยู่ใต้โต๊ะ',
        pronunciation: 'chǎn hěn mɛɛo yùu tâi tó',
        japanese_translation: '机の下に猫がいるのが見えます',
      },
      {
        thai_text: 'คุณเห็นกุญแจของฉันไหม',
        pronunciation: 'khun hěn kun-jɛɛ khɔ̌ɔng chǎn mǎi',
        japanese_translation: '私の鍵を見ましたか',
      },
    ],
  },
  {
    // rank帯: 76-100 / 出現頻度順位: 87位 / 出題頻度: 中（2例文）
    key_word: 'ช่วย',
    sentences: [
      {
        thai_text: 'ช่วยเปิดประตูให้หน่อยได้ไหม',
        pronunciation: 'chûai pə̀ət prà-tuu hâi nɔ̀i dâi mǎi',
        japanese_translation: 'ドアを開けてもらえますか',
      },
      {
        thai_text: 'พี่ช่วยน้องทำการบ้าน',
        pronunciation: 'phîi chûai nɔ́ɔng tham kaan-bâan',
        japanese_translation: '兄は弟の宿題を手伝います',
      },
    ],
  },
  {
    // rank帯: 101-125 / 出現頻度順位: 113位 / 出題頻度: 中（2例文）
    key_word: 'ชอบ',
    sentences: [
      {
        thai_text: 'ฉันชอบกินข้าวผัด',
        pronunciation: 'chǎn chɔ̂ɔp kin khâao phàt',
        japanese_translation: '私はチャーハンを食べるのが好きです',
      },
      {
        thai_text: 'เด็กๆชอบเล่นที่สวน',
        pronunciation: 'dèk-dèk chɔ̂ɔp lên thîi sǔan',
        japanese_translation: '子供たちは庭で遊ぶのが好きです',
      },
    ],
  },
  {
    // rank帯: 126-150 / 出現頻度順位: 136位 / 出題頻度: 中（2例文）
    key_word: 'บ้าน',
    sentences: [
      {
        thai_text: 'บ้านของฉันอยู่ใกล้สถานี',
        pronunciation: 'bâan khɔ̌ɔng chǎn yùu klâi sà-thǎa-nii',
        japanese_translation: '私の家は駅の近くにあります',
      },
      {
        thai_text: 'เขากลับบ้านหลังเลิกงาน',
        pronunciation: 'khǎo klàp bâan lǎng lə̂ək ngaan',
        japanese_translation: '彼は仕事の後に帰宅します',
      },
    ],
  },
  {
    // rank帯: 151-175 / 出現頻度順位: 155位 / 出題頻度: 中（2例文）
    key_word: 'กิน',
    sentences: [
      {
        thai_text: 'เรากินข้าวเที่ยงด้วยกันไหม',
        pronunciation: 'rao kin khâao thîang dûai-kan mǎi',
        japanese_translation: '一緒にお昼ごはんを食べませんか',
      },
      {
        thai_text: 'เด็กคนนี้กินผักทุกวัน',
        pronunciation: 'dèk khon níi kin phàk thúk wan',
        japanese_translation: 'この子は毎日野菜を食べます',
      },
    ],
  },
  {
    // rank帯: 176-200 / 出現頻度順位: 191位 / 出題頻度: 低（1例文）
    key_word: 'เพื่อน',
    sentences: [
      {
        thai_text: 'เพื่อนชวนฉันไปดูหนัง',
        pronunciation: 'phʉ̂an chuan chǎn pai duu nǎng',
        japanese_translation: '友達が私を映画に誘いました',
      },
    ],
  },
  {
    // rank帯: 201-225 / 出現頻度順位: 225位 / 出題頻度: 低（1例文）
    key_word: 'ห้อง',
    sentences: [
      {
        thai_text: 'ห้องนี้สะอาดและเงียบมาก',
        pronunciation: 'hɔ̂ɔng níi sà-àat lɛ́ ngîap mâak',
        japanese_translation: 'この部屋はきれいでとても静かです',
      },
    ],
  },
  {
    // rank帯: 226-250 / 出現頻度順位: 231位 / 出題頻度: 低（1例文）
    key_word: 'เงิน',
    sentences: [
      {
        thai_text: 'ฉันไม่มีเงินพอวันนี้',
        pronunciation: 'chǎn mâi mii ngəən phɔɔ wan-níi',
        japanese_translation: '今日は十分なお金がありません',
      },
    ],
  },
  {
    // rank帯: 251-275 / 出現頻度順位: 270位 / 出題頻度: 低（1例文）
    key_word: 'ครอบครัว',
    sentences: [
      {
        thai_text: 'ครอบครัวของฉันมีห้าคน',
        pronunciation: 'khrɔ̂ɔp-khrua khɔ̌ɔng chǎn mii hâa khon',
        japanese_translation: '私の家族は5人です',
      },
    ],
  },
  {
    // rank帯: 276-300 / 出現頻度順位: 293位 / 出題頻度: 低（1例文）
    key_word: 'ซื้อ',
    sentences: [
      {
        thai_text: 'แม่ไปซื้อของที่ตลาด',
        pronunciation: 'mɛ̂ɛ pai sʉ́ʉ khɔ̌ɔng thîi tà-làat',
        japanese_translation: '母は市場に買い物に行きます',
      },
    ],
  },
  {
    // rank帯: 301-325 / 出現頻度順位: 308位 / 出題頻度: 低（2例文）
    key_word: 'สำคัญ',
    sentences: [
      {
        thai_text: 'เรื่องนี้สำคัญมากสำหรับฉัน',
        pronunciation: 'rʉ̂ang níi sǎm-khan mâak sǎm-ràp chǎn',
        japanese_translation: 'この件は私にとってとても重要です',
      },
      {
        thai_text: 'สุขภาพสำคัญกว่าเงิน',
        pronunciation: 'sùk-khà-phâap sǎm-khan kwàa ngəən',
        japanese_translation: '健康はお金より大切です',
      },
    ],
  },
  {
    // rank帯: 326-350 / 出現頻度順位: 331位 / 出題頻度: 低（2例文）
    key_word: 'สวย',
    sentences: [
      {
        thai_text: 'ดอกไม้ในสวนสวยมาก',
        pronunciation: 'dɔ̀ɔk-máai nai sǔan sǔai mâak',
        japanese_translation: '庭の花がとてもきれいです',
      },
      {
        thai_text: 'วันนี้คุณแต่งตัวสวยจัง',
        pronunciation: 'wan-níi khun tɛ̀ɛng-tua sǔai jang',
        japanese_translation: '今日はとてもおしゃれですね',
      },
    ],
  },
  {
    // rank帯: 351-375 / 出現頻度順位: 361位 / 出題頻度: 低（1例文）
    key_word: 'นอน',
    sentences: [
      {
        thai_text: 'เมื่อคืนฉันนอนไม่หลับ',
        pronunciation: 'mʉ̂a-khʉʉn chǎn nɔɔn mâi làp',
        japanese_translation: '昨夜は眠れませんでした',
      },
    ],
  },
  {
    // rank帯: 376-400 / 出現頻度順位: 386位 / 出題頻度: 低（2例文）
    key_word: 'โรงเรียน',
    sentences: [
      {
        thai_text: 'ลูกไปโรงเรียนทุกเช้า',
        pronunciation: 'lûuk pai roong-rian thúk cháao',
        japanese_translation: '子供は毎朝学校に行きます',
      },
      {
        thai_text: 'โรงเรียนของเราอยู่ไม่ไกล',
        pronunciation: 'roong-rian khɔ̌ɔng rao yùu mâi klai',
        japanese_translation: '私たちの学校は遠くありません',
      },
    ],
  },
  {
    // rank帯: 401-425 / 出現頻度順位: 414位 / 出題頻度: 低（1例文）
    key_word: 'อายุ',
    sentences: [
      {
        thai_text: 'คุณอายุเท่าไหร่คะ',
        pronunciation: 'khun aa-yú thâo-rài khá',
        japanese_translation: 'おいくつですか',
      },
    ],
  },
  {
    // rank帯: 426-450 / 出現頻度順位: 449位 / 出題頻度: 低（1例文）
    key_word: 'ขาย',
    sentences: [
      {
        thai_text: 'ร้านนี้ขายผลไม้สดทุกวัน',
        pronunciation: 'ráan níi khǎai phǒn-lá-máai sòt thúk wan',
        japanese_translation: 'この店は毎日新鮮な果物を売っています',
      },
    ],
  },
  {
    // rank帯: 451-475 / 出現頻度順位: 467位 / 出題頻度: 低（1例文）
    key_word: 'เขียน',
    sentences: [
      {
        thai_text: 'ฉันเขียนจดหมายถึงแม่',
        pronunciation: 'chǎn khǐan jòt-mǎai thʉ̌ng mɛ̂ɛ',
        japanese_translation: '私は母に手紙を書きます',
      },
    ],
  },
  {
    // rank帯: 476-500 / 出現頻度順位: 478位 / 出題頻度: 低（2例文）
    key_word: 'ปัญหา',
    sentences: [
      {
        thai_text: 'ปัญหานี้แก้ไม่ยาก',
        pronunciation: 'pan-hǎa níi kɛ̂ɛ mâi yâak',
        japanese_translation: 'この問題は解決するのは難しくありません',
      },
      {
        thai_text: 'ถ้ามีปัญหาบอกฉันได้เลย',
        pronunciation: 'thâa mii pan-hǎa bɔ̀ɔk chǎn dâi ləəi',
        japanese_translation: '問題があれば私に言ってください',
      },
    ],
  },
];

export const DEFAULT_SENTENCES: DefaultSentence[] = DEFAULT_SENTENCE_GROUPS.flatMap((group, groupIndex) =>
  group.sentences.map((sentence, sentenceIndex) => ({
    sentence_id: `default_${groupIndex + 1}_${sentenceIndex + 1}`,
    key_word: group.key_word,
    ...sentence,
  }))
);
