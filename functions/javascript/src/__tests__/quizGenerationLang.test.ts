import {
  buildQuizGenerationPrompt,
  quizGenerationSystemPrompt,
  quizResponseSchema,
  QUIZ_GENERATION_SYSTEM_PROMPT,
  QUIZ_RESPONSE_JSON_SCHEMA,
  QuizSentenceSeed,
} from '../services/quizGenerationService';

const seed: QuizSentenceSeed = {
  thai_text: 'ฉันกินข้าว',
  pronunciation: 'chǎn kin khâao',
  japanese_translation: 'I eat rice.',
  key_word: 'กิน',
  key_word_pronunciation: 'kin',
  key_word_meaning: 'to eat',
};

describe('クイズプロンプトの言語分岐', () => {
  it('lang を指定しない呼び出しは ja（旧クライアント・既存コードの経路）', () => {
    expect(quizGenerationSystemPrompt('ja')).toBe(QUIZ_GENERATION_SYSTEM_PROMPT);
    expect(quizResponseSchema('ja')).toBe(QUIZ_RESPONSE_JSON_SCHEMA);
    expect(buildQuizGenerationPrompt([seed])).toBe(
      buildQuizGenerationPrompt([seed], 'ja'),
    );
  });

  it('ja のプロンプトの言語指定行が既存の文言のまま', () => {
    const ja = QUIZ_GENERATION_SYSTEM_PROMPT;
    expect(ja).toContain(
      '- explanation: correct_answer が入る理由だけを日本語で簡潔に書く。ダミーには触れない',
    );
    expect(ja).toContain(
      '- dummy_reasons: 各ダミーを「単語（ローマ字 / 日本語）：不正解理由」の形式で1行ずつ書く',
    );
    expect(ja).toContain('- 日本語訳、話者性別、敬意、人称だけで区別する語は不可');
    expect(ja).toContain(
      '日本語訳・語句・発音・解説なしでも、周辺タイ語だけで3ダミーを除外できる必要がある。',
    );
    expect(ja).toContain('- แกง（kɛɛng / カレー）：動詞の位置に名詞が入り文法上不自然');
  });

  it('en は解説とダミー理由を英語で書かせる', () => {
    const en = quizGenerationSystemPrompt('en');
    expect(en).toContain('explanation: correct_answer が入る理由だけを英語で簡潔に書く');
    expect(en).toContain('"word (romaji / English meaning): reason"');
    // ja の指定が混ざらない
    expect(en).not.toContain('日本語で簡潔に書く');
    expect(en).not.toContain('「単語（ローマ字 / 日本語）：不正解理由」');
  });

  it('en のダミー理由の書式は括弧とスラッシュを保つ', () => {
    // extractDummyPronunciation がこの形から選択肢の発音を切り出す。
    // 崩すと4択の発音表示が空になる。
    const en = quizGenerationSystemPrompt('en');
    for (const line of ['แกง (kɛɛng / curry)', 'เบื่อ (bʉ̀a / to be bored)']) {
      expect(en).toContain(line);
    }
  });

  it('en の禁止表現は英語の文字列である', () => {
    // 禁止表現は生成物に対する検査語なので、出力言語で書かないと機能しない。
    const en = quizGenerationSystemPrompt('en');
    expect(en).toContain('"does not fit"');
    expect(en).toContain('"more natural"');
  });

  it('タイ語だけの NG 例は言語で分けない', () => {
    const ja = QUIZ_GENERATION_SYSTEM_PROMPT;
    const en = quizGenerationSystemPrompt('en');
    for (const line of ['- กิน___ → ข้าว/ผัก/เนื้อ は全て目的語として成立']) {
      expect(ja).toContain(line);
      expect(en).toContain(line);
    }
  });

  it('en のスキーマは英語を要求し、構造は ja と同じ', () => {
    const en = quizResponseSchema('en');
    expect(en.properties.explanation.description).toContain('in English');
    expect(en.properties.dummy_reasons.description).toContain('in English');
    expect(en.required).toEqual(QUIZ_RESPONSE_JSON_SCHEMA.required);
    // 共有定数を書き換えていない
    expect(QUIZ_RESPONSE_JSON_SCHEMA.properties.explanation.description).toContain(
      'in Japanese',
    );
  });

  it('en では訳文のラベルを「日本語訳」にしない', () => {
    // japanese_translation の中身は lang に従った訳文。ラベルまで日本語だと
    // 英訳を「日本語訳」だと言ってモデルに渡すことになる。
    expect(buildQuizGenerationPrompt([seed], 'en')).toContain('translation: I eat rice.');
    expect(buildQuizGenerationPrompt([seed], 'en')).not.toContain('日本語訳:');
    expect(buildQuizGenerationPrompt([seed], 'ja')).toContain('日本語訳: I eat rice.');
  });
});
