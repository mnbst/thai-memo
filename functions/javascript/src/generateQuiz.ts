/**
 * generateQuiz.ts — Gemini AI によるタイ語穴埋めクイズ生成
 *
 * 「まいにちタイ語」アプリのクイズ機能のバックエンド。
 * クライアントから onCall で呼び出され、ユーザーの学習済み例文から
 * SRS（間隔反復）アルゴリズムでリアルタイムに復習対象を選出し、
 * Google Gemini AI で穴埋め形式のクイズ問題を生成して返却する。
 *
 * 【処理フロー】
 * 1. Firebase Auth 認証チェック
 * 2. 日次クイズ生成クォータチェック（free: 1回/日, premium: 10回/日、JST基準）
 * 3. ユーザーの例文からSRSベースでリアルタイムに復習対象を選出（最大5文）
 * 4. ランダムに5問を抽出し、Gemini API で穴埋め問題を生成
 * 5. 5問未満ならデフォルト例文（DEFAULT_SENTENCES）から Gemini 生成して補填
 * 6. ユーザー例文がない場合はデフォルト例文のみで5問生成
 *
 * 【穴埋めクイズの形式】
 * - タイ語の例文から1単語を空欄（___）に置き換え
 * - 正解1つ + ダミー3つの4択問題
 * - 各問題に発音・日本語の解説が付く
 *
 * リージョン: asia-northeast1（東京）
 * タイムアウト: 90秒 / メモリ: 512MiB
 */
import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { GeminiService, QuizQuestion, QuizQuestionsResponse } from './services/geminiService';
import { getGeminiApiKey } from './services/secretManager';
import { DEFAULT_SENTENCES, DefaultSentence } from './constants/defaultQuizQuestions';
import { GEMINI_MODEL_FREE, GEMINI_MODEL_PREMIUM } from './config/constants';
import { nowJST } from './utils/formatDate';


/** Firestore インスタンス */
const db = admin.firestore();

/** 1回のクイズ生成で出題する最大問題数 */
const MAX_QUESTIONS = 5;
/** UVM 未登録語に使う既定の P 値。Python 側の UNKNOWN_WORD_P と揃える。 */
const UNKNOWN_WORD_P = 0.3;

/** estimated_vocab 基準の帯域フィルタ幅（Python 側の FREQ_BAND_HALF と同値） */
const FREQ_BAND_HALF = 10;

/**
 * SRS（Spaced Repetition System / 間隔反復）の復習間隔（日数）
 *
 * 学習した例文を「1日後 → 3日後 → 7日後 → 14日後 → 30日後」に再出題することで
 * 忘却曲線に沿った効率的な定着を狙う。
 */
const SRS_DAYS = [1, 3, 7, 14, 30];
/** SRS 選出で確保する最大例文数 */
const MAX_REVIEW_SENTENCES = 5;

async function consumeQuizQuota(userRef: FirebaseFirestore.DocumentReference): Promise<void> {
  await db.runTransaction(async (transaction) => {
    const userSnapshot = await transaction.get(userRef);
    const userData = userSnapshot.data() || {};
    const remainingQuizzes = userData.remaining_quizzes ?? 0;

    if (remainingQuizzes <= 0) {
      throw new functions.https.HttpsError('resource-exhausted', '本日のクイズ生成上限に達しました');
    }

    transaction.set(userRef, { remaining_quizzes: remainingQuizzes - 1 }, { merge: true });
  });
}

/**
 * generateQuiz - クイズ生成（onCall、オンデマンド）
 *
 * クライアントからの呼び出しで穴埋めクイズを生成して返却する。
 * 1. 認証チェック + 日次クイズ生成クォータチェック（free: 1回/日, premium: 10回/日、JST基準）
 * 2. ユーザー例文をSRSルールでリアルタイム選出（最大5文）
 * 3. 選出結果からランダムに5問を抽出し、Gemini APIで穴埋め問題を生成
 * 4. 5問未満ならデフォルト例文からGemini生成して補填
 * 5. ユーザー例文がない場合はデフォルト例文のみで5問生成
 *
 * リージョン: asia-northeast1 / タイムアウト: 90秒 / メモリ: 512MiB
 */
export const generateQuiz = functions.https.onCall(
  {
    region: 'asia-northeast1',
    timeoutSeconds: 90,
    memory: '512MiB',
  },
  async (request) => {
    // Firebase Auth 認証チェック（匿名認証を含む）
    const uid = request.auth?.uid;
    if (!uid) {
      throw new functions.https.HttpsError('unauthenticated', '認証が必要です');
    }

    // --- クイズ生成クォータチェック ---
    const userRef = db.collection('users').doc(uid);
    const userDoc = await userRef.get();
    const userData = userDoc.data() || {};

    const remainingQuizzes: number = userData.remaining_quizzes ?? 0;

    // 上限に達している場合はエラーを返す
    if (remainingQuizzes <= 0) {
      throw new functions.https.HttpsError('resource-exhausted', '本日のクイズ生成上限に達しました');
    }

    // GCP Secret Manager から Gemini API キーを取得
    const apiKey = await getGeminiApiKey();
    const isPremium = userData.tier === 'premium';
    const geminiModel = isPremium ? GEMINI_MODEL_PREMIUM : GEMINI_MODEL_FREE;
    const geminiService = new GeminiService(apiKey, geminiModel);
    const estimatedVocab: number = userData.estimated_vocab ?? 0;

    // --- SRSベースでリアルタイムに復習対象例文を選出 ---
    const selectedSentences = await selectSentencesBySRS(uid, nowJST(), estimatedVocab);

    // ユーザー例文がない場合（初回登録直後など）→ デフォルト例文からクイズ生成
    if (selectedSentences.length === 0) {
      const result = await generateFromDefaults(geminiService, uid, estimatedVocab);
      await consumeQuizQuota(userRef);
      return result;
    }

    // 選出された例文からランダム5問を抽出
    const shuffled = [...selectedSentences].sort(() => Math.random() - 0.5);
    const picked = shuffled.slice(0, MAX_QUESTIONS);

    try {
      // 各例文を1問ずつ並列で Gemini API に投げてクイズ生成（key_word 不一致時はエラー）
      const results = await Promise.all(
        picked.map(async (s) => {
          const q = await generateSingleQuiz(geminiService, {
            thai_text: s.data.thai_text,
            pronunciation: s.data.pronunciation,
            japanese_translation: s.data.japanese_translation,
            word_breakdown: s.data.word_breakdown || [],
            key_word: s.data.key_word,
          });
          if (!q) return null;
          return {
            ...q,
            sentence_id: s.id,
            srs_interval: s.srsInterval,
            japanese_translation: s.data.japanese_translation || '',
            sentence_pronunciation: s.data.pronunciation || '',
          } as QuizQuestion;
        })
      );
      let questions = results.filter((q): q is QuizQuestion => q !== null);

      // 5問未満ならデフォルト例文からGemini生成して補填
      if (questions.length < MAX_QUESTIONS) {
        questions = await fillWithDefaults(geminiService, questions, uid, estimatedVocab);
      }

      // クイズ生成残回数をアトミックにデクリメント
      await consumeQuizQuota(userRef);

      return { questions: questions.slice(0, MAX_QUESTIONS) };
    } catch (error) {
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }
      console.error('Failed to generate quiz:', error);
      throw new functions.https.HttpsError('internal', 'クイズの生成に失敗しました');
    }
  }
);

/**
 * generateFromDefaults - デフォルト例文から effective P の低い順に5問を Gemini で生成
 *
 * ユーザー例文がない場合（初回登録直後など）のフォールバック処理。
 *
 * @param geminiService - Gemini API を呼び出すサービスインスタンス
 * @param uid - ユーザーID（UVM P値取得用）
 * @returns クイズ問題の配列を含むオブジェクト
 */
async function generateFromDefaults(geminiService: GeminiService, uid: string, estimatedVocab: number): Promise<{ questions: QuizQuestion[] }> {
  // デフォルト例文から「帯域内 → effective P 昇順 → estimated_vocab 近傍」順に5問選出
  const sorted = await sortDefaultsByPriority(uid, DEFAULT_SENTENCES, undefined, estimatedVocab);
  const selected = shuffleTopCandidates(sorted, MAX_QUESTIONS);

  try {
    return {
      questions: await generateQuestionsFromSources(
        geminiService,
        selected.map((sentence) => ({
          seed: {
            thai_text: sentence.thai_text,
            pronunciation: sentence.pronunciation,
            japanese_translation: sentence.japanese_translation,
            word_breakdown: [],
            key_word: sentence.key_word,
          },
          sentenceId: sentence.sentence_id,
          srsInterval: 0,
          japaneseTranslation: sentence.japanese_translation,
          sentencePronunciation: sentence.pronunciation,
        }))
      ),
    };
  } catch (error) {
    console.error('Failed to generate default quiz:', error);
    throw new functions.https.HttpsError('internal', 'クイズの生成に失敗しました');
  }
}

/**
 * fillWithDefaults - 5問未満の場合にデフォルト例文から Gemini 生成して補填
 *
 * SRS選出した例文からの生成で5問に満たなかった場合、
 * 既出の sentence_id を除外したうえでデフォルト例文から effective P の低い順に選出し、
 * Gemini API で追加のクイズ問題を生成する。
 *
 * Gemini 生成が失敗した場合は既存の問題のみで返却する（部分的成功を許容）。
 *
 * @param geminiService - Gemini API を呼び出すサービスインスタンス
 * @param existing - 既に生成済みのクイズ問題の配列
 * @returns 補填後のクイズ問題の配列
 */
async function fillWithDefaults(
  geminiService: GeminiService,
  existing: QuizQuestion[],
  uid: string,
  estimatedVocab: number,
): Promise<QuizQuestion[]> {
  const needed = MAX_QUESTIONS - existing.length;
  if (needed <= 0) return existing;

  // 既出の sentence_id を除外してデフォルト例文から「帯域内 → effective P 昇順 → estimated_vocab 近傍」順に候補を選出
  const usedIds = new Set(existing.map(q => q.sentence_id));
  const available = DEFAULT_SENTENCES.filter(s => !usedIds.has(s.sentence_id));
  const sorted = await sortDefaultsByPriority(uid, available, undefined, estimatedVocab);
  const candidates = shuffleTopCandidates(sorted, needed);

  if (candidates.length === 0) return existing;

  try {
    const fillerQuestions = await generateQuestionsFromSources(
      geminiService,
      candidates.map((sentence) => ({
        seed: {
          thai_text: sentence.thai_text,
          pronunciation: sentence.pronunciation,
          japanese_translation: sentence.japanese_translation,
          word_breakdown: [],
          key_word: sentence.key_word,
        },
        sentenceId: sentence.sentence_id,
        srsInterval: 0,
        japaneseTranslation: sentence.japanese_translation,
        sentencePronunciation: sentence.pronunciation,
      }))
    );

    return [...existing, ...fillerQuestions];
  } catch (error) {
    // 補填用の生成が失敗しても、既存の問題だけで返す（部分的成功を許容）
    console.error('Failed to generate filler quiz:', error);
    return existing;
  }
}

// ==================== 単問生成 + key_word バリデーション ====================

interface QuizSeed {
  thai_text: string;
  pronunciation: string;
  japanese_translation: string;
  word_breakdown: { word: string; pronunciation: string; meaning: string }[];
  key_word?: string;
}

interface QuizSeedSource {
  seed: QuizSeed;
  sentenceId: string;
  srsInterval: number;
  japaneseTranslation: string;
  sentencePronunciation: string;
}

interface SentenceWithDays {
  doc: FirebaseFirestore.QueryDocumentSnapshot;
  diffDays: number;
}

function shuffleTopCandidates<T>(candidates: T[], count: number): T[] {
  return [...candidates.slice(0, count)].sort(() => Math.random() - 0.5);
}

function toQuizQuestion(
  question: QuizQuestionsResponse['questions'][number],
  source: QuizSeedSource,
): QuizQuestion {
  return {
    ...question,
    sentence_id: source.sentenceId,
    srs_interval: source.srsInterval,
    japanese_translation: source.japaneseTranslation,
    sentence_pronunciation: source.sentencePronunciation,
  };
}

async function generateQuestionsFromSources(
  geminiService: GeminiService,
  sources: QuizSeedSource[],
): Promise<QuizQuestion[]> {
  const results = await Promise.all(
    sources.map(async (source) => {
      const question = await generateSingleQuiz(geminiService, source.seed);
      return question ? toQuizQuestion(question, source) : null;
    })
  );

  return results.filter((question): question is QuizQuestion => question !== null);
}

/**
 * 1つの例文に対して Gemini でクイズ1問を生成し、key_word 一致を検証する。
 *
 * - 生成失敗やサニタイズで除外された場合は null を返す
 * - key_word 不一致時は1回リトライし、それでも不一致ならエラーを throw
 */
async function generateSingleQuiz(
  geminiService: GeminiService,
  seed: QuizSeed,
): Promise<QuizQuestionsResponse['questions'][number] | null> {
  for (let attempt = 0; attempt < 2; attempt++) {
    const result = await geminiService.generateQuizQuestions([seed]);
    const q = result.questions[0];
    if (!q) return null;

    if (!seed.key_word || q.correct_answer.trim() === seed.key_word.trim()) {
      return q;
    }

    // 1回目の不一致はリトライ
    if (attempt === 0) {
      console.warn('key_word mismatch, retrying', {
        expected: seed.key_word,
        got: q.correct_answer,
      });
      continue;
    }

    // 2回目も不一致 → この問題はスキップ（他の問題に影響させない）
    console.error('key_word mismatch after retry, skipping', {
      expected: seed.key_word,
      got: q.correct_answer,
    });
    return null;
  }

  return null;
}

// ==================== SRS 例文選出 ====================

interface SelectedSentence {
  id: string;
  data: FirebaseFirestore.DocumentData;
  /**
   * この例文がどのSRS間隔で選ばれたかを示す値
   * -1: SRS対象外（ランダム補充）
   *  0: デフォルト例文（ユーザー例文が不足する新規ユーザー向け）
   *  1/3/7/14/30: 該当するSRS間隔（日数）
   */
  srsInterval: number;
}

function buildSortByP(
  pMap: Map<string, number>,
): (a: SentenceWithDays, b: SentenceWithDays) => number {
  return (a, b) => {
    const pA = pMap.get(a.doc.data().key_word) ?? 1;
    const pB = pMap.get(b.doc.data().key_word) ?? 1;
    return pA - pB;
  };
}

function toSelectedUserSentence(
  doc: FirebaseFirestore.QueryDocumentSnapshot,
  srsInterval: number,
): SelectedSentence {
  return {
    id: doc.id,
    data: doc.data(),
    srsInterval,
  };
}

function toSelectedDefaultSentence(sentence: DefaultSentence): SelectedSentence {
  return {
    id: sentence.sentence_id,
    data: {
      thai_text: sentence.thai_text,
      pronunciation: sentence.pronunciation,
      japanese_translation: sentence.japanese_translation,
      word_breakdown: [],
      key_word: sentence.key_word,
    },
    srsInterval: 0,
  };
}

function collectCandidatesByIntervals(
  docsWithDays: SentenceWithDays[],
  intervals: number[],
  matcher: (diffDays: number, interval: number) => boolean,
  sortByP: (a: SentenceWithDays, b: SentenceWithDays) => number,
  usedIds: Set<string>,
  seenIds?: Set<string>,
): SelectedSentence[] {
  return intervals.flatMap((interval) =>
    docsWithDays
      .filter(({ doc, diffDays }) =>
        !usedIds.has(doc.id) &&
        !(seenIds?.has(doc.id) ?? false) &&
        matcher(diffDays, interval)
      )
      .sort(sortByP)
      .map(({ doc }) => {
        seenIds?.add(doc.id);
        return toSelectedUserSentence(doc, interval);
      })
  );
}

/**
 * ユーザーの全例文からSRSアルゴリズムに基づいて復習対象を選出する。
 *
 * 選出の優先順位:
 *  ① SRS間隔にジャスト該当する例文
 *  ② ①で不足する場合、±1日の範囲から補填
 *  ③ ①+②で不足する場合、SRS対象外の例文から補充
 *  ④ それでも不足する場合、デフォルト例文で補充
 */
async function selectSentencesBySRS(
  uid: string,
  jstNow: Date,
  estimatedVocab: number = 0,
): Promise<SelectedSentence[]> {
  const selected: SelectedSentence[] = [];
  const usedIds = new Set<string>();

  const allSentencesSnapshot = await db
    .collection('users').doc(uid)
    .collection('sentences')
    .orderBy('created_at', 'desc')
    .get();

  if (allSentencesSnapshot.empty) return [];

  // UVM P値を取得（key_wordが苦手な文を優先するため）
  const userKeyWords = new Set<string>();
  for (const doc of allSentencesSnapshot.docs) {
    const kw = doc.data().key_word;
    if (kw && typeof kw === 'string') userKeyWords.add(kw);
  }
  // デフォルト例文の key_word も含めて一括取得（④で再利用）
  for (const s of DEFAULT_SENTENCES) userKeyWords.add(s.key_word);
  const pMap = await fetchUvmPValues(uid, userKeyWords);

  // 各例文の作成日からの経過日数を事前計算（SRS間隔との照合に使用）
  const jstNowMs = jstNow.getTime();
  const docsWithDays = allSentencesSnapshot.docs.map(doc => {
    const createdAt = doc.data().created_at?.toDate();
    let diffDays = -1;
    if (createdAt) {
      const jstCreated = new Date(createdAt.toLocaleString('en-US', { timeZone: 'Asia/Tokyo' }));
      diffDays = Math.floor((jstNowMs - jstCreated.getTime()) / (24 * 60 * 60 * 1000));
    }
    return { doc, diffDays };
  });

  const sortByP = buildSortByP(pMap);

  const remainingSlots = () => MAX_REVIEW_SENTENCES - selected.length;

  const appendTopCandidates = (candidates: SelectedSentence[]): void => {
    const take = Math.min(candidates.length, remainingSlots());
    for (const candidate of candidates.slice(0, take)) {
      selected.push(candidate);
      usedIds.add(candidate.id);
    }
  };

  // ① SRSジャスト該当日から、各間隔の上位候補を必要件数ぶん取得
  const exactCandidates = collectCandidatesByIntervals(
    docsWithDays,
    SRS_DAYS,
    (diffDays, interval) => diffDays === interval,
    sortByP,
    usedIds,
  );
  appendTopCandidates(exactCandidates);

  // ② ±1日の近傍候補から、各間隔の上位候補を必要件数ぶん取得
  if (remainingSlots() > 0) {
    const nearbySeenIds = new Set<string>();
    const nearbyCandidates = collectCandidatesByIntervals(
      docsWithDays,
      SRS_DAYS,
      (diffDays, interval) => diffDays >= interval - 1 && diffDays <= interval + 1,
      sortByP,
      usedIds,
      nearbySeenIds,
    );
    appendTopCandidates(nearbyCandidates);
  }

  // ③ ①+②で不足する場合、残りユーザー例文からP値が低い順に補充
  if (remainingSlots() > 0) {
    const remaining = allSentencesSnapshot.docs
      .filter(doc => !usedIds.has(doc.id))
      .sort((a, b) => {
        const pA = pMap.get(a.data().key_word) ?? 1;
        const pB = pMap.get(b.data().key_word) ?? 1;
        return pA - pB;
      })
      .map((doc) => toSelectedUserSentence(doc, -1));
    appendTopCandidates(remaining);
  }

  // ④ デフォルト例文から不足分を補充
  if (remainingSlots() > 0) {
    const defaults = await sortDefaultsByPriority(uid, DEFAULT_SENTENCES, pMap, estimatedVocab);
    const defaultCandidates = defaults
      .filter((s) => !usedIds.has(s.sentence_id))
      .map((s) => toSelectedDefaultSentence(s));
    appendTopCandidates(defaultCandidates);
  }

  return selected;
}

/**
 * デフォルト例文を estimated_vocab ± 10 帯域内に絞り、effective P の低い順に返す。
 * 帯域外の例文は一切含まない。
 *
 * pMap を渡す場合は Firestore 読み取りをスキップして再利用する。
 */
async function sortDefaultsByPriority(
  uid: string,
  sentences: DefaultSentence[],
  existingPMap?: Map<string, number>,
  estimatedVocab: number = 0,
): Promise<DefaultSentence[]> {
  const bandLow = Math.max(0, estimatedVocab - FREQ_BAND_HALF);
  const bandHigh = estimatedVocab + FREQ_BAND_HALF;

  // 帯域内のみに絞る
  const inBand = sentences.filter(s => s.rank >= bandLow && s.rank <= bandHigh);
  if (inBand.length === 0) return [];

  const pMap = existingPMap ?? await fetchUvmPValues(uid, new Set(inBand.map(s => s.key_word)));

  return [...inBand].sort((a, b) => {
    const pA = pMap.get(a.key_word) ?? UNKNOWN_WORD_P;
    const pB = pMap.get(b.key_word) ?? UNKNOWN_WORD_P;
    if (pA !== pB) return pA - pB;

    const distanceA = Math.abs(a.rank - estimatedVocab);
    const distanceB = Math.abs(b.rank - estimatedVocab);
    if (distanceA !== distanceB) return distanceA - distanceB;

    return Math.random() - 0.5;
  });
}

/**
 * 指定された key_word 群の UVM P値を一括取得する。
 * UVM未登録の単語は pMap に含まれない（呼び出し側でデフォルト値を使用）。
 */
async function fetchUvmPValues(
  uid: string,
  keyWords: Set<string>
): Promise<Map<string, number>> {
  const pMap = new Map<string, number>();
  if (keyWords.size === 0) return pMap;

  const uvmRef = db.collection('users').doc(uid).collection('uvm');
  const refs = [...keyWords].map(w => uvmRef.doc(w));
  const snapshots = await db.getAll(...refs);

  for (const snap of snapshots) {
    if (snap.exists) {
      const p = (snap.data() as { p?: number })?.p;
      if (typeof p === 'number') pMap.set(snap.id, p);
    }
  }

  return pMap;
}
