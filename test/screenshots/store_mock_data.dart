// =============================================================================
// store_mock_data.dart
// ストア用スクショに描く例文・クイズの見本データ（ja / en / ko）。
// 配信docと同じ形の JSON なので DailySentenceService.toSentence に通せる。
// =============================================================================

import 'package:thai_memo/core/constants/generation_constants.dart';
import 'package:thai_memo/data/models/vocab_word.dart';

/// 描く見本の組。`--dart-define=SET=travel` / `SET=work` でカスタムプロダクトページ用の
/// 例文（旅行・仕事）に替える。空なら既定のページ用（食べ物の例文）。
const String storeSet = String.fromEnvironment('SET');

/// 例文のタイ語。発音練習の合成音声もこの並びから作る。
String get storeThaiText => switch (storeSet) {
      'travel' => 'ช่วยไปส่งที่โรงแรมนี้หน่อยได้ไหมครับ',
      'work' => 'ขอเลื่อนประชุมเป็นบ่ายสามได้ไหมครับ',
      _ => 'ร้านนี้อร่อยมากเลยนะ',
    };

/// 発音練習で「惜しい」にする音節（文頭からの番号）と、その音節を含む語の番号。
/// 既定は อร่อย の2音節目、旅行は ไป、仕事は เลื่อน。
int get storeMissedSyllable =>
    switch (storeSet) { 'travel' => 1, 'work' => 1, _ => 3 };
int get storeMissedWord =>
    switch (storeSet) { 'travel' => 1, 'work' => 1, _ => 2 };

/// まとめクイズの穴にする語。
String get storeBlankWord => switch (storeSet) {
      'travel' => 'โรงแรม',
      'work' => 'เลื่อน',
      _ => 'อร่อย',
    };

/// 文字の解説を開く語（1音節で、頭子音・母音・末子音・声調記号がそろうもの）。
String get storeExplainedWord => switch (storeSet) {
      'travel' => 'ส่ง',
      'work' => 'เลื่อน',
      _ => 'ร้าน',
    };

/// ja・en・ko の3つから [lang] のものを選ぶ。
String _pick(String lang, String ja, String en, String ko) =>
    switch (lang) { 'ja' => ja, 'ko' => ko, _ => en };

typedef _Word = Map<String, dynamic> Function(
  String text,
  String pronunciation,
  List<String> syllables,
  List<String> meaning,
  List<String> role, {
  List<String> notes,
});

Map<String, dynamic> storeSentenceJson(String lang) {
  String t(String ja, String en, String ko) => _pick(lang, ja, en, ko);
  Map<String, dynamic> word(
    String text,
    String pronunciation,
    List<String> syllables,
    List<String> meaning,
    List<String> role, {
    List<String> notes = const ['', '', ''],
  }) =>
      {
        'word': text,
        'pronunciation': pronunciation,
        'syllables': syllables,
        'meaning': t(meaning[0], meaning[1], meaning[2]),
        'grammatical_role': t(role[0], role[1], role[2]),
        'notes': t(notes[0], notes[1], notes[2]),
      };

  if (storeSet == 'travel') return _travelSentence(lang, t, word);
  if (storeSet == 'work') return _workSentence(lang, t, word);
  return {
    'thai_text': storeThaiText,
    'pronunciation': 'ráan níi à-rɔ̀i mâak ləəi ná',
    'japanese_translation':
        t('このお店、本当においしいね。', 'This place is really delicious!', '이 가게 정말 맛있네.'),
    'word_breakdown': [
      word('ร้าน', 'ráan', ['ร้าน'], ['店', 'shop, restaurant', '가게'],
          ['名詞', 'noun', '명사']),
      word('นี้', 'níi', ['นี้'], ['この', 'this', '이'],
          ['限定詞', 'determiner', '관형사']),
      word(
        'อร่อย',
        'à-rɔ̀i',
        ['อ', 'ร่อย'],
        ['おいしい', 'delicious', '맛있다'],
        ['形容詞', 'adjective', '형용사'],
        notes: [
          '食べ物の味をほめる、いちばん基本の言葉。屋台でもレストランでも使える。',
          'The most basic word for praising food. Works at street stalls and restaurants alike.',
          '음식 맛을 칭찬하는 가장 기본적인 말. 노점에서도 레스토랑에서도 쓸 수 있어요.',
        ],
      ),
      word('มาก', 'mâak', ['มาก'], ['とても', 'very', '아주'],
          ['副詞', 'adverb', '부사']),
      word('เลย', 'ləəi', ['เลย'], ['本当に（強調）', 'really (emphasis)', '정말(강조)'],
          ['助詞', 'particle', '조사']),
      word('นะ', 'ná', ['นะ'], ['〜ね', '(softens the tone)', '~네(어조를 부드럽게)'],
          ['文末詞', 'sentence-final particle', '문말 조사']),
    ],
    'context': {
      'topic': GenerationConstants.topics[4],
      'style':
          t('友達同士のくだけた口語', 'Casual speech between friends', '친구끼리 쓰는 편한 구어체'),
      'emotion': t('満足・うれしさ', 'Satisfied, happy', '만족, 기쁨'),
      'usage_scenarios': t(
        '屋台やレストランで食べながら、一緒にいる友達に感想を伝えるとき。',
        'Telling a friend what you think while eating at a stall or restaurant.',
        '노점이나 식당에서 먹으면서 함께 있는 친구에게 소감을 말할 때.',
      ),
      'cultural_notes': t(
        'タイでは食事中に味をほめ合うのが自然な会話のきっかけになる。',
        'In Thailand, praising the food is a natural way to start a conversation over a meal.',
        '태국에서는 식사 중에 맛을 칭찬하는 것이 자연스러운 대화의 계기가 돼요.',
      ),
    },
    'key_word': storeBlankWord,
    'generation_tier': 'premium',
    'lang': lang,
    'created_at': '2026-10-06T09:41:00+09:00',
  };
}

/// まとめクイズ（穴埋め4択）の1問。
Map<String, dynamic> storeQuizJson(String lang) {
  String t(String ja, String en, String ko) => _pick(lang, ja, en, ko);
  if (storeSet == 'travel') return _travelQuiz(t);
  if (storeSet == 'work') return _workQuiz(t);
  return {
    'sentence_id': 'store-sentence',
    'thai_text': storeThaiText,
    'blank_text': 'ร้านนี้___มากเลยนะ',
    'correct_answer': storeBlankWord,
    'correct_answer_meaning': t('おいしい', 'delicious', '맛있다'),
    'choices': ['สวย', storeBlankWord, 'ไกล', 'แพง'],
    'choice_pronunciations': ['sǔai', 'à-rɔ̀i', 'klai', 'phɛɛng'],
    'pronunciation': 'à-rɔ̀i',
    'explanation': t(
      '「มาก（とても）」の前に入り、店の料理をほめる語が必要。สวย（きれい）・ไกล（遠い）・แพง（高い）では「本当に〜ね」と喜ぶ文脈に合わない。',
      'The blank needs a word that praises the food before มาก (very). สวย (beautiful), ไกล (far) and แพง (expensive) don\'t fit the happy tone.',
      '빈칸에는 มาก(아주) 앞에서 가게 음식을 칭찬하는 말이 들어가야 해요. สวย(예쁘다)・ไกล(멀다)・แพง(비싸다)는 "정말 ~네"라며 기뻐하는 문맥에 맞지 않아요.',
    ),
    'japanese_translation':
        t('このお店、本当においしいね。', 'This place is really delicious!', '이 가게 정말 맛있네.'),
    'sentence_pronunciation': 'ráan níi à-rɔ̀i mâak ləəi ná',
    'blank_sentence_pronunciation': 'ráan níi ___ mâak ləəi ná',
    'quiz_format': 'cloze_choice',
  };
}

typedef _T = String Function(String ja, String en, String ko);

/// 旅行のページ用。タクシーで行き先のホテルを頼む。
Map<String, dynamic> _travelSentence(String lang, _T t, _Word word) => {
      'thai_text': storeThaiText,
      'pronunciation': 'chûai pai sòng thîi roong-rɛɛm níi nɔ̀i dâai mǎi khráp',
      'japanese_translation': t(
        'このホテルまで送ってもらえますか？',
        'Could you take me to this hotel, please?',
        '이 호텔까지 데려다주실 수 있나요?',
      ),
      'word_breakdown': [
        word('ช่วย', 'chûai', ['ช่วย'], ['〜してください（依頼）', 'please (asking for help)', '~해 주세요(부탁)'],
            ['動詞', 'verb', '동사']),
        word('ไป', 'pai', ['ไป'], ['行く', 'to go', '가다'], ['動詞', 'verb', '동사']),
        word(
          'ส่ง',
          'sòng',
          ['ส่ง'],
          ['送る', 'to drop off', '데려다주다'],
          ['動詞', 'verb', '동사'],
          notes: [
            'ไปส่ง で「（車で）送っていく」。タクシーで行き先を頼むときの定番。',
            'ไปส่ง means "take someone somewhere". The go-to phrase for telling a taxi where to go.',
            'ไปส่ง은 "(차로) 데려다주다". 택시에서 목적지를 말할 때 늘 쓰는 표현이에요.',
          ],
        ),
        word('ที่', 'thîi', ['ที่'], ['〜まで、〜に', 'to, at', '~까지, ~에'],
            ['前置詞', 'preposition', '전치사']),
        word('โรงแรม', 'roong-rɛɛm', ['โรง', 'แรม'], ['ホテル', 'hotel', '호텔'],
            ['名詞', 'noun', '명사']),
        word('นี้', 'níi', ['นี้'], ['この', 'this', '이'],
            ['限定詞', 'determiner', '관형사']),
        word('หน่อย', 'nɔ̀i', ['หน่อย'], ['ちょっと（頼みをやわらげる）', 'a little (softens a request)', '좀(부탁을 부드럽게)'],
            ['副詞', 'adverb', '부사']),
        word('ได้', 'dâai', ['ได้'], ['できる', 'can', '할 수 있다'],
            ['助動詞', 'auxiliary verb', '조동사']),
        word('ไหม', 'mǎi', ['ไหม'], ['〜か？（疑問）', '(question marker)', '~까?(의문)'],
            ['疑問詞', 'question particle', '의문 조사']),
        word('ครับ', 'khráp', ['ครับ'], ['（丁寧・男性）', '(polite, male speaker)', '(공손, 남성)'],
            ['文末詞', 'sentence-final particle', '문말 조사']),
      ],
      'context': {
        'topic': GenerationConstants.travelTopic,
        'style': t('丁寧な頼み', 'Polite request', '공손한 부탁'),
        'emotion': t('ていねい・少し遠慮', 'Polite, a little reserved', '공손함, 약간 조심스러움'),
        'usage_scenarios': t(
          'タクシーやバイクタクシーで、ホテルの地図や住所を見せながら運転手に行き先を頼むとき。',
          'Showing the driver a map or address of your hotel in a taxi or on a motorbike taxi.',
          '택시나 오토바이 택시에서 호텔 지도나 주소를 보여 주며 기사에게 목적지를 부탁할 때.',
        ),
        'cultural_notes': t(
          'タイのタクシーではホテル名だけだと伝わりにくい。地図や住所を見せて นี้（この）で示すと確実。',
          'Hotel names alone often don\'t get through to Thai taxi drivers. Point to a map or address and say นี้ (this).',
          '태국 택시에서는 호텔 이름만으로는 잘 안 통해요. 지도나 주소를 보여 주며 นี้(이)로 가리키면 확실해요.',
        ),
      },
      'key_word': storeBlankWord,
      'generation_tier': 'premium',
      'lang': lang,
      'created_at': '2026-10-06T09:41:00+09:00',
    };

Map<String, dynamic> _travelQuiz(_T t) => {
      'sentence_id': 'store-sentence',
      'thai_text': storeThaiText,
      'blank_text': 'ช่วยไปส่งที่___นี้หน่อยได้ไหมครับ',
      'correct_answer': storeBlankWord,
      'correct_answer_meaning': t('ホテル', 'hotel', '호텔'),
      'choices': ['อร่อย', storeBlankWord, 'ช้า', 'แพง'],
      'choice_pronunciations': ['à-rɔ̀i', 'roong-rɛɛm', 'cháa', 'phɛɛng'],
      'pronunciation': 'roong-rɛɛm',
      'explanation': t(
        'ที่（〜まで）の後には行き先になる場所の名詞が入る。อร่อย（おいしい）・ช้า（遅い）・แพง（高い）は様子を表す語で、行き先にならない。',
        'After ที่ (to) comes a place you\'re going. อร่อย (delicious), ช้า (slow) and แพง (expensive) describe things and can\'t be a destination.',
        'ที่(~까지) 뒤에는 목적지가 되는 장소 명사가 와요. อร่อย(맛있다)・ช้า(느리다)・แพง(비싸다)는 상태를 나타내는 말이라 목적지가 될 수 없어요.',
      ),
      'japanese_translation': t(
        'このホテルまで送ってもらえますか？',
        'Could you take me to this hotel, please?',
        '이 호텔까지 데려다주실 수 있나요?',
      ),
      'sentence_pronunciation':
          'chûai pai sòng thîi roong-rɛɛm níi nɔ̀i dâai mǎi khráp',
      'blank_sentence_pronunciation':
          'chûai pai sòng thîi ___ níi nɔ̀i dâai mǎi khráp',
      'quiz_format': 'cloze_choice',
    };

/// 仕事のページ用。会議の時間をずらしてもらう。
Map<String, dynamic> _workSentence(String lang, _T t, _Word word) => {
      'thai_text': storeThaiText,
      'pronunciation': 'khɔ̌ɔ lʉ̂an prà-chum pen bàai sǎam dâai mǎi khráp',
      'japanese_translation': t(
        '会議を午後3時にずらしてもいいですか？',
        'Could we move the meeting to 3 p.m.?',
        '회의를 오후 3시로 미뤄도 될까요?',
      ),
      'word_breakdown': [
        word('ขอ', 'khɔ̌ɔ', ['ขอ'], ['〜させてください（お願い）', 'may I, please', '~하게 해 주세요(부탁)'],
            ['動詞', 'verb', '동사']),
        word(
          'เลื่อน',
          'lʉ̂an',
          ['เลื่อน'],
          ['ずらす、延期する', 'to move, to postpone', '미루다, 옮기다'],
          ['動詞', 'verb', '동사'],
          notes: [
            '予定を前後にずらす。เลื่อน〜เป็น… で「〜を…にずらす」。',
            'Shifts a plan earlier or later. เลื่อน X เป็น Y means "move X to Y".',
            '일정을 앞뒤로 옮겨요. เลื่อน~เป็น…는 "~를 …로 옮기다".',
          ],
        ),
        word('ประชุม', 'prà-chum', ['ประ', 'ชุม'], ['会議', 'meeting', '회의'],
            ['名詞', 'noun', '명사']),
        word('เป็น', 'pen', ['เป็น'], ['〜に（変える先）', 'to (the new time)', '~로(바꿀 대상)'],
            ['前置詞', 'preposition', '전치사']),
        word('บ่าย', 'bàai', ['บ่าย'], ['午後', 'afternoon', '오후'],
            ['名詞', 'noun', '명사']),
        word('สาม', 'sǎam', ['สาม'], ['3（時）', 'three (o\'clock)', '3(시)'],
            ['数詞', 'number', '수사']),
        word('ได้', 'dâai', ['ได้'], ['できる', 'can', '할 수 있다'],
            ['助動詞', 'auxiliary verb', '조동사']),
        word('ไหม', 'mǎi', ['ไหม'], ['〜か？（疑問）', '(question marker)', '~까?(의문)'],
            ['疑問詞', 'question particle', '의문 조사']),
        word('ครับ', 'khráp', ['ครับ'], ['（丁寧・男性）', '(polite, male speaker)', '(공손, 남성)'],
            ['文末詞', 'sentence-final particle', '문말 조사']),
      ],
      'context': {
        'topic': GenerationConstants.topics[2],
        'style': t('職場での丁寧な頼み', 'Polite request at work', '직장에서의 공손한 부탁'),
        'emotion': t('ていねい・少し申し訳なさ', 'Polite, a little apologetic', '공손함, 약간 미안함'),
        'usage_scenarios': t(
          '上司や取引先に、予定していた会議を午後3時に変えてほしいと頼むとき。',
          'Asking your boss or a client to move a scheduled meeting to 3 p.m.',
          '상사나 거래처에 예정된 회의를 오후 3시로 바꿔 달라고 부탁할 때.',
        ),
        'cultural_notes': t(
          'タイの職場では ขอ〜ได้ไหม で切り出すと、角の立たない丁寧な頼み方になる。',
          'At Thai workplaces, opening with ขอ … ได้ไหม keeps a request polite and soft.',
          '태국 직장에서는 ขอ~ได้ไหม로 말을 꺼내면 부드럽고 공손한 부탁이 돼요.',
        ),
      },
      'key_word': storeBlankWord,
      'generation_tier': 'premium',
      'lang': lang,
      'created_at': '2026-10-06T09:41:00+09:00',
    };

Map<String, dynamic> _workQuiz(_T t) => {
      'sentence_id': 'store-sentence',
      'thai_text': storeThaiText,
      'blank_text': 'ขอ___ประชุมเป็นบ่ายสามได้ไหมครับ',
      'correct_answer': storeBlankWord,
      'correct_answer_meaning': t('ずらす', 'to move', '미루다'),
      'choices': ['หิว', storeBlankWord, 'สวย', 'ไกล'],
      'choice_pronunciations': ['hǐu', 'lʉ̂an', 'sǔai', 'klai'],
      'pronunciation': 'lʉ̂an',
      'explanation': t(
        'ประชุม（会議）を受けて、時間を動かす動詞が要る。หิว（おなかがすいた）・สวย（きれい）・ไกล（遠い）は様子を表す語で、会議を動かせない。',
        'The blank needs a verb that moves ประชุม (the meeting) to a new time. หิว (hungry), สวย (beautiful) and ไกล (far) describe things and can\'t move a meeting.',
        'ประชุม(회의)를 받아 시간을 옮기는 동사가 필요해요. หิว(배고프다)・สวย(예쁘다)・ไกล(멀다)는 상태를 나타내는 말이라 회의를 옮길 수 없어요.',
      ),
      'japanese_translation': t(
        '会議を午後3時にずらしてもいいですか？',
        'Could we move the meeting to 3 p.m.?',
        '회의를 오후 3시로 미뤄도 될까요?',
      ),
      'sentence_pronunciation':
          'khɔ̌ɔ lʉ̂an prà-chum pen bàai sǎam dâai mǎi khráp',
      'blank_sentence_pronunciation':
          'khɔ̌ɔ ___ prà-chum pen bàai sǎam dâai mǎi khráp',
      'quiz_format': 'cloze_choice',
    };

/// 復習タブで画面に映る語（語彙ランクの大きい順）。p が 0 の語は「見ただけ」。
const List<(String, int, String, String, String, String, double)> _reviewWords = [
  ('ค่อย', 650, 'khɔ̂i', 'だんだん', 'gradually', '점점', 0),
  ('นักเรียน', 648, 'nák-rian', '生徒', 'student', '학생', 0.42),
  ('ป้า', 647, 'pâa', 'おば', 'aunt', '이모', 0),
  ('หนุ่ม', 644, 'nùm', '若い男性', 'young man', '젊은 남자', 0.38),
  ('เงียบ', 642, 'ngîap', '静かな', 'quiet', '조용하다', 0.46),
  ('ถนน', 629, 'thà-nǒn', '道路', 'road', '도로', 0.82),
  ('ประเทศ', 626, 'prà-thêet', '国', 'country', '나라', 0.94),
  ('กระเป๋า', 623, 'krà-pǎo', 'かばん', 'bag', '가방', 0.74),
  ('เดินทาง', 621, 'dəən-thaang', '旅行する', 'to travel', '여행하다', 0.34),
  ('สบาย', 619, 'sà-baai', '快適な', 'comfortable', '편안하다', 0.88),
  ('มั่นใจ', 610, 'mân-jai', '自信がある', 'confident', '자신 있다', 0),
  ('ไกล', 609, 'klai', '遠い', 'far', '멀다', 0.9),
  ('อันตราย', 605, 'an-tà-raai', '危険な', 'dangerous', '위험하다', 0.66),
  ('ปกติ', 604, 'pòk-kà-tì', '普通の', 'normal', '보통', 0.71),
  ('คำถาม', 598, 'kham-thǎam', '質問', 'question', '질문', 0.78),
  ('ภาพ', 596, 'phâap', '絵、画像', 'picture', '그림', 0.44),
  ('ร้องไห้', 595, 'rɔ́ɔng-hâi', '泣く', 'to cry', '울다', 0.85),
  ('ตก', 593, 'tòk', '落ちる', 'to fall', '떨어지다', 0.79),
  ('หนัง', 583, 'nǎng', '映画', 'movie', '영화', 0.92),
  ('อาทิตย์', 576, 'aa-thít', '週', 'week', '주', 0.87),
  ('ตอบ', 575, 'tɔ̀ɔp', '答える', 'to answer', '대답하다', 0.76),
];

/// 復習タブの一覧。画面に映らない前後は埋め草で、上の集計の語数と割合だけを作る。
List<VocabEntry> storeVocabEntries(String lang) {
  VocabEntry filler(int rank, double p) => VocabEntry(
        progress: VocabWord(word: 'w$rank', rank: rank, p: p, answered: p > 0),
      );
  return [
    // スコアより上の語は、まだ見ただけ・覚えかけが多い。
    for (var i = 0; i < 30; i++) filler(1200 - i * 18, i.isEven ? 0 : 0.4),
    for (final (word, rank, pronunciation, ja, en, ko, p) in _reviewWords)
      VocabEntry(
        progress: VocabWord(word: word, rank: rank, p: p, answered: p > 0),
        pronunciation: pronunciation,
        meaning: _pick(lang, ja, en, ko),
      ),
    // スコアより下の語は、ほとんど覚えている。
    for (var i = 0; i < 260; i++) filler(560 - i * 2, i % 5 == 0 ? 0.4 : 0.8),
  ];
}
