/**
 * generateQuiz.ts — OpenAI によるタイ語穴埋めクイズ生成
 *
 * 「まいにちタイ語」アプリのクイズ機能のバックエンド。
 * クライアントから onCall で呼び出され、ユーザーの学習済み例文から
 * SRS（間隔反復）アルゴリズムでリアルタイムに復習対象を選出し、
 * OpenAI で穴埋め形式のクイズ問題を生成して返却する。
 *
 * 【処理フロー】
 * 1. Firebase Auth 認証チェック
 * 2. クイズ生成クォータチェック（5回/12時間、JST 0:00/12:00リセット）
 * 3. ユーザーの例文からSRSベースでリアルタイムに復習対象を選出（最大5文）
 * 4. 5問分の生成元を先に揃え、OpenAI で穴埋め問題を一括生成
 * 5. 生成失敗分のみ OpenAI で一括リトライ
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
import * as logger from 'firebase-functions/logger';
import * as admin from 'firebase-admin';
import { OpenAiQuizService } from './services/openAiQuizService';
import { getOpenAiApiKey } from './services/secretManager';
import {
  isQuizSentenceSeedReady,
  QuizGenerationService,
  QuizQuestion,
  QuizQuestionsResponse,
} from './services/quizGenerationService';
import {
  DEFAULT_SENTENCES,
  DefaultSentence,
  isDefaultSentenceMatchingDifficulty,
} from './constants/defaultQuizQuestions';
import {
  OPENAI_MODEL_FREE,
  OPENAI_MODEL_PREMIUM,
} from './config/constants';
import { nowJST } from './utils/formatDate';


/** Firestore インスタンス */
const db = admin.firestore();

/** 1回のクイズ生成で出題する最大問題数 */
const MAX_QUESTIONS = 5;
/** JST オフセット（ms） */
const JST_OFFSET_MS = 9 * 60 * 60 * 1000;
/** Firestore から取得するユーザー例文の上限数 */
const MAX_USER_SENTENCES_FETCH = 50;
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
const MAX_REVIEW_SENTENCES = 3;

async function consumeQuizQuota(
  userRef: FirebaseFirestore.DocumentReference,
  questionCount: number,
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
        last_active_at: admin.firestore.FieldValue.serverTimestamp(),
        last_quiz_generated_at: admin.firestore.FieldValue.serverTimestamp(),
        quiz_generated_count: admin.firestore.FieldValue.increment(1),
        quiz_question_generated_count: admin.firestore.FieldValue.increment(questionCount),
      },
      { merge: true },
    );
  });
}

/**
 * generateQuiz - クイズ生成（onCall、オンデマンド）
 *
 * クライアントからの呼び出しで穴埋めクイズを生成して返却する。
 * 1. 認証チェック + クイズ生成クォータチェック（5回/12時間、JST 0:00/12:00リセット）
 * 2. ユーザー例文をSRSルールでリアルタイム選出（最大5文）
 * 3. 選出結果と補填候補から最大5問分の生成元を作成
 * 4. OpenAIで穴埋め問題を一括生成
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
      throw new functions.https.HttpsError('resource-exhausted', 'この時間帯のクイズ生成上限に達しました');
    }

    const isPremium = userData.tier === 'premium';
    const quizGenerationService = await createQuizGenerationService(isPremium, uid);
    const estimatedVocab: number = userData.estimated_vocab ?? 0;

    // --- SRSベースでリアルタイムに復習対象例文を選出 ---
    const selectedSentences = await selectSentencesBySRS(uid, nowJST(), estimatedVocab);

    // ユーザー例文がない場合（初回登録直後など）→ デフォルト例文からクイズ生成
    if (selectedSentences.length === 0) {
      const result = await generateFromDefaults(quizGenerationService, uid, estimatedVocab);
      await consumeQuizQuota(userRef, result.questions.length);
      return result;
    }

    try {
      const sources = await buildQuizSourcesForGeneration(selectedSentences, uid, estimatedVocab);
      const questions = await generateQuestionsFromSources(quizGenerationService, sources);

      // クイズ生成残回数をアトミックにデクリメント
      await consumeQuizQuota(userRef, questions.length);

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

async function createQuizGenerationService(isPremium: boolean, uid: string): Promise<QuizGenerationService> {
  const apiKey = await getOpenAiApiKey();
  const model = isPremium ? OPENAI_MODEL_PREMIUM : OPENAI_MODEL_FREE;
  return new OpenAiQuizService(apiKey, model, uid, isPremium ? 'premium' : 'free');
}

/**
 * generateFromDefaults - デフォルト例文から effective P の低い順に5問を生成
 *
 * ユーザー例文がない場合（初回登録直後など）のフォールバック処理。
 *
 * @param quizGenerationService - クイズ生成AIサービスインスタンス
 * @param uid - ユーザーID（UVM P値取得用）
 * @returns クイズ問題の配列を含むオブジェクト
 */
async function generateFromDefaults(
  quizGenerationService: QuizGenerationService,
  uid: string,
  estimatedVocab: number,
): Promise<{ questions: QuizQuestion[] }> {
  // デフォルト例文から「帯域内 → effective P 昇順 → estimated_vocab 近傍」順に5問選出
  const sorted = await sortDefaultsByPriority(uid, DEFAULT_SENTENCES, undefined, estimatedVocab);
  const selectedSources = shuffleTopCandidates(
    sorted.map(toQuizSeedSourceFromDefault).filter(isQuizSeedSourceReady),
    MAX_QUESTIONS,
  );

  try {
    return {
      questions: await generateQuestionsFromSources(
        quizGenerationService,
        selectedSources,
      ),
    };
  } catch (error) {
    console.error('Failed to generate default quiz:', error);
    throw new functions.https.HttpsError('internal', 'クイズの生成に失敗しました');
  }
}

/**
 * buildQuizSourcesForGeneration - 生成前に最大5問分の元例文を揃える
 *
 * LLM呼び出しを1回にまとめるため、SRS選出分と不足補填分を先に結合する。
 */
async function buildQuizSourcesForGeneration(
  selectedSentences: SelectedSentence[],
  uid: string,
  estimatedVocab: number,
): Promise<QuizSeedSource[]> {
  const selectedSources = [...selectedSentences]
    .sort(() => Math.random() - 0.5)
    .slice(0, MAX_QUESTIONS)
    .map(toQuizSeedSourceFromSelected)
    .filter(isQuizSeedSourceReady);

  const excludedIds = new Set(selectedSentences.map((sentence) => sentence.id));
  return fillQuizSourcesBeforeGeneration(selectedSources, uid, estimatedVocab, excludedIds);
}

async function fillQuizSourcesBeforeGeneration(
  existingSources: QuizSeedSource[],
  uid: string,
  estimatedVocab: number,
  excludedIds: Set<string> = new Set(),
): Promise<QuizSeedSource[]> {
  const needed = MAX_QUESTIONS - existingSources.length;
  if (needed <= 0) return existingSources.slice(0, MAX_QUESTIONS);

  const usedIds = new Set([
    ...excludedIds,
    ...existingSources.map((source) => source.sentenceId),
  ]);
  const available = DEFAULT_SENTENCES.filter((s) => !usedIds.has(s.sentence_id));
  const sorted = await sortDefaultsByPriority(uid, available, undefined, estimatedVocab);
  const candidates = shuffleTopCandidates(
    sorted.map(toQuizSeedSourceFromDefault).filter(isQuizSeedSourceReady),
    needed,
  );

  let sources = [
    ...existingSources,
    ...candidates,
  ];

  if (sources.length < MAX_QUESTIONS) {
    sources = await fillQuizSourcesWithUserSentencesByP(
      sources,
      uid,
      MAX_QUESTIONS - sources.length,
      usedIds,
    );
  }

  return sources.slice(0, MAX_QUESTIONS);
}

/**
 * fillQuizSourcesWithUserSentencesByP - ユーザー例文を UVM P値昇順で補填
 *
 * デフォルト例文の帯域内候補が不足した場合のフォールバック。
 * UVM P値が最も低い（最も苦手な）ユーザー例文を優先して出題する。
 */
async function fillQuizSourcesWithUserSentencesByP(
  existingSources: QuizSeedSource[],
  uid: string,
  needed: number,
  excludedIds: Set<string> = new Set(),
): Promise<QuizSeedSource[]> {
  if (needed <= 0) return existingSources;

  const usedIds = new Set([
    ...excludedIds,
    ...existingSources.map((source) => source.sentenceId),
  ]);

  const snapshot = await db
    .collection('users').doc(uid)
    .collection('sentences')
    .orderBy('created_at', 'desc')
    .limit(MAX_USER_SENTENCES_FETCH)
    .get();

  if (snapshot.empty) return existingSources;

  const keyWords = new Set<string>();
  for (const doc of snapshot.docs) {
    const kw = doc.data().key_word;
    if (kw) keyWords.add(kw);
  }
  const pMap = await fetchUvmPValues(uid, keyWords);

  const candidates = snapshot.docs
    .filter((doc) => !usedIds.has(doc.id))
    .sort((a, b) => {
      const pA = pMap.get(a.data().key_word) ?? UNKNOWN_WORD_P;
      const pB = pMap.get(b.data().key_word) ?? UNKNOWN_WORD_P;
      return pA - pB;
    })
    .map(toQuizSeedSourceFromUserDoc)
    .filter(isQuizSeedSourceReady)
    .slice(0, needed);

  if (candidates.length === 0) return existingSources;

  return [
    ...existingSources,
    ...candidates,
  ];
}

// ==================== 一括生成 + key_word バリデーション ====================

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

function toQuizSeedSourceFromSelected(sentence: SelectedSentence): QuizSeedSource {
  return {
    seed: {
      thai_text: sentence.data.thai_text,
      pronunciation: sentence.data.pronunciation,
      japanese_translation: sentence.data.japanese_translation,
      word_breakdown: sentence.data.word_breakdown || [],
      key_word: sentence.data.key_word,
    },
    sentenceId: sentence.id,
    srsInterval: sentence.srsInterval,
    japaneseTranslation: sentence.data.japanese_translation || '',
    sentencePronunciation: sentence.data.pronunciation || '',
  };
}

function toQuizSeedSourceFromDefault(sentence: DefaultSentence): QuizSeedSource {
  return {
    seed: {
      thai_text: sentence.thai_text,
      pronunciation: sentence.pronunciation,
      japanese_translation: sentence.japanese_translation,
      word_breakdown: [
        {
          word: sentence.key_word,
          pronunciation: sentence.key_word_pronunciation,
          meaning: '',
        },
      ],
      key_word: sentence.key_word,
    },
    sentenceId: sentence.sentence_id,
    srsInterval: 0,
    japaneseTranslation: sentence.japanese_translation,
    sentencePronunciation: sentence.pronunciation,
  };
}

function toQuizSeedSourceFromUserDoc(
  doc: FirebaseFirestore.QueryDocumentSnapshot,
): QuizSeedSource {
  const data = doc.data();
  return {
    seed: {
      thai_text: data.thai_text,
      pronunciation: data.pronunciation,
      japanese_translation: data.japanese_translation,
      word_breakdown: data.word_breakdown || [],
      key_word: data.key_word,
    },
    sentenceId: doc.id,
    srsInterval: -1,
    japaneseTranslation: data.japanese_translation || '',
    sentencePronunciation: data.pronunciation || '',
  };
}

function shuffleTopCandidates<T>(candidates: T[], count: number): T[] {
  return [...candidates.slice(0, count)].sort(() => Math.random() - 0.5);
}

function toQuizQuestion(
  question: QuizQuestionsResponse['questions'][number],
  source: QuizSeedSource,
): QuizQuestion {
  const clientQuestion = { ...question };
  delete clientQuestion.source_index;

  return {
    ...clientQuestion,
    sentence_id: source.sentenceId,
    srs_interval: source.srsInterval,
    japanese_translation: source.japaneseTranslation,
    sentence_pronunciation: source.sentencePronunciation,
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

  const questionsBySource: Array<QuizQuestion | null> = Array(readySources.length).fill(null);
  const firstAttempt = await generateBatchQuizQuestions(quizGenerationService, readySources, 0);
  for (const result of firstAttempt) {
    questionsBySource[result.sourcePosition] = result.question;
  }

  const retrySourcePositions = questionsBySource
    .map((question, sourcePosition) => question ? null : sourcePosition)
    .filter((sourcePosition): sourcePosition is number => sourcePosition !== null);

  if (retrySourcePositions.length > 0) {
    logger.warn('Batch quiz generation retrying failed sources', {
      event: 'batch_quiz_generation_retrying_failed_sources',
      requested: sources.length,
      failed: retrySourcePositions.length,
    });

    const retrySources = retrySourcePositions.map((sourcePosition) => readySources[sourcePosition]);
    const retryAttempt = await generateBatchQuizQuestions(quizGenerationService, retrySources, 1);
    for (const result of retryAttempt) {
      const originalSourcePosition = retrySourcePositions[result.sourcePosition];
      questionsBySource[originalSourcePosition] = result.question;
    }
  }

  const skipped = questionsBySource.filter((question) => question === null).length;
  if (skipped > 0) {
    logger.error('Batch quiz generation skipped sources after retry', {
      event: 'batch_quiz_generation_skipped_sources_after_retry',
      requested: readySources.length,
      skipped,
    });
  }

  return questionsBySource.filter((question): question is QuizQuestion => question !== null);
}

/**
 * 複数の例文に対してAIでクイズをまとめて生成し、source_index と key_word 一致を検証する。
 *
 * - 生成失敗やサニタイズで除外された問題は戻り値に含めない
 * - key_word 不一致時は呼び出し側で1回だけリトライする
 */
async function generateBatchQuizQuestions(
  quizGenerationService: QuizGenerationService,
  sources: QuizSeedSource[],
  attempt: number,
): Promise<Array<{ sourcePosition: number; question: QuizQuestion }>> {
  const result = await quizGenerationService.generateQuizQuestions(sources.map((source) => source.seed));
  const usedSourcePositions = new Set<number>();
  const questions: Array<{ sourcePosition: number; question: QuizQuestion }> = [];

  result.questions.forEach((question, responseIndex) => {
    const sourcePosition = resolveSourcePosition(
      question,
      responseIndex,
      sources.length,
      usedSourcePositions,
    );
    if (sourcePosition === null) return;

    const source = sources[sourcePosition];
    if (!matchesKeyWord(question, source.seed)) {
      const details = {
        expected: source.seed.key_word,
        got: question.correct_answer,
        sourcePosition,
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
      return;
    }

    usedSourcePositions.add(sourcePosition);
    questions.push({
      sourcePosition,
      question: toQuizQuestion(question, source),
    });
  });

  return questions;
}

function resolveSourcePosition(
  question: QuizQuestionsResponse['questions'][number],
  responseIndex: number,
  sourceCount: number,
  usedSourcePositions: Set<number>,
): number | null {
  const sourcePosition = Number.isInteger(question.source_index) ?
    question.source_index as number :
    responseIndex;

  if (sourcePosition < 0 || sourcePosition >= sourceCount) {
    logger.warn('Dropping quiz question due to invalid source_index', {
      event: 'quiz_question_dropped_invalid_source_index',
      sourceIndex: question.source_index,
      responseIndex,
      sourceCount,
    });
    return null;
  }

  if (usedSourcePositions.has(sourcePosition)) {
    logger.warn('Dropping quiz question due to duplicate source_index', {
      event: 'quiz_question_dropped_duplicate_source_index',
      sourceIndex: sourcePosition,
      responseIndex,
    });
    return null;
  }

  return sourcePosition;
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


/**
 * ユーザーの全例文からSRSアルゴリズムに基づいて復習対象を選出する。
 *
 * 選出の優先順位:
 *  ① SRS_DAYSからランダムに3間隔を選び、各間隔1文を選出（exact → ±1日の順）
 *  ② ①で埋まらなかった枠を、SRS対象外のユーザー例文（P値低い順）で補充
 *  ③ それでも不足する場合、デフォルト例文で補充
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
    .limit(MAX_USER_SENTENCES_FETCH)
    .get();

  if (allSentencesSnapshot.empty) return [];

  // UVM P値を取得（key_wordが苦手な文を優先するため）
  const userKeyWords = new Set<string>();
  for (const doc of allSentencesSnapshot.docs) {
    const kw = doc.data().key_word;
    if (kw && typeof kw === 'string') userKeyWords.add(kw);
  }
  // デフォルト例文の key_word も含めて一括取得（③で再利用）
  for (const s of DEFAULT_SENTENCES) userKeyWords.add(s.key_word);
  const pMap = await fetchUvmPValues(uid, userKeyWords);

  // 各例文の作成日からの経過日数を事前計算（SRS間隔との照合に使用）
  const jstNowMs = jstNow.getTime();
  const docsWithDays = allSentencesSnapshot.docs.map(doc => {
    const createdAt = doc.data().created_at?.toDate();
    let diffDays = -1;
    if (createdAt) {
        const jstCreatedMs = createdAt.getTime() + JST_OFFSET_MS;
      diffDays = Math.floor((jstNowMs - jstCreatedMs) / (24 * 60 * 60 * 1000));
    }
    return { doc, diffDays };
  });

  const sortByP = buildSortByP(pMap);

  const remainingSlots = () => MAX_REVIEW_SENTENCES - selected.length;

  const addCandidate = (candidate: SelectedSentence): void => {
    selected.push(candidate);
    usedIds.add(candidate.id);
  };

  // ① SRS_DAYSからランダムに3間隔を選び、各間隔1文を選出（当日±1日の中でP値が最低の文）
  const shuffledIntervals = [...SRS_DAYS].sort(() => Math.random() - 0.5).slice(0, MAX_REVIEW_SENTENCES);
  for (const interval of shuffledIntervals) {
    if (remainingSlots() <= 0) break;

    const candidates = docsWithDays
      .filter(({ doc, diffDays }) => !usedIds.has(doc.id) && diffDays >= interval - 1 && diffDays <= interval + 1)
      .sort(sortByP);
    if (candidates.length > 0) {
      addCandidate(toSelectedUserSentence(candidates[0].doc, interval));
    }
  }

  // ② SRSで埋まらなかった枠を、残りユーザー例文からP値が低い順に補充
  if (remainingSlots() > 0) {
    const remaining = allSentencesSnapshot.docs
      .filter(doc => !usedIds.has(doc.id))
      .sort((a, b) => {
        const pA = pMap.get(a.data().key_word) ?? 1;
        const pB = pMap.get(b.data().key_word) ?? 1;
        return pA - pB;
      })
      .map((doc) => toSelectedUserSentence(doc, -1));
    const take = Math.min(remaining.length, remainingSlots());
    for (const candidate of remaining.slice(0, take)) addCandidate(candidate);
  }

  // ③ デフォルト例文から不足分を補充
  if (remainingSlots() > 0) {
    const defaults = await sortDefaultsByPriority(uid, DEFAULT_SENTENCES, pMap, estimatedVocab);
    const defaultCandidates = defaults
      .filter((s) => !usedIds.has(s.sentence_id))
      .map((s) => toSelectedDefaultSentence(s));
    const take = Math.min(defaultCandidates.length, remainingSlots());
    for (const candidate of defaultCandidates.slice(0, take)) addCandidate(candidate);
  }

  return selected;
}

/**
 * デフォルト例文を estimated_vocab ± 10 帯域、prompts.py と同じ語彙レベル、
 * および単語数上限に絞り、effective P の低い順に返す。
 * 条件外の例文は一切含まない。
 *
 * pMap を渡す場合は Firestore 読み取りをスキップして再利用する。
 *
 * @param {string} uid - ユーザーID（UVM P値取得用）
 * @param {DefaultSentence[]} sentences - フィルタ対象のデフォルト例文
 * @param {Map<string, number>} existingPMap - 取得済みのUVM P値
 * @param {number} estimatedVocab - ユーザーの推定語彙数
 * @return {Promise<DefaultSentence[]>} 条件に合うデフォルト例文
 */
async function sortDefaultsByPriority(
  uid: string,
  sentences: DefaultSentence[],
  existingPMap?: Map<string, number>,
  estimatedVocab: number = 0,
): Promise<DefaultSentence[]> {
  const bandLow = Math.max(0, estimatedVocab - FREQ_BAND_HALF);
  const bandHigh = estimatedVocab + FREQ_BAND_HALF;

  // 帯域内、かつ prompts.py の難易度条件に合うものだけに絞る
  const inBand = sentences.filter((s) => (
    s.rank >= bandLow &&
    s.rank <= bandHigh &&
    isDefaultSentenceMatchingDifficulty(s, estimatedVocab)
  ));
  if (inBand.length === 0) return [];

  const pMap = existingPMap ?? await fetchUvmPValues(
    uid,
    new Set(inBand.map((s) => s.key_word)),
  );

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
