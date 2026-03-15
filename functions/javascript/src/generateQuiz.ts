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
import { GeminiService, QuizQuestion } from './services/geminiService';
import { getGeminiApiKey } from './services/secretManager';
import { DEFAULT_SENTENCES, DefaultSentence } from './constants/defaultQuizQuestions';
import { GEMINI_MODEL_FREE, GEMINI_MODEL_PREMIUM } from './config/constants';
import { nowJST } from './utils/formatDate';


/** Firestore インスタンス */
const db = admin.firestore();

/** 1回のクイズ生成で出題する最大問題数 */
const MAX_QUESTIONS = 5;

/**
 * SRS（Spaced Repetition System / 間隔反復）の復習間隔（日数）
 *
 * 学習した例文を「1日後 → 3日後 → 7日後 → 14日後 → 30日後」に再出題することで
 * 忘却曲線に沿った効率的な定着を狙う。
 */
const SRS_DAYS = [1, 3, 7, 14, 30];
/** SRS 選出で確保する最大例文数 */
const MAX_REVIEW_SENTENCES = 5;
/** ①+②の後にユーザー例文として最低限確保したい例文数 */
const MIN_USER_REVIEW_SENTENCES = 3;
/** 各SRS間隔から選出する最大例文数 */
const MAX_PER_INTERVAL = 1;

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

    // --- SRSベースでリアルタイムに復習対象例文を選出 ---
    const selectedSentences = await selectSentencesBySRS(uid, nowJST());

    // ユーザー例文がない場合（初回登録直後など）→ デフォルト例文からクイズ生成
    if (selectedSentences.length === 0) {
      const result = await generateFromDefaults(geminiService, uid);
      await userRef.set({ remaining_quizzes: remainingQuizzes - 1 }, { merge: true });
      return result;
    }

    // 選出された例文からランダム5問を抽出
    const shuffled = [...selectedSentences].sort(() => Math.random() - 0.5);
    const picked = shuffled.slice(0, MAX_QUESTIONS);

    try {
      // Gemini API で穴埋めクイズ問題を生成
      const quizResult = await geminiService.generateQuizQuestions(
        picked.map(s => ({
          thai_text: s.data.thai_text,
          pronunciation: s.data.pronunciation,
          japanese_translation: s.data.japanese_translation,
          word_breakdown: s.data.word_breakdown || [],
          key_word: s.data.key_word,
        }))
      );

      // Gemini の生成結果に sentence_id や srs_interval などのメタデータを付与
      let questions: QuizQuestion[] = quizResult.questions.map((q, i) => ({
        ...q,
        sentence_id: picked[i]?.id || '',
        srs_interval: picked[i]?.srsInterval || 0,
        japanese_translation: picked[i]?.data.japanese_translation || '',
        sentence_pronunciation: picked[i]?.data.pronunciation || '',
      }));

      // 5問未満ならデフォルト例文からGemini生成して補填
      if (questions.length < MAX_QUESTIONS) {
        questions = await fillWithDefaults(geminiService, questions, uid);
      }

      // クイズ生成残回数をデクリメント
      await userRef.set({ remaining_quizzes: remainingQuizzes - 1 }, { merge: true });

      return { questions: questions.slice(0, MAX_QUESTIONS) };
    } catch (error) {
      console.error('Failed to generate quiz:', error);
      throw new functions.https.HttpsError('internal', 'クイズの生成に失敗しました');
    }
  }
);

/**
 * generateFromDefaults - デフォルト例文（32件）から「UVM未登録 → 低P」順に5問を Gemini で生成
 *
 * ユーザー例文がない場合（初回登録直後など）のフォールバック処理。
 *
 * @param geminiService - Gemini API を呼び出すサービスインスタンス
 * @param uid - ユーザーID（UVM P値取得用）
 * @returns クイズ問題の配列を含むオブジェクト
 */
async function generateFromDefaults(geminiService: GeminiService, uid: string): Promise<{ questions: QuizQuestion[] }> {
  // デフォルト例文から「UVM未登録 → 低P」順に5問選出
  const sorted = await sortDefaultsByPriority(uid, DEFAULT_SENTENCES);
  const selected = sorted.slice(0, MAX_QUESTIONS);

  try {
    // Gemini API で穴埋めクイズを生成
    const quizResult = await geminiService.generateQuizQuestions(
      selected.map((s: DefaultSentence) => ({
        thai_text: s.thai_text,
        pronunciation: s.pronunciation,
        japanese_translation: s.japanese_translation,
        word_breakdown: [],
        key_word: s.key_word,
      }))
    );

    // 生成結果にデフォルト例文のメタデータを付与
    const questions: QuizQuestion[] = quizResult.questions.map((q, i) => ({
      ...q,
      sentence_id: selected[i]?.sentence_id || '',
      srs_interval: 0,  // デフォルト例文は SRS 対象外
      japanese_translation: selected[i]?.japanese_translation || '',
      sentence_pronunciation: selected[i]?.pronunciation || '',
    }));

    return { questions };
  } catch (error) {
    console.error('Failed to generate default quiz:', error);
    throw new functions.https.HttpsError('internal', 'クイズの生成に失敗しました');
  }
}

/**
 * fillWithDefaults - 5問未満の場合にデフォルト例文から Gemini 生成して補填
 *
 * SRS選出した例文からの生成で5問に満たなかった場合、
 * 既出の sentence_id を除外したうえでデフォルト例文から「UVM未登録 → 低P」順に選出し、
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
): Promise<QuizQuestion[]> {
  const needed = MAX_QUESTIONS - existing.length;
  if (needed <= 0) return existing;

  // 既出の sentence_id を除外してデフォルト例文から「UVM未登録 → 低P」順に候補を選出
  const usedIds = new Set(existing.map(q => q.sentence_id));
  const available = DEFAULT_SENTENCES.filter(s => !usedIds.has(s.sentence_id));
  const sorted = await sortDefaultsByPriority(uid, available);
  const candidates = sorted.slice(0, needed);

  if (candidates.length === 0) return existing;

  try {
    // Gemini API で補填用のクイズ問題を生成
    const quizResult = await geminiService.generateQuizQuestions(
      candidates.map((s: DefaultSentence) => ({
        thai_text: s.thai_text,
        pronunciation: s.pronunciation,
        japanese_translation: s.japanese_translation,
        word_breakdown: [],
        key_word: s.key_word,
      }))
    );

    const fillerQuestions: QuizQuestion[] = quizResult.questions.map((q, i) => ({
      ...q,
      sentence_id: candidates[i]?.sentence_id || '',
      srs_interval: 0,  // デフォルト例文は SRS 対象外
      japanese_translation: candidates[i]?.japanese_translation || '',
      sentence_pronunciation: candidates[i]?.pronunciation || '',
    }));

    // 既存の問題と補填問題を結合して返す
    return [...existing, ...fillerQuestions];
  } catch (error) {
    // 補填用の生成が失敗しても、既存の問題だけで返す（部分的成功を許容）
    console.error('Failed to generate filler quiz:', error);
    return existing;
  }
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

/**
 * ユーザーの全例文からSRSアルゴリズムに基づいて復習対象を選出する。
 *
 * 選出の優先順位:
 *  ① SRS間隔にジャスト該当する例文（1日前/3日前/7日前/14日前/30日前に学習したもの）
 *  ② ①で不足する場合、±1日の範囲からランダム補填（学習日のズレを吸収）
 *  ③ ①+②で3問に満たない場合、SRS対象外の例文からランダム補充
 *  ④ ユーザーの例文自体が少ない場合、5問になるまでデフォルト例文で補充
 */
async function selectSentencesBySRS(
  uid: string,
  jstNow: Date
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

  /** P値昇順でソート（低P＝苦手な単語を優先） */
  const sortByP = (a: { doc: FirebaseFirestore.QueryDocumentSnapshot }, b: { doc: FirebaseFirestore.QueryDocumentSnapshot }) => {
    const pA = pMap.get(a.doc.data().key_word) ?? 1;
    const pB = pMap.get(b.doc.data().key_word) ?? 1;
    return pA - pB;
  };

  // ① SRS各間隔ごとにジャスト該当日を最大1問選出（P値が低い文を優先）
  for (const days of SRS_DAYS) {
    if (selected.length >= MAX_REVIEW_SENTENCES) break;

    const exact = docsWithDays.filter(d =>
      !usedIds.has(d.doc.id) && d.diffDays === days
    ).sort(sortByP);
    const take = Math.min(MAX_PER_INTERVAL, exact.length, MAX_REVIEW_SENTENCES - selected.length);
    for (let i = 0; i < take; i++) {
      selected.push({ id: exact[i].doc.id, data: exact[i].doc.data(), srsInterval: days });
      usedIds.add(exact[i].doc.id);
    }
  }

  // ② ①で不足したSRS間隔を±1日の範囲から補填（P値が低い文を優先）
  for (const days of SRS_DAYS) {
    if (selected.length >= MAX_REVIEW_SENTENCES) break;

    const alreadySelectedForInterval = selected.some(sentence => sentence.srsInterval === days);
    if (alreadySelectedForInterval) continue;

    const nearby = docsWithDays
      .filter(d =>
        !usedIds.has(d.doc.id) &&
        d.diffDays >= days - 1 &&
        d.diffDays <= days + 1
      )
      .sort(sortByP);

    const candidate = nearby[0];
    if (!candidate) continue;

    selected.push({ id: candidate.doc.id, data: candidate.doc.data(), srsInterval: days });
    usedIds.add(candidate.doc.id);
  }

  // ③ ①+②で3問に満たない場合、SRS対象外の例文からP値が低い順に補充
  if (selected.length < MIN_USER_REVIEW_SENTENCES) {
    const remaining = allSentencesSnapshot.docs
      .filter(doc => !usedIds.has(doc.id))
      .sort((a, b) => {
        const pA = pMap.get(a.data().key_word) ?? 1;
        const pB = pMap.get(b.data().key_word) ?? 1;
        return pA - pB;
      });

    for (const doc of remaining) {
      if (selected.length >= MIN_USER_REVIEW_SENTENCES) break;
      selected.push({ id: doc.id, data: doc.data(), srsInterval: -1 });
      usedIds.add(doc.id);
    }
  }

  // ④ デフォルト例文から5問まで補充（UVM未登録 → 低P順、新規ユーザー等で不足する場合）
  if (selected.length < MAX_REVIEW_SENTENCES) {
    const defaults = await sortDefaultsByPriority(uid, DEFAULT_SENTENCES, pMap);

    for (const s of defaults) {
      if (selected.length >= MAX_REVIEW_SENTENCES) break;
      if (usedIds.has(s.sentence_id)) continue;
      selected.push({
        id: s.sentence_id,
        data: {
          thai_text: s.thai_text,
          pronunciation: s.pronunciation,
          japanese_translation: s.japanese_translation,
          word_breakdown: [],
          key_word: s.key_word,
        },
        srsInterval: 0,
      });
      usedIds.add(s.sentence_id);
    }
  }

  return selected;
}

/**
 * デフォルト例文を「UVM未登録 → UVM低P」の順にソートして返す。
 * UVM未登録の単語を優先し、未知語に触れる機会を増やす。
 * 同グループ内はランダム順。
 *
 * pMap を渡す場合は Firestore 読み取りをスキップして再利用する。
 */
async function sortDefaultsByPriority(
  uid: string,
  sentences: DefaultSentence[],
  existingPMap?: Map<string, number>
): Promise<DefaultSentence[]> {
  const pMap = existingPMap ?? await fetchUvmPValues(uid, new Set(sentences.map(s => s.key_word)));

  return [...sentences].sort((a, b) => {
    const hasA = pMap.has(a.key_word);
    const hasB = pMap.has(b.key_word);
    // UVM未登録を先に（未登録 < 登録済み）
    if (!hasA && hasB) return -1;
    if (hasA && !hasB) return 1;
    // 両方未登録 → ランダム
    if (!hasA && !hasB) return Math.random() - 0.5;
    // 両方登録済み → 低P優先
    const pA = pMap.get(a.key_word)!;
    const pB = pMap.get(b.key_word)!;
    if (pA !== pB) return pA - pB;
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

