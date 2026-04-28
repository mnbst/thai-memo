/**
 * generateQuiz.ts — Gemini によるタイ語穴埋めクイズ生成
 *
 * 「まいにちタイ語」アプリのクイズ機能のバックエンド。
 * クライアントから onCall で呼び出され、ユーザーの学習済み例文から
 * SRS（間隔反復）アルゴリズムでリアルタイムに復習対象を選出し、
 * Gemini で穴埋め形式のクイズ問題を生成して返却する。
 *
 * 【処理フロー】
 * 1. Firebase Auth 認証チェック
 * 2. クイズ生成クォータチェック（free=1回/日、premium=5回/日、JST 0:00リセット。）
 * 3. ユーザーの例文からSRSベースでリアルタイムに復習対象を選出（最大5文）
 * 4. 5問分の生成元を先に揃え、Gemini で穴埋め問題を生成
 * 5. 生成失敗分のみ Gemini でリトライ
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
import * as logger from 'firebase-functions/logger';
import * as admin from 'firebase-admin';
import { GeminiQuizService } from './services/geminiQuizService';
import { getGeminiApiKey } from './services/secretManager';
import {
  buildBlankSentencePronunciation,
  isQuizSentenceSeedReady,
  QuizGenerationService,
  QuizQuestion,
  QuizQuestionsResponse,
} from './services/quizGenerationService';
import { nowJST } from './utils/formatDate';


/** Firestore インスタンス */
const db = admin.firestore();

/** 1回のクイズ生成で出題する最大問題数 */
const MAX_QUESTIONS = 5;
/** JST オフセット（ms） */
const JST_OFFSET_MS = 9 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
/**
 * SRS（Spaced Repetition System / 間隔反復）の復習間隔（日数）
 *
 * 学習した例文を「1日後 → 3日後 → 7日後 → 14日後 → 30日後」に再出題することで
 * 忘却曲線に沿った効率的な定着を狙う。
 */
const SRS_DAYS = [1, 3, 7, 14, 30];
/** SRSから選ぶ最大例文数 */
const MAX_SRS_SENTENCES = 2;
/** 補充用に一度に確認するUVM語数 */
const UVM_FILLER_PAGE_SIZE = 50;
/** Firestore の in query に渡すキーワード数 */
const KEYWORD_IN_QUERY_LIMIT = 10;

async function consumeQuizQuota(
  userRef: FirebaseFirestore.DocumentReference,
): Promise<void> {
  await db.runTransaction(async (transaction) => {
    const userSnapshot = await transaction.get(userRef);
    const userData = userSnapshot.data() || {};
    const remainingQuizzes = userData.remaining_quizzes ?? 0;

    if (remainingQuizzes <= 0) {
      throw new functions.https.HttpsError('resource-exhausted', 'この時間帯のクイズ生成上限に達しました');
    }

    transaction.set(
      userRef,
      {
        remaining_quizzes: remainingQuizzes - 1,
        ...(userData.is_first_quiz_generation === true && remainingQuizzes <= 1 ?
          {is_first_quiz_generation: admin.firestore.FieldValue.delete()} :
          {}),
      },
      { merge: true },
    );
  });
}

async function restoreQuizQuota(
  userRef: FirebaseFirestore.DocumentReference,
): Promise<void> {
  await userRef.update({
    remaining_quizzes: admin.firestore.FieldValue.increment(1),
  });
}

async function updateQuizStats(
  userRef: FirebaseFirestore.DocumentReference,
  questionCount: number,
): Promise<void> {
  await userRef.set(
    {
      last_active_at: admin.firestore.FieldValue.serverTimestamp(),
      last_quiz_generated_at: admin.firestore.FieldValue.serverTimestamp(),
      quiz_generated_count: admin.firestore.FieldValue.increment(1),
      quiz_question_generated_count: admin.firestore.FieldValue.increment(questionCount),
    },
    { merge: true },
  );
}

/**
 * generateQuiz - クイズ生成（onCall、オンデマンド）
 *
 * クライアントからの呼び出しで穴埋めクイズを生成して返却する。
 * 1. 認証チェック + クイズ生成クォータチェック（free=1回/日、premium=5回/日、JST 0:00リセット。）
 * 2. ユーザー例文をSRSルールでリアルタイム選出（最大5文）
 * 3. 選出結果と補填候補から最大5問分の生成元を作成
 * 4. Geminiで穴埋め問題を生成
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
      throw new functions.https.HttpsError('resource-exhausted', 'この時間帯のクイズ生成上限に達しました');
    }

    const isPremium = userData.tier === 'premium';
    const isFirstGeneration = userData.is_first_quiz_generation === true;
    const usePremiumModel = isPremium || isFirstGeneration;
    const quizGenerationService = await createQuizGenerationService(usePremiumModel, uid);

    // --- SRSベースでリアルタイムに復習対象例文を選出 ---
    const selectedSentences = await selectSentencesBySRS(uid, nowJST());

    // ユーザー例文がない場合 → クォータ消費せずクライアントに通知
    if (selectedSentences.length === 0) {
      return { questions: [], no_user_sentences: true };
    }

    // クォータをGemini呼び出し前にアトミックに消費（並行リクエストによるAPI浪費を防止）
    await consumeQuizQuota(userRef);

    try {
      const sources = buildQuizSources(selectedSentences);
      const questions = await generateQuestionsFromSources(quizGenerationService, sources);
      if (questions.length === 0) {
        await restoreQuizQuota(userRef);
        throw new functions.https.HttpsError('internal', 'クイズの生成に失敗しました');
      }

      await updateQuizStats(userRef, questions.length);

      return { questions: questions.slice(0, MAX_QUESTIONS) };
    } catch (error) {
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }
      console.error('Failed to generate quiz:', error);
      await restoreQuizQuota(userRef).catch((e) =>
        logger.error('Failed to restore quiz quota', { uid, error: e }),
      );
      throw new functions.https.HttpsError('internal', 'クイズの生成に失敗しました');
    }
  }
);

/**
 * generateLearningQuiz - 学習フロー専用の1問クイズ生成（onCall）
 *
 * クライアントで表示中の例文から、穴埋めクイズを1問だけ生成する。
 * SRS選出や補充は行わず、学習直後の確認問題として使う。
 * 学習フローの一部なので、通常クイズ用の生成クォータは消費しない。
 */
export const generateLearningQuiz = functions.https.onCall(
  {
    region: 'asia-northeast1',
    timeoutSeconds: 90,
    memory: '512MiB',
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new functions.https.HttpsError('unauthenticated', '認証が必要です');
    }

    const payload = request.data?.sentence;
    const source = buildLearningQuizSource(payload);
    if (!source || !isQuizSeedSourceReady(source)) {
      throw new functions.https.HttpsError('invalid-argument', 'クイズに使える例文データがありません');
    }

    const userRef = db.collection('users').doc(uid);
    const userDoc = await userRef.get();
    const userData = userDoc.data() || {};
    const isPremium = userData.tier === 'premium';
    const isFirstGeneration = userData.is_first_quiz_generation === true;
    const usePremiumModel = isPremium || isFirstGeneration;
    const quizGenerationService = await createQuizGenerationService(usePremiumModel, uid);

    try {
      const questions = await generateQuestionsFromSources(quizGenerationService, [source]);
      if (questions.length === 0) {
        throw new functions.https.HttpsError('internal', 'クイズの生成に失敗しました');
      }

      const [question] = questions;

      return { questions: [question] };
    } catch (error) {
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }
      console.error('Failed to generate learning quiz:', error);
      throw new functions.https.HttpsError('internal', 'クイズの生成に失敗しました');
    }
  }
);

async function createQuizGenerationService(isPremium: boolean, uid: string): Promise<QuizGenerationService> {
  const apiKey = await getGeminiApiKey();
  return new GeminiQuizService(apiKey, uid, isPremium ? 'premium' : 'free');
}

function buildQuizSources(
  selectedSentences: SelectedSentence[],
): QuizSeedSource[] {
  return [...selectedSentences]
    .sort(() => Math.random() - 0.5)
    .slice(0, MAX_QUESTIONS)
    .map(toQuizSeedSourceFromSelected);
}

// ==================== 一括生成 + key_word バリデーション ====================

interface QuizSeed {
  thai_text: string;
  pronunciation: string;
  japanese_translation: string;
  key_word?: string;
  key_word_pronunciation?: string;
  key_word_meaning?: string;
}

interface QuizSeedSource {
  seed: QuizSeed;
  sentenceId: string;
  srsInterval: number;
  japaneseTranslation: string;
  sentencePronunciation: string;
  sentenceDetail?: Record<string, unknown>;
}

function buildLearningQuizSource(payload: unknown): QuizSeedSource | null {
  if (!payload || typeof payload !== 'object') return null;
  const data = payload as Record<string, unknown>;
  const sentenceId = normalizeTextValue(data.sentence_id);
  const thaiText = normalizeTextValue(data.thai_text);
  const pronunciation = normalizeTextValue(data.pronunciation);
  const japaneseTranslation = normalizeTextValue(data.japanese_translation);
  const keyWord = normalizeTextValue(data.key_word);
  const keyWordPronunciation = normalizeTextValue(data.key_word_pronunciation);
  const keyWordMeaning = normalizeTextValue(data.key_word_meaning);
  const sentenceDetail = buildSentenceDetail(data, sentenceId, {
    thaiText,
    pronunciation,
    japaneseTranslation,
  });

  if (!sentenceId || !thaiText || !keyWord) return null;

  return {
    seed: {
      thai_text: thaiText,
      pronunciation,
      japanese_translation: japaneseTranslation,
      key_word: keyWord,
      key_word_pronunciation: keyWordPronunciation,
      key_word_meaning: keyWordMeaning,
    },
    sentenceId,
    srsInterval: 0,
    japaneseTranslation,
    sentencePronunciation: pronunciation,
    sentenceDetail,
  };
}

function normalizeTextValue(value: unknown): string {
  return typeof value === 'string' ? value.trim().replace(/\s+/g, ' ') : '';
}

function toQuizSeedSourceFromSelected(sentence: SelectedSentence): QuizSeedSource {
  return {
    seed: {
      thai_text: sentence.data.thai_text,
      pronunciation: sentence.data.pronunciation,
      japanese_translation: sentence.data.japanese_translation,
      key_word: sentence.data.key_word,
      key_word_pronunciation: sentence.data.key_word_pronunciation,
      key_word_meaning: resolveKeyWordMeaning(sentence.data),
    },
    sentenceId: sentence.id,
    srsInterval: sentence.srsInterval,
    japaneseTranslation: sentence.data.japanese_translation || '',
    sentencePronunciation: sentence.data.pronunciation || '',
    sentenceDetail: buildSentenceDetail(sentence.data, sentence.id),
  };
}

function buildSentenceDetail(
  data: Record<string, unknown>,
  sentenceId: string,
  fallback?: {
    thaiText: string;
    pronunciation: string;
    japaneseTranslation: string;
  },
): Record<string, unknown> | undefined {
  const wordBreakdown = Array.isArray(data.word_breakdown) ? data.word_breakdown : [];
  const context =
    data.context && typeof data.context === 'object' && !Array.isArray(data.context) ?
      data.context as Record<string, unknown> :
      undefined;

  if (wordBreakdown.length === 0 && !context) return undefined;

  return {
    id: sentenceId,
    thai_text: normalizeTextValue(data.thai_text) || fallback?.thaiText || '',
    pronunciation: normalizeTextValue(data.pronunciation) || fallback?.pronunciation || '',
    japanese_translation:
      normalizeTextValue(data.japanese_translation) || fallback?.japaneseTranslation || '',
    word_breakdown: wordBreakdown,
    ...(context ? { context } : {}),
    ...(typeof data.generation_tier === 'string' ? { generation_tier: data.generation_tier } : {}),
    ...(typeof data.key_word === 'string' ? { target_words: [data.key_word] } : {}),
  };
}

function toQuizQuestion(
  question: QuizQuestionsResponse['questions'][number],
  source: QuizSeedSource,
): QuizQuestion {
  const clientQuestion = { ...question };
  delete clientQuestion.source_index;

  return {
    ...clientQuestion,
    choice_pronunciations: clientQuestion.choice_pronunciations ?? [],
    correct_answer_meaning: clientQuestion.correct_answer_meaning ?? '',
    sentence_id: source.sentenceId,
    srs_interval: source.srsInterval,
    japanese_translation: source.japaneseTranslation,
    sentence_pronunciation: source.sentencePronunciation,
    blank_sentence_pronunciation: buildBlankSentencePronunciation(
      source.sentencePronunciation,
      source.seed.key_word_pronunciation,
    ),
    ...(source.sentenceDetail ? { sentence_detail: source.sentenceDetail } : {}),
  };
}

function isQuizSeedSourceReady(source: QuizSeedSource): boolean {
  const ready = isQuizSentenceSeedReady(source.seed);
  if (!ready) {
    logger.warn('Skipping quiz seed due to unresolved key_word', {
      event: 'quiz_seed_skipped_unresolved_key_word',
      sentenceId: source.sentenceId,
      keyWord: source.seed.key_word ?? null,
    });
  }
  return ready;
}

async function generateQuestionsFromSources(
  quizGenerationService: QuizGenerationService,
  sources: QuizSeedSource[],
): Promise<QuizQuestion[]> {
  const readySources = sources.filter(isQuizSeedSourceReady);
  if (readySources.length === 0) return [];

  const firstResults = await Promise.all(
    readySources.map((source) => generateSingleQuizQuestion(quizGenerationService, source, 0)),
  );

  const questions: Array<QuizQuestion | null> = [...firstResults];

  const retryIndices = questions
    .map((q, i) => q ? null : i)
    .filter((i): i is number => i !== null);

  if (retryIndices.length > 0) {
    logger.warn('Quiz generation retrying failed sources', {
      event: 'quiz_generation_retrying_failed_sources',
      requested: readySources.length,
      failed: retryIndices.length,
    });

    const retryResults = await Promise.all(
      retryIndices.map((i) => generateSingleQuizQuestion(quizGenerationService, readySources[i], 1)),
    );
    retryIndices.forEach((originalIndex, i) => {
      questions[originalIndex] = retryResults[i];
    });
  }

  const skipped = questions.filter((q) => q === null).length;
  if (skipped > 0) {
    logger.error('Quiz generation skipped sources after retry', {
      event: 'quiz_generation_skipped_sources_after_retry',
      requested: readySources.length,
      skipped,
    });
  }

  return questions.filter((q): q is QuizQuestion => q !== null);
}

async function generateSingleQuizQuestion(
  quizGenerationService: QuizGenerationService,
  source: QuizSeedSource,
  attempt: number,
): Promise<QuizQuestion | null> {
  const result = await quizGenerationService.generateQuizQuestions([source.seed]);
  if (result.questions.length === 0) return null;

  const question = result.questions[0];
  if (!matchesKeyWord(question, source.seed)) {
    const details = {
      expected: source.seed.key_word,
      got: question.correct_answer,
      attempt,
    };
    if (attempt === 0) {
      logger.warn('key_word mismatch, will retry', {
        event: 'quiz_key_word_mismatch_retrying',
        ...details,
      });
    } else {
      logger.error('key_word mismatch after retry, skipping', {
        event: 'quiz_key_word_mismatch_after_retry',
        ...details,
      });
    }
    return null;
  }

  return toQuizQuestion(question, source);
}

function matchesKeyWord(
  question: QuizQuestionsResponse['questions'][number],
  seed: QuizSeed,
): boolean {
  return !seed.key_word || question.correct_answer.trim() === seed.key_word.trim();
}

// ==================== SRS 例文選出 ====================

interface SelectedSentence {
  id: string;
  data: FirebaseFirestore.DocumentData;
  /**
   * この例文がどのSRS間隔で選ばれたかを示す値
   * -1: SRS対象外（ランダム補充）
   *  1/3/7/14/30: 該当するSRS間隔（日数）
   */
  srsInterval: number;
}

interface SrsIntervalCandidates {
  interval: number;
  candidates: FirebaseFirestore.QueryDocumentSnapshot[];
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

function isUserSentenceDocReady(
  doc: FirebaseFirestore.QueryDocumentSnapshot,
): boolean {
  const data = doc.data();
  return isQuizSentenceSeedReady({
    thai_text: data.thai_text,
    pronunciation: data.pronunciation,
    japanese_translation: data.japanese_translation,
    key_word: data.key_word,
    key_word_pronunciation: data.key_word_pronunciation,
    key_word_meaning: resolveKeyWordMeaning(data),
  });
}

function resolveKeyWordMeaning(data: Record<string, unknown>): string {
  const keyWord = normalizeTextValue(data.key_word);
  const storedMeaning = normalizeTextValue(data.key_word_meaning);
  if (storedMeaning) return storedMeaning;

  const wordBreakdown = Array.isArray(data.word_breakdown) ? data.word_breakdown : [];
  const match = wordBreakdown.find((item) => {
    if (!item || typeof item !== 'object') return false;
    return normalizeTextValue((item as Record<string, unknown>).word) === keyWord;
  });
  if (!match || typeof match !== 'object') return '';
  return normalizeTextValue((match as Record<string, unknown>).meaning);
}

function shuffleArray<T>(values: T[]): T[] {
  const arr = [...values];
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

/**
 * ユーザーの全例文からSRSアルゴリズムに基づいて復習対象を選出する。
 *
 * 選出の優先順位:
 *  ① SRS_DAYSをランダム順に見て、ジャスト日付ごとにP値最低の1文を最大3文選出
 *  ② ①で埋まらなかった枠を、UVMのP値が低いキーワード順に1語1文で補充
 */
async function selectSentencesBySRS(
  uid: string,
  jstNow: Date,
): Promise<SelectedSentence[]> {
  const selected: SelectedSentence[] = [];
  const usedIds = new Set<string>();
  const usedKeyWords = new Set<string>();

  const remainingSlots = () => MAX_QUESTIONS - selected.length;

  const addCandidate = (candidate: SelectedSentence): void => {
    selected.push(candidate);
    usedIds.add(candidate.id);
    const keyWord = candidate.data.key_word;
    if (typeof keyWord === 'string' && keyWord) {
      usedKeyWords.add(keyWord);
    }
  };

  const srsSentences = await selectSrsSentences(uid, jstNow);
  for (const candidate of srsSentences) addCandidate(candidate);

  if (remainingSlots() > 0) {
    const fillers = await selectFillerSentencesByUvm(uid, remainingSlots(), usedIds, usedKeyWords);
    for (const candidate of fillers) addCandidate(candidate);
  }

  return selected;
}

async function selectSrsSentences(
  uid: string,
  jstNow: Date,
): Promise<SelectedSentence[]> {
  const intervals = shuffleArray(SRS_DAYS);
  const intervalCandidates = await Promise.all(
    intervals.map((interval) => fetchSrsCandidatesForInterval(uid, jstNow, interval)),
  );
  const pMap = await fetchUvmPValues(
    uid,
    collectKeyWords(intervalCandidates.flatMap(({ candidates }) => candidates)),
  );

  const selected: SelectedSentence[] = [];
  const usedIds = new Set<string>();

  for (const { interval, candidates } of intervalCandidates) {
    if (selected.length >= MAX_SRS_SENTENCES) break;

    const [candidate] = candidates
      .filter((doc) => !usedIds.has(doc.id))
      .sort((a, b) => {
        const pA = pMap.get(a.data().key_word) ?? 1;
        const pB = pMap.get(b.data().key_word) ?? 1;
        return pA - pB;
      });
    if (!candidate) continue;

    selected.push(toSelectedUserSentence(candidate, interval));
    usedIds.add(candidate.id);
  }

  return selected;
}

async function fetchSrsCandidatesForInterval(
  uid: string,
  jstNow: Date,
  interval: number,
): Promise<SrsIntervalCandidates> {
  const targetStart = startOfJstDayDaysAgo(jstNow, interval);
  const targetEnd = new Date(targetStart.getTime() + DAY_MS);

  const snapshot = await db
    .collection('users').doc(uid)
    .collection('sentences')
    .where('created_at', '>=', admin.firestore.Timestamp.fromDate(targetStart))
    .where('created_at', '<', admin.firestore.Timestamp.fromDate(targetEnd))
    .get();

  return {
    interval,
    candidates: snapshot.docs.filter(isUserSentenceDocReady),
  };
}

async function selectFillerSentencesByUvm(
  uid: string,
  needed: number,
  usedIds: Set<string>,
  usedKeyWords: Set<string>,
): Promise<SelectedSentence[]> {
  const selected: SelectedSentence[] = [];
  if (needed <= 0) return selected;

  const uvmSnapshot = await db
    .collection('users').doc(uid)
    .collection('uvm')
    .orderBy('p', 'asc')
    .limit(UVM_FILLER_PAGE_SIZE)
    .get();

  for (let i = 0; i < uvmSnapshot.docs.length && selected.length < needed; i += KEYWORD_IN_QUERY_LIMIT) {
    const keyWords = uvmSnapshot.docs
      .slice(i, i + KEYWORD_IN_QUERY_LIMIT)
      .map((doc) => doc.id)
      .filter((keyWord) => !usedKeyWords.has(keyWord));
    if (keyWords.length === 0) continue;

    const sentenceCandidatesByKeyWord = await fetchSentenceCandidatesByKeyWords(uid, keyWords, usedIds);

    for (const keyWord of keyWords) {
      if (selected.length >= needed) break;
      if (usedKeyWords.has(keyWord)) continue;

      const candidates = sentenceCandidatesByKeyWord.get(keyWord) ?? [];
      const sentence = shuffleArray(candidates)[0];
      if (!sentence) continue;

      selected.push(toSelectedUserSentence(sentence, -1));
      usedIds.add(sentence.id);
      usedKeyWords.add(keyWord);
    }
  }

  return selected;
}

async function fetchSentenceCandidatesByKeyWords(
  uid: string,
  keyWords: string[],
  usedIds: Set<string>,
): Promise<Map<string, FirebaseFirestore.QueryDocumentSnapshot[]>> {
  const candidatesByKeyWord = new Map<string, FirebaseFirestore.QueryDocumentSnapshot[]>();
  if (keyWords.length === 0) return candidatesByKeyWord;

  const snapshot = await db
    .collection('users').doc(uid)
    .collection('sentences')
    .where('key_word', 'in', keyWords)
    .get();

  for (const doc of snapshot.docs) {
    const keyWord = doc.data().key_word;
    if (typeof keyWord !== 'string') continue;
    if (usedIds.has(doc.id)) continue;
    if (!isUserSentenceDocReady(doc)) continue;

    const current = candidatesByKeyWord.get(keyWord) ?? [];
    current.push(doc);
    candidatesByKeyWord.set(keyWord, current);
  }

  return candidatesByKeyWord;
}

function startOfJstDayDaysAgo(jstNow: Date, daysAgo: number): Date {
  const shiftedStartMs = Date.UTC(
    jstNow.getUTCFullYear(),
    jstNow.getUTCMonth(),
    jstNow.getUTCDate() - daysAgo,
  );
  return new Date(shiftedStartMs - JST_OFFSET_MS);
}

function collectKeyWords(
  docs: FirebaseFirestore.QueryDocumentSnapshot[],
): Set<string> {
  const keyWords = new Set<string>();
  for (const doc of docs) {
    const keyWord = doc.data().key_word;
    if (typeof keyWord === 'string' && keyWord) keyWords.add(keyWord);
  }
  return keyWords;
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
