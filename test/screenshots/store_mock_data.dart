// =============================================================================
// store_mock_data.dart
// ストア用スクショに描く例文・クイズの見本データ（ja / en）。
// 配信docと同じ形の JSON なので DailySentenceService.toSentence に通せる。
// =============================================================================

import 'package:thai_memo/core/constants/generation_constants.dart';

/// 例文のタイ語。発音練習の合成音声もこの並びから作る。
const String storeThaiText = 'ร้านนี้อร่อยมากเลยนะ';

/// 発音練習で「惜しい」にする語（อร่อย の2音節目）。
const int storeMissedSyllable = 3;

/// まとめクイズの穴にする語。
const String storeBlankWord = 'อร่อย';

Map<String, dynamic> storeSentenceJson(String lang) {
  final ja = lang == 'ja';
  Map<String, dynamic> word(
    String text,
    String pronunciation,
    List<String> syllables,
    String meaningJa,
    String meaningEn,
    String roleJa,
    String roleEn, {
    String notesJa = '',
    String notesEn = '',
  }) =>
      {
        'word': text,
        'pronunciation': pronunciation,
        'syllables': syllables,
        'meaning': ja ? meaningJa : meaningEn,
        'grammatical_role': ja ? roleJa : roleEn,
        'notes': ja ? notesJa : notesEn,
      };

  return {
    'thai_text': storeThaiText,
    'pronunciation': 'ráan níi à-rɔ̀i mâak ləəi ná',
    'japanese_translation':
        ja ? 'このお店、本当においしいね。' : 'This place is really delicious!',
    'word_breakdown': [
      word('ร้าน', 'ráan', ['ร้าน'], '店', 'shop, restaurant', '名詞', 'noun'),
      word('นี้', 'níi', ['นี้'], 'この', 'this', '限定詞', 'determiner'),
      word(
        'อร่อย',
        'à-rɔ̀i',
        ['อ', 'ร่อย'],
        'おいしい',
        'delicious',
        '形容詞',
        'adjective',
        notesJa: '食べ物の味をほめる、いちばん基本の言葉。屋台でもレストランでも使える。',
        notesEn:
            'The most basic word for praising food. Works at street stalls and restaurants alike.',
      ),
      word('มาก', 'mâak', ['มาก'], 'とても', 'very', '副詞', 'adverb'),
      word('เลย', 'ləəi', ['เลย'], '本当に（強調）', 'really (emphasis)', '助詞',
          'particle'),
      word('นะ', 'ná', ['นะ'], '〜ね', '(softens the tone)', '文末詞',
          'sentence-final particle'),
    ],
    'context': {
      'topic': GenerationConstants.topics[4],
      'style': ja ? '友達同士のくだけた口語' : 'Casual speech between friends',
      'emotion': ja ? '満足・うれしさ' : 'Satisfied, happy',
      'usage_scenarios': ja
          ? '屋台やレストランで食べながら、一緒にいる友達に感想を伝えるとき。'
          : 'Telling a friend what you think while eating at a stall or restaurant.',
      'cultural_notes': ja
          ? 'タイでは食事中に味をほめ合うのが自然な会話のきっかけになる。'
          : 'In Thailand, praising the food is a natural way to start a conversation over a meal.',
    },
    'key_word': storeBlankWord,
    'generation_tier': 'premium',
    'lang': lang,
    'created_at': '2026-10-06T09:41:00+09:00',
  };
}

/// まとめクイズ（穴埋め4択）の1問。
Map<String, dynamic> storeQuizJson(String lang) {
  final ja = lang == 'ja';
  return {
    'sentence_id': 'store-sentence',
    'thai_text': storeThaiText,
    'blank_text': 'ร้านนี้___มากเลยนะ',
    'correct_answer': storeBlankWord,
    'correct_answer_meaning': ja ? 'おいしい' : 'delicious',
    'choices': ['สวย', storeBlankWord, 'ไกล', 'แพง'],
    'choice_pronunciations': ['sǔai', 'à-rɔ̀i', 'klai', 'phɛɛng'],
    'pronunciation': 'à-rɔ̀i',
    'explanation': ja
        ? '「มาก（とても）」の前に入り、店の料理をほめる語が必要。สวย（きれい）・ไกล（遠い）・แพง（高い）では「本当に〜ね」と喜ぶ文脈に合わない。'
        : 'The blank needs a word that praises the food before มาก (very). สวย (beautiful), ไกล (far) and แพง (expensive) don\'t fit the happy tone.',
    'japanese_translation':
        ja ? 'このお店、本当においしいね。' : 'This place is really delicious!',
    'sentence_pronunciation': 'ráan níi à-rɔ̀i mâak ləəi ná',
    'blank_sentence_pronunciation': 'ráan níi ___ mâak ləəi ná',
    'quiz_format': 'cloze_choice',
  };
}
