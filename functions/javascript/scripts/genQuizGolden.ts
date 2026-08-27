/**
 * genQuizGolden.ts — クイズ生成のプロンプトと整形処理の期待値を JS 実装から書き出す。
 *
 * Go 版 internal/quizgen との差分テストに使う。
 * 出力先: functions/javascript/scripts/quiz_golden.json
 */
import * as fs from 'fs';
import * as path from 'path';
import {
  quizGenerationSystemPrompt,
  buildQuizGenerationPrompt,
  prepareQuizGenerationInputs,
  isQuizSentenceSeedReady,
  applyRuleBasedQuizFields,
  sanitizeQuizQuestion,
  buildBlankSentencePronunciation,
  QuizSentenceSeed,
  GeneratedQuizQuestion,
} from '../src/services/quizGenerationService';

/* eslint-disable @typescript-eslint/no-explicit-any */

// shuffleChoices は Math.random に依存する。差分を取るため恒等にする。
// （並べ替えそのものは検査対象ではない。順序に依存する
//  choice_pronunciations の対応付けだけが見たい）
const realRandom = Math.random;
Math.random = () => 0.5; // sort のコンパレータが常に 0 → 元の順序が保たれる

/** 再現可能な擬似乱数（mulberry32） */
function rng(seed: number) {
  return function () {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = rng(20260827);
const pick = <T>(xs: T[]): T => xs[Math.floor(rand() * xs.length)];

const THAI_WORDS = ['กิน', 'ข้าว', 'ไป', 'ตลาด', 'แมว', 'สวย', 'เร็ว', 'บ้าน', 'น้ำ', 'ครับ'];
const ROMAJI = ['kin', 'khâao', 'pai', 'talàat', 'mɛɛo', 'sǔai', 'reo', 'bâan', 'náam', 'khráp'];
const MEANINGS = ['食べる', 'ご飯', '行く', '市場', '猫', '美しい', '速い', '家', '水', 'です'];

// 空白・注釈・非タイ語など、正規化と検査を踏ませるための混ぜ物
const NOISE_PREFIX = ['', '  ', '　', '\n', '﻿'];
const ANNOTATIONS = [
  (w: string, r: string, m: string) => w,
  (w: string, r: string, m: string) => `${w} (${r} / ${m})`,
  (w: string, r: string, m: string) => `${w}（${r} / ${m}）：理由`,
  (w: string, r: string, m: string) => `${w}: ${m}`,
  () => 'not thai at all',
  () => '日本語だけ',
  () => '',
];

type SanitizeCase = {
  input: GeneratedQuizQuestion;
  output: GeneratedQuizQuestion | null;
};

function makeSeed(): QuizSentenceSeed {
  const i = Math.floor(rand() * THAI_WORDS.length);
  const word = THAI_WORDS[i];
  const inSentence = rand() < 0.85;
  const thai = inSentence
    ? `${pick(THAI_WORDS)}${word}${pick(THAI_WORDS)}`
    : `${pick(THAI_WORDS)}${pick(THAI_WORDS)}`;
  const seed: any = {
    thai_text: pick(NOISE_PREFIX) + thai + pick(NOISE_PREFIX),
    pronunciation: `${pick(ROMAJI)} ${ROMAJI[i]} ${pick(ROMAJI)}`,
    japanese_translation: pick(NOISE_PREFIX) + pick(MEANINGS) + pick(NOISE_PREFIX),
  };
  if (rand() < 0.9) seed.key_word = pick(NOISE_PREFIX) + word + pick(NOISE_PREFIX);
  if (rand() < 0.8) seed.key_word_pronunciation = ROMAJI[i];
  if (rand() < 0.7) seed.key_word_meaning = MEANINGS[i];
  return seed as QuizSentenceSeed;
}

async function main() {
  // --- プロンプト（バイト一致で比べる） ---
  const prompts = {
    system_ja: quizGenerationSystemPrompt('ja'),
    system_en: quizGenerationSystemPrompt('en'),
  };

  // --- prepare / ready / applyRuleBasedQuizFields ---
  const prepareCases: any[] = [];
  for (let i = 0; i < 800; i++) {
    const count = 1 + Math.floor(rand() * 3);
    const sentences: QuizSentenceSeed[] = [];
    for (let j = 0; j < count; j++) sentences.push(makeSeed());

    const drafts = sentences.map(() => ({
      dummies: [pick(THAI_WORDS), pick(THAI_WORDS), pick(THAI_WORDS)],
      explanation: pick(NOISE_PREFIX) + '解説' + pick(NOISE_PREFIX),
      dummy_reasons: [
        `${pick(THAI_WORDS)}（${pick(ROMAJI)} / ${pick(MEANINGS)}）：理由1`,
        `${pick(THAI_WORDS)}（${pick(ROMAJI)} / ${pick(MEANINGS)}）：理由2`,
        `${pick(THAI_WORDS)}（${pick(ROMAJI)} / ${pick(MEANINGS)}）：理由3`,
      ],
    }));

    prepareCases.push({
      sentences,
      prepared: prepareQuizGenerationInputs(sentences),
      ready: sentences.map(isQuizSentenceSeedReady),
      user_prompt_ja: buildQuizGenerationPrompt(sentences, 'ja'),
      user_prompt_en: buildQuizGenerationPrompt(sentences, 'en'),
      drafts,
      applied: applyRuleBasedQuizFields({ questions: drafts }, sentences).questions,
    });
  }

  // --- sanitizeQuizQuestion ---
  const sanitizeCases: SanitizeCase[] = [];
  for (let i = 0; i < 1200; i++) {
    const correctIdx = Math.floor(rand() * THAI_WORDS.length);
    const correct = THAI_WORDS[correctIdx];

    // 通過ケースを十分な数だけ作るため、ダミーは互いに異なるものを選ぶ。
    // 注釈は「タイ語が残る形」を多めにし、崩れた形も一定割合で混ぜる。
    const dummyIdx: number[] = [];
    while (dummyIdx.length < 3) {
      const d = Math.floor(rand() * THAI_WORDS.length);
      if (d !== correctIdx && !dummyIdx.includes(d)) dummyIdx.push(d);
    }
    const KEEP_THAI = ANNOTATIONS.slice(0, 4);
    const dummies = dummyIdx.map((d) => {
      const annotate = rand() < 0.8 ? pick(KEEP_THAI) : pick(ANNOTATIONS);
      return annotate(THAI_WORDS[d], ROMAJI[d], MEANINGS[d]);
    });

    // 理由は「対応するダミーを含むもの」を確率的に欠落させる
    const reasons: string[] = [];
    for (const d of dummyIdx) {
      const roll = rand();
      if (roll < 0.75) {
        const bracket = rand() < 0.6 ? ['（', '）'] : ['(', ')'];
        reasons.push(
          `${THAI_WORDS[d]}${bracket[0]}${ROMAJI[d]} / ${MEANINGS[d]}${bracket[1]}：理由`
        );
      } else if (roll < 0.92) {
        // 括弧の書式が崩れた理由。ダミー自体は含むので理由の対応は取れるが、
        // 発音は切り出せず空になる。
        reasons.push(`${THAI_WORDS[d]}：括弧なしの理由`);
      } else if (rand() < 0.5) {
        reasons.push(`関係のない理由 ${i}-${d}`);
      }
    }

    const input: any = {
      source_index: rand() < 0.9 ? i % 3 : undefined,
      thai_text: pick(NOISE_PREFIX) + pick(THAI_WORDS) + correct + pick(NOISE_PREFIX),
      blank_text: `${pick(THAI_WORDS)}___`,
      correct_answer: rand() < 0.8
        ? correct
        : pick(ANNOTATIONS)(correct, ROMAJI[correctIdx], MEANINGS[correctIdx]),
      choices: dummies,
      choice_pronunciations: [],
      pronunciation: rand() < 0.9
        ? pick(NOISE_PREFIX) + ROMAJI[correctIdx] + pick(NOISE_PREFIX)
        : '',
      explanation: pick(NOISE_PREFIX) + '説明' + pick(NOISE_PREFIX),
      japanese_translation: pick(MEANINGS),
      sentence_pronunciation: `${pick(ROMAJI)} ${ROMAJI[correctIdx]}`,
      dummy_reasons: reasons,
    };

    sanitizeCases.push({ input, output: sanitizeQuizQuestion(input) });
  }

  // --- buildBlankSentencePronunciation ---
  const blankPronCases: any[] = [];
  for (let i = 0; i < 300; i++) {
    const idx = Math.floor(rand() * ROMAJI.length);
    const sentencePron = pick(NOISE_PREFIX) +
      `${pick(ROMAJI)} ${rand() < 0.8 ? ROMAJI[idx] : 'zzz'} ${pick(ROMAJI)}` +
      pick(NOISE_PREFIX);
    const keyPron = rand() < 0.9 ? ROMAJI[idx] : '';
    blankPronCases.push({
      sentence_pronunciation: sentencePron,
      key_word_pronunciation: keyPron,
      output: buildBlankSentencePronunciation(sentencePron, keyPron),
    });
  }

  Math.random = realRandom;

  // --- Gemini リクエスト本文 ---
  // 本物の GeminiQuizService に fetch をスタブして通し、送信内容を記録する。
  const geminiRequests: any[] = [];
  {
    const { GeminiQuizService } = require('../src/services/geminiQuizService');
    let captured: any = null;
    (global as any).fetch = async (_url: string, init: any) => {
      captured = { url: _url, body: JSON.parse(init.body) };
      return {
        ok: true,
        status: 200,
        json: async () => ({
          candidates: [{ content: { parts: [{ text: JSON.stringify({
            dummies: ['ข้าว', 'ไป', 'แมว'],
            explanation: '説明',
            dummy_reasons: ['a', 'b', 'c'],
          }) }] } }],
          usageMetadata: { promptTokenCount: 100, candidatesTokenCount: 50 },
        }),
      };
    };
    for (const l of ['ja', 'en'] as const) {
      for (const c of prepareCases.slice(0, 5)) {
        captured = null;
        const svc = new GeminiQuizService('TEST_KEY', 'uid-1', 'free', l);
        await svc.generateQuizQuestions(c.sentences);
        geminiRequests.push({ lang: l, sentences: c.sentences, request: captured });
      }
    }
  }

  const out = path.join(process.cwd(), 'scripts', 'quiz_golden.json');
  fs.writeFileSync(out, JSON.stringify({
    prompts,
    prepare_cases: prepareCases,
    sanitize_cases: sanitizeCases,
    blank_pronunciation_cases: blankPronCases,
    gemini_requests: geminiRequests,
  }, null, 1));
  console.error(
    `wrote prepare=${prepareCases.length} sanitize=${sanitizeCases.length} ` +
    `blankPron=${blankPronCases.length} -> ${out}`
  );
  console.error(`  sanitize: 通過 ${sanitizeCases.filter((c) => c.output).length} / ` +
    `破棄 ${sanitizeCases.filter((c) => !c.output).length}`);
}

main();
