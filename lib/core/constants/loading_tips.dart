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
      content: '短母音 อะ は「a」、長母音 อา は「aa」。長さで意味が変わります。',
      example: 'จะ（jà＝〜する） / จา（jaa＝皿）',
    ),
    LoadingTip(
      category: '母音',
      title: 'อิ / อี （i / ii）',
      content: '短母音 อิ は短い「i」、長母音 อี は長い「ii」。',
      example: 'นิด（nít＝少し） / นี่（nîi＝これ）',
    ),
    LoadingTip(
      category: '母音',
      title: 'อุ / อู （u / uu）',
      content: '短母音 อุ は短い「u」、長母音 อู は長い「uu」。',
      example: 'รุ่น（rùn＝世代） / รู้（rúu＝知る）',
    ),
    LoadingTip(
      category: '母音',
      title: 'เอ / แอ （ee / ae）',
      content: 'เอ は「ee」、แอ は口を大きく開けた「ae」。',
      example: 'เก่ง（kèeng＝上手） / แก่（kɛ̀ɛ＝老いた）',
    ),
    LoadingTip(
      category: '母音',
      title: 'โอ / ออ （oo / ɔɔ）',
      content: 'โอ は口をすぼめた「oo」、ออ は口を開けた「ɔɔ」。',
      example: 'โต（too＝大きい） / ต่อ（tɔ̀ɔ＝続ける）',
    ),
    LoadingTip(
      category: '母音',
      title: 'เอือ （ʉa）',
      content: 'เอือ は日本語にない母音。「ʉa」と表記されます。',
      example: 'เมือง（mʉʉang＝街・国）',
    ),
    LoadingTip(
      category: '母音',
      title: 'อือ / อื （ʉ / ʉʉ）',
      content: '日本語にない音。「i」の口で「u」と発音するイメージ。',
      example: 'คือ（khʉʉ＝〜である） / ฝืน（fʉ̌ʉn＝無理する）',
    ),
    LoadingTip(
      category: '母音',
      title: 'เอีย （ia）',
      content: 'เอีย は「ia」。i から a へ滑らかにつなげます。',
      example: 'เรียน（riian＝学ぶ）',
    ),
    LoadingTip(
      category: '母音',
      title: 'อัว （ua）',
      content: 'อัว は「ua」。u から a へ滑らかにつなげます。',
      example: 'ตัว（tuua＝体・匹）',
    ),
    LoadingTip(
      category: '母音',
      title: 'เอา （aw）',
      content: 'เอา は「aw」。口を開けてからすぼめます。',
      example: 'เอา（aw＝要る・取る）',
    ),
    LoadingTip(
      category: '母音',
      title: 'ไอ / ใอ （ai）',
      content: 'ไอ と ใอ は同じ「ai」の発音。ใ を使う語は20語だけ。',
      example: 'ไป（pai＝行く） / ใจ（jai＝心）',
    ),
    LoadingTip(
      category: '母音',
      title: 'เอ็（短母音 e）',
      content: '短い「e」。เ〜็ の形で表記されます。',
      example: 'เก็บ（kèp＝拾う・保管する）',
    ),
    LoadingTip(
      category: '母音',
      title: 'แอ็（短母音 ae）',
      content: '短い「ae」（口を大きく開ける）。แ〜็ の形。',
      example: 'แบ็ก（báek＝バッグ）',
    ),
    LoadingTip(
      category: '母音',
      title: 'เออ （əə）',
      content: 'เออ は曖昧な母音「əə」。口を半開きにして発音。',
      example: 'เธอ（thəə＝あなた・彼女）',
    ),
    LoadingTip(
      category: '母音',
      title: '母音の長短で意味が変わる',
      content: 'タイ語は母音の長さが重要。短母音と長母音で別の単語になります。',
      example: 'ปะ（pà＝出会う） / ป้า（pâa＝おばさん）',
    ),
    // --- 文化・習慣 ---
    LoadingTip(
      category: '文化',
      title: 'wâi（合掌・ไหว้）',
      content: '両手を合わせるタイ式挨拶。目上の人には鼻の高さ、同年代は胸の高さで。',
    ),
    LoadingTip(
      category: '文化',
      title: '寺院参拝のマナー',
      content: '寺院では靴を脱ぎ、肩と膝を隠す服装で。仏像より高い位置に座らないこと。',
    ),
    LoadingTip(
      category: '文化',
      title: 'sǒngkraan（水かけ祭り）',
      content: '毎年4月13〜15日のタイ正月。水をかけ合い新年を祝います。',
    ),
    LoadingTip(
      category: '文化',
      title: 'lɔɔi krathong（灯篭流し）',
      content: '陰暦12月の満月に川へ灯篭を流す祭り。水の精霊に感謝を捧げます。',
    ),
    LoadingTip(
      category: '文化',
      title: 'タイ料理の食べ方',
      content: 'フォークとスプーンを使い、スプーンで口に運びます。箸は麺料理の時だけ。',
    ),
    LoadingTip(
      category: '文化',
      title: 'ไม่เป็นไร（mâi pen rai）',
      content: '「気にしないで・大丈夫」。タイ人の寛容さを表す代表的フレーズです。',
    ),
    // --- 声調 ---
    LoadingTip(
      category: '声調',
      title: 'タイ語は5つの声調',
      content: '平声・低声・下声・高声・上声の5つ。声調が違うと全く別の単語になります。',
      example: 'ไหม（mǎi＝絹） / ใหม่（mài＝新しい） / ไม่（mâi＝〜ない）',
    ),
    LoadingTip(
      category: '声調',
      title: '声調記号 ่ （mái èek）',
      content: '文字の上に付く第1声調記号。中子音・高子音に付くと低声になります。',
      example: 'เก่า（kàw＝古い）、ข่าว（khàaw＝ニュース）',
    ),
    LoadingTip(
      category: '声調',
      title: '声調記号 ้ （mái thoo）',
      content: '文字の上に付く第2声調記号。中子音に付くと下声になります。',
      example: 'น้ำ（náam＝水）、บ้าน（bâan＝家）',
    ),
    LoadingTip(
      category: '声調',
      title: '声調記号 ๊ と ๋',
      content: '๊（mái trii）は高声、๋（mái jàttawaa）は上声を示します。使用頻度は低め。',
      example: 'โน๊ต（nóot＝ノート）、จ๋า（jǎa＝はいよ）',
    ),
    LoadingTip(
      category: '声調',
      title: '子音クラスと声調の関係',
      content: '声調は子音クラス（高・中・低）×母音の長短×末子音×声調記号で決まります。',
    ),
    LoadingTip(
      category: '声調',
      title: '声調を間違えると…',
      content: 'สวย（sǔuai＝美しい）と ซวย（suai＝ついてない）のように声調で意味が激変。',
    ),
    LoadingTip(
      category: '声調',
      title: '平声（sǎa-man）',
      content: '中くらいの高さで平らに発音。中子音＋長母音（声調記号なし）が基本パターン。',
      example: 'กา（kaa＝カラス）、ดี（dii＝良い）',
    ),
    LoadingTip(
      category: '声調',
      title: '上声（jàttawaa）',
      content: '低い音から高い音へ上がる声調。日本語の疑問文の語尾上げに少し似ています。',
      example: 'สวย（sǔuai＝美しい）、หนาว（nǎaw＝寒い）',
    ),
    // --- 子音 ---
    LoadingTip(
      category: '子音',
      title: 'タイ語は44の子音字',
      content: '44文字ありますが、現在使われるのは42文字。発音は21種類に集約されます。',
    ),
    LoadingTip(
      category: '子音',
      title: '高子音（àksɔ̌ɔn sǔung）',
      content: 'ข ฃ ข ฉ ฐ ถ ผ ฝ ศ ษ ส ห の11文字。声調ルールが中・低子音と異なります。',
    ),
    LoadingTip(
      category: '子音',
      title: '中子音（àksɔ̌ɔn klaang）',
      content: 'ก จ ฎ ฏ ด ต บ ป อ の9文字。声調記号がそのまま反映される基本グループ。',
    ),
    LoadingTip(
      category: '子音',
      title: '低子音（àksɔ̌ɔn tàm）',
      content: '残り24文字が低子音。対応する高子音がある「対応字」と「単独字」に分かれます。',
    ),
    LoadingTip(
      category: '子音',
      title: '末子音の発音ルール',
      content: '末子音は k, t, p, n, m, ng, i, o の8音のみ。元の子音と違う音になることも。',
      example: 'บ,ป,พ,ภ,ฟ → 末子音ではすべて -p',
    ),
    LoadingTip(
      category: '子音',
      title: '有気音と無気音',
      content: 'タイ語は息の有無で子音を区別。ป（無気音 p）と พ（有気音 ph）は別の音。',
      example: 'ปลา（plaa＝魚） / พลา（phlaa＝失敗する）',
    ),
    LoadingTip(
      category: '子音',
      title: '黙字記号 ์（kaa-ran）',
      content: '文字の上に付く ์ は「この子音は読まない」という記号。外来語に多いです。',
      example: 'จันทร์（jan＝月） ← ร์ は読まない',
    ),
    LoadingTip(
      category: '子音',
      title: '二重子音（àksɔ̌ɔn khûap）',
      content: '子音が2つ連続する場合、一緒に発音します。kr, kl, pr, pl などのパターン。',
      example: 'กรุง（krung＝都） / ปลา（plaa＝魚）',
    ),
    // --- 数字 ---
    LoadingTip(
      category: '数字',
      title: 'タイ数字',
      content: 'タイには独自の数字があります。๐๑๒๓๔๕๖๗๘๙（0〜9）。看板や公文書で使われます。',
    ),
    LoadingTip(
      category: '数字',
      title: '1〜5の読み方',
      content: '๑ nʉ̀ng、๒ sɔ̌ɔng、๓ sǎam、๔ sìi、๕ hâa',
    ),
    LoadingTip(
      category: '数字',
      title: '6〜10の読み方',
      content: '๖ hòk、๗ jèt、๘ pɛ̀ɛt、๙ kâw、๑๐ sìp',
    ),
    LoadingTip(
      category: '数字',
      title: '11と21の特殊な読み方',
      content: '11は sìp èt、21は yîi sìp èt。1の位と2の十の位が特殊。',
    ),
    LoadingTip(
      category: '数字',
      title: '類別詞（láksanànaam）',
      content: '数を数えるとき「数詞＋類別詞」が必要。日本語の「〜本」「〜枚」と同じ仕組み。',
      example: 'khon（人）、tua（動物）、an（小物）',
    ),
    LoadingTip(
      category: '数字',
      title: '百・千・万の位',
      content: 'rɔ́ɔi（百）、phan（千）、mʉ̀ʉn（万）、sǎen（十万）、láan（百万）',
    ),
    LoadingTip(
      category: '数字',
      title: '値段の聞き方',
      content: '「いくらですか？」は thâo rài。raakhaa（価格）と合わせて覚えましょう。',
      example: 'an-níi thâo rài（これいくら？）',
    ),
    // --- 挨拶・日常表現 ---
    LoadingTip(
      category: '日常表現',
      title: 'ครับ / ค่ะ（khráp / khâ）',
      content: '男性は khráp（ครับ）、女性は khâ（ค่ะ）を文末に付けて丁寧にします。タイ語の基本マナー。',
      example: 'khɔ̀ɔp khun khráp / khɔ̀ɔp khun khâ',
    ),
    LoadingTip(
      category: '日常表現',
      title: 'สวัสดี（sà-wàt-dii）',
      content: '「こんにちは」朝昼夜いつでも使える万能挨拶。別れ際にも使います。',
    ),
    LoadingTip(
      category: '日常表現',
      title: 'ขอบคุณ（khɔ̀ɔp khun）',
      content: '「ありがとう」。khɔ̀ɔp khun mâak で「大変ありがとう」。',
    ),
    LoadingTip(
      category: '日常表現',
      title: 'ขอโทษ（khɔ̌ɔ thôot）',
      content: '「すみません・ごめんなさい」。謝罪にも呼びかけにも使えます。',
    ),
    LoadingTip(
      category: '日常表現',
      title: 'ใช่ / ไม่ใช่（châi / mâi châi）',
      content: '「はい / いいえ」。確認に対する返答に使います。',
      example: 'châi mǎi（そうですか？）→ châi khráp（はい）',
    ),
    LoadingTip(
      category: '日常表現',
      title: 'กิน（kin）＝食べる',
      content: '「ご飯食べた？」kin khâao rʉ̌ʉ yang はタイの定番挨拶です。',
    ),
    LoadingTip(
      category: '日常表現',
      title: 'อร่อย（à-ròi）＝おいしい',
      content: 'タイ料理を食べたら à-ròi！mâak を付けると「とてもおいしい」。',
    ),
    LoadingTip(
      category: '日常表現',
      title: '人称代名詞の使い分け',
      content: 'phǒm（僕）は男性、dì-chǎn（私）は女性のフォーマルな一人称。',
      example: 'カジュアルでは rao や chǎn も使います',
    ),
  ];
}
