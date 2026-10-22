// =============================================================================
// store_mock_data.dart
// ストア用スクショに描く例文・クイズの見本データ（ja / en / ko）。
// 配信docと同じ形の JSON なので DailySentenceService.toSentence に通せる。
// =============================================================================

import 'package:thai_memo/core/constants/generation_constants.dart';

/// 例文のタイ語。発音練習の合成音声もこの並びから作る。
const String storeThaiText = 'ร้านนี้อร่อยมากเลยนะ';

/// 発音練習で「惜しい」にする語（อร่อย の2音節目）。
const int storeMissedSyllable = 3;

/// まとめクイズの穴にする語。
const String storeBlankWord = 'อร่อย';

/// ja・en・ko の3つから [lang] のものを選ぶ。
String _pick(String lang, String ja, String en, String ko) =>
    switch (lang) { 'ja' => ja, 'ko' => ko, _ => en };

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
