/**
 * クイズ用デフォルト例文データ（20問）
 *
 * 【クイズ生成の仕組み】
 * 本アプリでは毎日のタイ語復習クイズ（穴埋め4択形式）を提供している。
 * クイズの出題元は以下の2段階で決まる：
 *
 * 1. review_queue（優先）
 *    - dailyBatch（毎日JST 0:00実行）がユーザーの学習履歴からSRS（間隔反復）で
 *      復習すべき例文を選びFirestoreに保存したもの
 *    - generateQuiz Cloud Functionがここから最大5問をランダム抽出し、
 *      Gemini APIで穴埋め問題・選択肢・解説を動的生成する
 *
 * 2. デフォルト例文（フォールバック）
 *    - review_queueが空（新規ユーザー等）または例文数が不足する場合に使用
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
}

export const DEFAULT_SENTENCES: DefaultSentence[] = [
  {
    sentence_id: 'default_1',
    thai_text: 'ฉันชอบกินข้าวผัด',
    pronunciation: 'chǎn chɔ̂ɔp kin khâao phàt',
    japanese_translation: '私はチャーハンを食べるのが好きです',
  },
  {
    sentence_id: 'default_2',
    thai_text: 'วันนี้อากาศร้อนมาก',
    pronunciation: 'wan-níi aa-kàat rɔ́ɔn mâak',
    japanese_translation: '今日はとても暑いです',
  },
  {
    sentence_id: 'default_3',
    thai_text: 'เขาไปโรงเรียนทุกวัน',
    pronunciation: 'khǎo pai roong-rian thúk wan',
    japanese_translation: '彼は毎日学校に行きます',
  },
  {
    sentence_id: 'default_4',
    thai_text: 'น้ำส้มอร่อยมาก',
    pronunciation: 'nám-sôm a-rɔ̀i mâak',
    japanese_translation: 'オレンジジュースがとても美味しいです',
  },
  {
    sentence_id: 'default_5',
    thai_text: 'แม่ทำอาหารที่บ้าน',
    pronunciation: 'mɛ̂ɛ tham aa-hǎan thîi bâan',
    japanese_translation: '母は家で料理を作ります',
  },
  {
    sentence_id: 'default_6',
    thai_text: 'สวัสดีครับผมชื่อสมชาย',
    pronunciation: 'sa-wàt-dii khráp phǒm chʉ̂ʉ sǒm-chaai',
    japanese_translation: 'こんにちは、私の名前はソムチャイです',
  },
  {
    sentence_id: 'default_7',
    thai_text: 'ฉันไปซื้อของที่ตลาด',
    pronunciation: 'chǎn pai sʉ́ʉ khɔ̌ɔng thîi ta-làat',
    japanese_translation: '私は市場に買い物に行きます',
  },
  {
    sentence_id: 'default_8',
    thai_text: 'เราจะนั่งรถไฟไปเชียงใหม่',
    pronunciation: 'rao jà nâng rót-fai pai chiang-mài',
    japanese_translation: '私たちは電車でチェンマイに行きます',
  },
  {
    sentence_id: 'default_9',
    thai_text: 'น้องสาวเรียนภาษาไทย',
    pronunciation: 'nɔ́ɔng-sǎao rian phaa-sǎa thai',
    japanese_translation: '妹はタイ語を勉強しています',
  },
  {
    sentence_id: 'default_10',
    thai_text: 'กระเป๋านี้แพงเกินไป',
    pronunciation: 'kra-pǎo níi phɛɛng kəən-pai',
    japanese_translation: 'このカバンは高すぎます',
  },
  {
    sentence_id: 'default_11',
    thai_text: 'ฉันหิวข้าวมากเลย',
    pronunciation: 'chǎn hǐu khâao mâak ləəi',
    japanese_translation: 'とてもお腹が空きました',
  },
  {
    sentence_id: 'default_12',
    thai_text: 'ดอกไม้ในสวนสวยมาก',
    pronunciation: 'dɔ̀ɔk-mái nai sǔan sǔai mâak',
    japanese_translation: '庭の花がとても美しいです',
  },
  {
    sentence_id: 'default_13',
    thai_text: 'เด็กๆชอบเล่นที่ทะเล',
    pronunciation: 'dèk-dèk chɔ̂ɔp lên thîi thá-lee',
    japanese_translation: '子供たちは海で遊ぶのが好きです',
  },
  {
    sentence_id: 'default_14',
    thai_text: 'คุณพูดภาษาไทยได้ไหม',
    pronunciation: 'khun phûut phaa-sǎa thai dâai mǎi',
    japanese_translation: 'タイ語を話せますか？',
  },
  {
    sentence_id: 'default_15',
    thai_text: 'ขอกาแฟเย็นหนึ่งแก้ว',
    pronunciation: 'khɔ̌ɔ kaa-fɛɛ yen nùeng kɛ̂ɛw',
    japanese_translation: 'アイスコーヒーを一杯ください',
  },
  {
    sentence_id: 'default_16',
    thai_text: 'เมื่อคืนผมนอนดึกมาก',
    pronunciation: 'mʉ̂a-khʉʉn phǒm nɔɔn dùek mâak',
    japanese_translation: '昨夜はとても遅くまで起きていました',
  },
  {
    sentence_id: 'default_17',
    thai_text: 'พี่ชายอยากเป็นหมอ',
    pronunciation: 'phîi-chaai yàak pen mɔ̌ɔ',
    japanese_translation: '兄は医者になりたいです',
  },
  {
    sentence_id: 'default_18',
    thai_text: 'วันนี้ฝนตกหนักมาก',
    pronunciation: 'wan-níi fǒn tòk nàk mâak',
    japanese_translation: '今日は雨がとても激しく降っています',
  },
  {
    sentence_id: 'default_19',
    thai_text: 'ผัดไทยร้านนี้อร่อยที่สุด',
    pronunciation: 'phàt-thai ráan níi a-rɔ̀i thîi-sùt',
    japanese_translation: 'この店のパッタイが一番美味しいです',
  },
  {
    sentence_id: 'default_20',
    thai_text: 'เราไปดูช้างที่เชียงใหม่',
    pronunciation: 'rao pai duu cháang thîi chiang-mài',
    japanese_translation: '私たちはチェンマイで象を見に行きます',
  },
];
