/// 例文生成中に表示するTipsデータ
class LoadingTip {
  final String category;
  final String title;
  final String content;
  final String? example;

  const LoadingTip({
    required this.category,
    required this.title,
    required this.content,
    this.example,
  });
}

class LoadingTips {
  LoadingTips._();

  static const List<LoadingTip> all = [
    // --- 母音の読み方 ---
    LoadingTip(
      category: '母音',
      title: 'อะ / อา （a / aa）',
      content: '短母音 อะ は「ア」、長母音 อา は「アー」。長さで意味が変わります。',
      example: 'จะ（ジャ＝〜する） / จา（ジャー＝皿）',
    ),
    LoadingTip(
      category: '母音',
      title: 'อิ / อี （i / ii）',
      content: '短母音 อิ は短い「イ」、長母音 อี は長い「イー」。',
      example: 'นิด（ニッ＝少し） / นี่（ニー＝これ）',
    ),
    LoadingTip(
      category: '母音',
      title: 'อุ / อู （u / uu）',
      content: '短母音 อุ は短い「ウ」、長母音 อู は長い「ウー」。',
      example: 'รุ่น（ルン＝世代） / รู้（ルー＝知る）',
    ),
    LoadingTip(
      category: '母音',
      title: 'เอ / แอ （ee / ae）',
      content: 'เอ は「エー」、แอ は口を大きく開けた「エー」。',
      example: 'เก่ง（ゲン＝上手） / แก่（ゲー＝老いた）',
    ),
    LoadingTip(
      category: '母音',
      title: 'โอ / ออ （oo / ɔɔ）',
      content: 'โอ は口をすぼめた「オー」、ออ は口を開けた「オー」。',
      example: 'โต（トー＝大きい） / ต่อ（トー＝続ける）',
    ),
    LoadingTip(
      category: '母音',
      title: 'เอือ （ʉa）',
      content: 'เอือ は「ウア」に近い音。日本語にない母音です。',
      example: 'เมือง（ムアン＝街・国）',
    ),
    LoadingTip(
      category: '母音',
      title: 'อือ / อื （ʉ / ʉʉ）',
      content: '日本語にない音。「イ」の口で「ウ」と発音するイメージ。',
      example: 'คือ（クー＝〜である） / ฝืน（フーン＝無理する）',
    ),
    LoadingTip(
      category: '母音',
      title: 'เอีย （ia）',
      content: 'เอีย は「イア」。イからアへ滑らかにつなげます。',
      example: 'เรียน（リアン＝学ぶ）',
    ),
    LoadingTip(
      category: '母音',
      title: 'อัว （ua）',
      content: 'อัว は「ウア」。ウからアへ滑らかにつなげます。',
      example: 'ตัว（トゥア＝体・匹）',
    ),
    LoadingTip(
      category: '母音',
      title: 'เอา （ao）',
      content: 'เอา は「アオ」。口を開けてからすぼめます。',
      example: 'เอา（アオ＝要る・取る）',
    ),
    LoadingTip(
      category: '母音',
      title: 'ไอ / ใอ （ai）',
      content: 'ไอ と ใอ は同じ「アイ」の発音。ใ を使う語は20語だけ。',
      example: 'ไป（パイ＝行く） / ใจ（ジャイ＝心）',
    ),
    LoadingTip(
      category: '母音',
      title: 'เอ็（短母音 e）',
      content: '短い「エ」。เ〜็ の形で表記されます。',
      example: 'เก็บ（ゲップ＝拾う・保管する）',
    ),
    LoadingTip(
      category: '母音',
      title: 'แอ็（短母音 ae）',
      content: '短い「エ」（口を大きく開ける）。แ〜็ の形。',
      example: 'แบ็ก（ベーク＝バッグ）',
    ),
    LoadingTip(
      category: '母音',
      title: 'เออ （əə）',
      content: 'เออ は曖昧な「ウー」。口を半開きにして発音。',
      example: 'เธอ（トゥー＝あなた・彼女）',
    ),
    LoadingTip(
      category: '母音',
      title: '母音の長短で意味が変わる',
      content: 'タイ語は母音の長さが重要。短母音と長母音で別の単語になります。',
      example: 'ปะ（パ＝出会う） / ป้า（パー＝おばさん）',
    ),
    // --- 文化・習慣 ---
    LoadingTip(
      category: '文化',
      title: 'ワイ（合掌・ไหว้）',
      content: '両手を合わせるタイ式挨拶。目上の人には鼻の高さ、同年代は胸の高さで。',
    ),
    LoadingTip(
      category: '文化',
      title: '頭は神聖な場所',
      content: 'タイでは頭は最も高貴な部分。他人の頭を触るのはタブーです。',
    ),
    LoadingTip(
      category: '文化',
      title: '足は不浄とされる',
      content: '足を人や仏像に向けるのは失礼。足で物を指すのも避けましょう。',
    ),
    LoadingTip(
      category: '文化',
      title: '寺院参拝のマナー',
      content: '寺院では靴を脱ぎ、肩と膝を隠す服装で。仏像より高い位置に座らないこと。',
    ),
    LoadingTip(
      category: '文化',
      title: 'ソンクラーン（水かけ祭り）',
      content: '毎年4月13〜15日のタイ正月。水をかけ合い新年を祝います。',
    ),
    LoadingTip(
      category: '文化',
      title: 'ロイクラトン（灯篭流し）',
      content: '陰暦12月の満月に川へ灯篭を流す祭り。水の精霊に感謝を捧げます。',
    ),
    LoadingTip(
      category: '文化',
      title: '国王への敬意',
      content: '映画館では上映前に国歌が流れ起立します。王室への敬意はタイ文化の根幹です。',
    ),
    LoadingTip(
      category: '文化',
      title: 'タイ料理の食べ方',
      content: 'フォークとスプーンを使い、スプーンで口に運びます。箸は麺料理の時だけ。',
    ),
    LoadingTip(
      category: '文化',
      title: '托鉢（たくはつ）',
      content: '早朝、僧侶が托鉢に回ります。食べ物を寄進することは大きな功徳とされます。',
    ),
    LoadingTip(
      category: '文化',
      title: 'マイペンライ（ไม่เป็นไร）',
      content: '「気にしないで・大丈夫」。タイ人の寛容さを表す代表的フレーズです。',
    ),
  ];
}
