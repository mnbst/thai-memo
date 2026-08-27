/**
 * genLearningQuizGolden.ts — generateLearningQuiz の組み立てを JS 実装から書き出す。
 *
 * Firestore と Gemini をスタブし、本物の generateQuiz.ts を通して
 * 「入力ペイロード → 返す questions」を記録する。
 * これで buildLearningQuizSource / buildSentenceDetail / toQuizQuestion /
 * matchesKeyWord の再試行までまとめて Go 版と突き合わせられる。
 * 出力先: functions/javascript/scripts/learning_quiz_golden.json
 */
import * as fs from 'fs';
import * as path from 'path';

/* eslint-disable @typescript-eslint/no-explicit-any */

class FakeHttpsError extends Error {
  constructor(readonly code: string, message: string) {
    super(message);
  }
}

let capturedStats: any = null;
let userData: any = {};

const adminStub: any = {
  firestore: Object.assign(
    () => ({
      collection: () => ({
        doc: () => ({
          get: async () => ({ data: () => userData }),
          set: async (payload: any) => { capturedStats = payload; },
        }),
      }),
    }),
    {
      FieldValue: {
        serverTimestamp: () => ({ __sentinel: 'serverTimestamp' }),
        increment: (n: number) => ({ __increment: n }),
      },
      Timestamp: { fromDate: (d: Date) => ({ __timestamp: d.getTime() }) },
    }
  ),
  apps: [],
};

const handlers: Record<string, any> = {};
let onCallSeq = 0;
const functionsStub: any = {
  https: {
    onCall: (_c: unknown, h: any) => {
      handlers[onCallSeq === 0 ? 'generateQuiz' : 'generateLearningQuiz'] = h;
      onCallSeq++;
      return h;
    },
    HttpsError: FakeHttpsError,
  },
};

/** Gemini が返す問題（ケースごとに差し替える） */
let stubbedQuestions: any[][] = [];
let stubCallCount = 0;

const Module = require('module');
const origLoad = Module._load;
Module._load = function (request: string, ...rest: any[]) {
  if (request === 'firebase-admin') return adminStub;
  if (request === 'firebase-functions/v2') return functionsStub;
  if (request === 'firebase-functions/logger') {
    return { warn: () => { }, error: () => { }, info: () => { } };
  }
  if (request.endsWith('geminiQuizService')) {
    return {
      GeminiQuizService: class {
        async generateQuizQuestions() {
          const q = stubbedQuestions[Math.min(stubCallCount, stubbedQuestions.length - 1)];
          stubCallCount++;
          return { questions: q };
        }
      },
    };
  }
  if (request.endsWith('secretManager')) {
    return { getGeminiApiKey: async () => 'TEST_KEY' };
  }
  return origLoad.call(this, request, ...rest);
};

require('../src/generateQuiz');
const generateLearningQuiz = handlers['generateLearningQuiz'];

const AUTH = { auth: { uid: 'uid-1' } };

type Case = {
  name: string;
  sentence: any;
  lang: unknown;
  stubbed_questions: any[][];
  ok: boolean;
  error_code: string | null;
  error_message: string | null;
  result: any;
  stats: any;
};

function encode(value: any): any {
  if (value === null || value === undefined) return value ?? null;
  if (Array.isArray(value)) return value.map(encode);
  if (typeof value === 'object') {
    if (value.__sentinel === 'serverTimestamp') return { $server_timestamp: true };
    if (typeof value.__increment === 'number') return { $increment: value.__increment };
    const o: any = {};
    for (const [k, v] of Object.entries(value)) o[k] = encode(v);
    return o;
  }
  return value;
}

// モデルが返す1問（ルールベース合成・検査を通ったあとの形）
function madeQuestion(over: any = {}) {
  return {
    source_index: 0,
    thai_text: 'ฉันกินข้าว',
    blank_text: 'ฉัน___ข้าว',
    correct_answer: 'กิน',
    correct_answer_meaning: '食べる',
    choices: ['กิน', 'ไป', 'แมว', 'สวย'],
    choice_pronunciations: ['kin', 'pai', 'mɛɛo', 'sǔai'],
    pronunciation: 'kin',
    explanation: '説明',
    japanese_translation: '私はご飯を食べる',
    sentence_pronunciation: 'chǎn kin khâao',
    dummy_reasons: ['ไป（pai / 行く）：理由', 'แมว（mɛɛo / 猫）：理由', 'สวย（sǔai / 美しい）：理由'],
    ...over,
  };
}

const FULL_SENTENCE = {
  sentence_id: 's-1',
  thai_text: '  ฉันกินข้าว  ',
  pronunciation: 'chǎn kin khâao',
  japanese_translation: '私はご飯を食べる',
  key_word: 'กิน',
  key_word_pronunciation: 'kin',
  key_word_meaning: '食べる',
  word_breakdown: [
    { word: 'ฉัน', meaning: '私', pronunciation: 'chǎn' },
    { word: 'กิน', meaning: '食べる', pronunciation: 'kin' },
  ],
  context: { situation: '食事', register: 'casual' },
  generation_tier: 'premium',
};

async function main() {
  const specs: { name: string; sentence: any; lang?: unknown; stubbed: any[][] }[] = [
    {
      name: '完全な例文',
      sentence: FULL_SENTENCE,
      stubbed: [[madeQuestion()]],
    },
    {
      name: 'word_breakdown も context も無い（sentence_detail を付けない）',
      sentence: {
        sentence_id: 's-2', thai_text: 'ฉันกินข้าว',
        pronunciation: 'chǎn kin khâao',
        japanese_translation: '私はご飯を食べる', key_word: 'กิน',
        key_word_pronunciation: 'kin', key_word_meaning: '食べる',
      },
      stubbed: [[madeQuestion()]],
    },
    {
      name: 'key_word_meaning が無く word_breakdown から引く',
      sentence: { ...FULL_SENTENCE, key_word_meaning: '' },
      stubbed: [[madeQuestion()]],
    },
    {
      name: 'context だけある',
      sentence: { ...FULL_SENTENCE, word_breakdown: [] },
      stubbed: [[madeQuestion()]],
    },
    {
      name: 'lang=en',
      sentence: FULL_SENTENCE, lang: 'en',
      stubbed: [[madeQuestion()]],
    },
    {
      name: '発音が例文中に無く blank_sentence_pronunciation が空',
      sentence: { ...FULL_SENTENCE, key_word_pronunciation: 'zzz' },
      stubbed: [[madeQuestion({ correct_answer: 'กิน' })]],
    },
    {
      name: 'key_word 不一致 → 再試行して成功',
      sentence: FULL_SENTENCE,
      stubbed: [[madeQuestion({ correct_answer: 'ไป' })], [madeQuestion()]],
    },
    {
      name: 'key_word 不一致が再試行でも直らない',
      sentence: FULL_SENTENCE,
      stubbed: [[madeQuestion({ correct_answer: 'ไป' })], [madeQuestion({ correct_answer: 'ไป' })]],
    },
    {
      name: 'モデルが空を返す',
      sentence: FULL_SENTENCE,
      stubbed: [[]],
    },
    {
      name: 'sentence_id なし',
      sentence: { ...FULL_SENTENCE, sentence_id: '' },
      stubbed: [[madeQuestion()]],
    },
    {
      name: 'key_word なし',
      sentence: { ...FULL_SENTENCE, key_word: '' },
      stubbed: [[madeQuestion()]],
    },
    {
      name: 'key_word が本文に含まれない',
      sentence: { ...FULL_SENTENCE, key_word: 'ไม่มี' },
      stubbed: [[madeQuestion()]],
    },
    {
      name: 'ペイロードが null',
      sentence: null,
      stubbed: [[madeQuestion()]],
    },
  ];

  const cases: Case[] = [];
  for (const spec of specs) {
    stubbedQuestions = spec.stubbed;
    stubCallCount = 0;
    capturedStats = null;
    userData = { tier: 'free' };

    const c: Case = {
      name: spec.name, sentence: spec.sentence, lang: spec.lang ?? null,
      stubbed_questions: spec.stubbed,
      ok: false, error_code: null, error_message: null, result: null, stats: null,
    };
    try {
      const result = await generateLearningQuiz({
        ...AUTH,
        data: { sentence: spec.sentence, ...(spec.lang ? { lang: spec.lang } : {}) },
      });
      c.ok = true;
      c.result = encode(result);
    } catch (e) {
      c.error_code = (e as FakeHttpsError).code ?? null;
      c.error_message = (e as Error).message;
    }
    c.stats = encode(capturedStats);
    cases.push(c);
  }

  const out = path.join(process.cwd(), 'scripts', 'learning_quiz_golden.json');
  fs.writeFileSync(out, JSON.stringify(cases, null, 1));
  console.error(`wrote ${cases.length} cases -> ${out}`);
  for (const c of cases) {
    console.error(`  ${c.ok ? 'OK ' : `NG(${c.error_code})`} ${c.name}`);
  }
}

main();
