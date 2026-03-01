/**
 * デフォルト例文データ（20問）
 * review_queueにデータがない場合や補填用に使用
 * 選択肢・穴埋め・解説はGeminiで毎回生成する
 */
export interface DefaultSentence {
  sentence_id: string;
  thai_text: string;
  pronunciation: string;
  japanese_translation: string;
}

export const DEFAULT_SENTENCES: DefaultSentence[] = [
  {
    sentence_id: 'default_1',
    thai_text: 'ฉันชอบกินข้าวผัด',
    pronunciation: 'chǎn chôop kin khâao phàt',
    japanese_translation: '私はチャーハンを食べるのが好きです',
  },
  {
    sentence_id: 'default_2',
    thai_text: 'วันนี้อากาศร้อนมาก',
    pronunciation: 'wan-níi aa-kàat ráwn mâak',
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
    pronunciation: 'nám-sôm a-ròi mâak',
    japanese_translation: 'オレンジジュースがとても美味しいです',
  },
  {
    sentence_id: 'default_5',
    thai_text: 'แม่ทำอาหารที่บ้าน',
    pronunciation: 'mâe tham aa-hǎan thîi bâan',
    japanese_translation: '母は家で料理を作ります',
  },
  {
    sentence_id: 'default_6',
    thai_text: 'สวัสดีครับผมชื่อสมชาย',
    pronunciation: 'sa-wàt-dii khráp phǒm chûue sǒm-chaai',
    japanese_translation: 'こんにちは、私の名前はソムチャイです',
  },
  {
    sentence_id: 'default_7',
    thai_text: 'ฉันไปซื้อของที่ตลาด',
    pronunciation: 'chǎn pai súue khǎwng thîi ta-làat',
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
    pronunciation: 'náwng-sǎao rian phaa-sǎa thai',
    japanese_translation: '妹はタイ語を勉強しています',
  },
  {
    sentence_id: 'default_10',
    thai_text: 'กระเป๋านี้แพงเกินไป',
    pronunciation: 'kra-pǎo níi phaaeng koen-pai',
    japanese_translation: 'このカバンは高すぎます',
  },
  {
    sentence_id: 'default_11',
    thai_text: 'ฉันหิวข้าวมากเลย',
    pronunciation: 'chǎn hǐu khâao mâak loei',
    japanese_translation: 'とてもお腹が空きました',
  },
  {
    sentence_id: 'default_12',
    thai_text: 'ดอกไม้ในสวนสวยมาก',
    pronunciation: 'dàwk-mái nai sǔan sǔai mâak',
    japanese_translation: '庭の花がとても美しいです',
  },
  {
    sentence_id: 'default_13',
    thai_text: 'เด็กๆชอบเล่นที่ทะเล',
    pronunciation: 'dèk-dèk chôop lên thîi thá-lee',
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
    pronunciation: 'khǎw kaa-faae yen nùeng kâaew',
    japanese_translation: 'アイスコーヒーを一杯ください',
  },
  {
    sentence_id: 'default_16',
    thai_text: 'เมื่อคืนผมนอนดึกมาก',
    pronunciation: 'mûea-khuuen phǒm nawn dùek mâak',
    japanese_translation: '昨夜はとても遅くまで起きていました',
  },
  {
    sentence_id: 'default_17',
    thai_text: 'พี่ชายอยากเป็นหมอ',
    pronunciation: 'phîi-chaai yàak pen mǎw',
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
    pronunciation: 'phàt-thai ráan níi a-ròi thîi-sùt',
    japanese_translation: 'この店のパッタイが一番美味しいです',
  },
  {
    sentence_id: 'default_20',
    thai_text: 'เราไปดูช้างที่เชียงใหม่',
    pronunciation: 'rao pai duu cháang thîi chiang-mài',
    japanese_translation: '私たちはチェンマイで象を見に行きます',
  },
];
