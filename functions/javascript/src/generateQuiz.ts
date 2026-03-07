/**
 * generateQuiz.ts — Gemini AI によるタイ語穴埋めクイズ生成
 *
 * 「まいにちタイ語」アプリのクイズ機能のバックエンド。
 * クライアントから onCall で呼び出され、ユーザーの復習対象例文をもとに
 * Google Gemini AI で穴埋め形式のクイズ問題を生成して返却する。
 *
 * 【処理フロー】
 * 1. Firebase Auth 認証チェック
 * 2. 日次クイズ生成クォータチェック（free: 1回/日, premium: 10回/日、JST基準）
 * 3. review_queue からユーザーの最新エントリ（最大20文）を取得
 * 4. ランダムに5問を抽出し、Gemini API で穴埋め問題を生成
 * 5. 5問未満ならデフォルト例文（DEFAULT_SENTENCES）から Gemini 生成して補填
 * 6. review_queue が空の場合はデフォルト例文のみで5問生成
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
import { DEFAULT_SENTENCES } from './constants/defaultQuizQuestions';
import { todayJST } from './utils/formatDate';

/** Firestore インスタンス */
const db = admin.firestore();

/** 1回のクイズ生成で出題する最大問題数 */
const MAX_QUESTIONS = 5;

/**
 * generateQuiz - クイズ生成（onCall、オンデマンド）
 *
 * クライアントからの呼び出しで穴埋めクイズを生成して返却する。
 * 1. 認証チェック + 日次クイズ生成クォータチェック（free: 1回/日, premium: 10回/日、JST基準）
 * 2. review_queueからユーザーの最新エントリ（最大20文）を取得
 * 3. そこからランダムに5問を抽出し、Gemini APIで穴埋め問題を生成
 * 4. 5問未満ならデフォルト例文からGemini生成して補填
 * 5. review_queueが空の場合はデフォルト例文のみで5問生成
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

    // --- 日次クイズ生成クォータチェック ---
    // free ユーザー: 1日1回まで / premium ユーザー: 1日10回まで
    const userRef = db.collection('users').doc(uid);
    const userDoc = await userRef.get();
    const userData = userDoc.data() || {};
    const tier: string = userData.tier || 'free';
    const maxCount = tier === 'premium' ? 10 : 1;
    const today = todayJST();
    const lastQuizDate: string = userData.last_quiz_date || '';
    let dailyQuizCount: number = userData.daily_quiz_count || 0;
    // 日付が変わっていたらカウントをリセット
    if (lastQuizDate !== today) {
      dailyQuizCount = 0;
    }
    // 上限に達している場合はエラーを返す
    if (dailyQuizCount >= maxCount) {
      throw new functions.https.HttpsError('resource-exhausted', `本日のクイズ生成上限（${maxCount}回）に達しました`);
    }

    // GCP Secret Manager から Gemini API キーを取得
    const apiKey = await getGeminiApiKey();
    const geminiService = new GeminiService(apiKey);

    // --- review_queue からユーザーの最新エントリを取得 ---
    // dailyBatch で生成されたキューから最新のものを1件取得
    const reviewSnapshot = await db
      .collection('review_queue')
      .where('uid', '==', uid)
      .orderBy('created_at', 'desc')
      .limit(1)
      .get();

    // review_queue にデータがない場合（初回登録直後など）→ デフォルト例文からクイズ生成
    if (reviewSnapshot.empty) {
      const result = await generateFromDefaults(geminiService);
      await userRef.set({ daily_quiz_count: dailyQuizCount + 1, last_quiz_date: today }, { merge: true });
      return result;
    }

    const reviewDoc = reviewSnapshot.docs[0];
    const reviewData = reviewDoc.data();
    const sentences = reviewData.sentences || [];
    const sentenceIds: string[] = reviewData.sentence_ids || [];
    const srsIntervals: number[] = reviewData.srs_intervals || [];

    // sentences が空の場合もデフォルト例文にフォールバック
    if (sentences.length === 0) {
      const result = await generateFromDefaults(geminiService);
      await userRef.set({ daily_quiz_count: dailyQuizCount + 1, last_quiz_date: today }, { merge: true });
      return result;
    }

    // --- 最大20問からランダム5問を抽出 ---
    // sentences, sentenceIds, srsIntervals はインデックスで対応しているため、
    // インデックスをシャッフルして同期的に抽出する
    const indices = sentences.map((_: unknown, i: number) => i).sort(() => Math.random() - 0.5);
    const selected = indices.slice(0, MAX_QUESTIONS);
    const pickedSentences = selected.map((i: number) => sentences[i]);
    const pickedIds = selected.map((i: number) => sentenceIds[i]);
    const pickedIntervals = selected.map((i: number) => srsIntervals[i]);

    try {
      // Gemini API で穴埋めクイズ問題を生成
      const quizResult = await geminiService.generateQuizQuestions(
        pickedSentences.map((s: {
          thai_text: string;
          pronunciation: string;
          japanese_translation: string;
          word_breakdown: { word: string; pronunciation: string; meaning: string }[];
        }) => ({
          thai_text: s.thai_text,
          pronunciation: s.pronunciation,
          japanese_translation: s.japanese_translation,
          word_breakdown: s.word_breakdown || [],
        }))
      );

      // Gemini の生成結果に sentence_id や srs_interval などのメタデータを付与
      let questions: QuizQuestion[] = quizResult.questions.map((q, i) => ({
        ...q,
        sentence_id: pickedIds[i] || '',
        srs_interval: pickedIntervals[i] || 0,
        japanese_translation: pickedSentences[i]?.japanese_translation || '',
        sentence_pronunciation: pickedSentences[i]?.pronunciation || '',
      }));

      // 5問未満ならデフォルト例文からGemini生成して補填
      if (questions.length < MAX_QUESTIONS) {
        questions = await fillWithDefaults(geminiService, questions);
      }

      // クイズ生成回数を更新
      await userRef.set({
        daily_quiz_count: dailyQuizCount + 1,
        last_quiz_date: today,
      }, { merge: true });

      return { questions: questions.slice(0, MAX_QUESTIONS) };
    } catch (error) {
      console.error('Failed to generate quiz:', error);
      throw new functions.https.HttpsError('internal', 'クイズの生成に失敗しました');
    }
  }
);

/**
 * generateFromDefaults - デフォルト例文（20件）からランダム5問を Gemini で生成
 *
 * review_queue が空のユーザー（初回登録直後など）向けのフォールバック処理。
 * あらかじめ用意されたタイ語のデフォルト例文からランダムに5件選出し、
 * Gemini API で穴埋めクイズを生成する。
 *
 * @param geminiService - Gemini API を呼び出すサービスインスタンス
 * @returns クイズ問題の配列を含むオブジェクト
 */
async function generateFromDefaults(geminiService: GeminiService): Promise<{ questions: QuizQuestion[] }> {
  // デフォルト例文からランダムに5問選出
  const selected = [...DEFAULT_SENTENCES]
    .sort(() => Math.random() - 0.5)
    .slice(0, MAX_QUESTIONS);

  try {
    // Gemini API で穴埋めクイズを生成
    const quizResult = await geminiService.generateQuizQuestions(
      selected.map(s => ({
        thai_text: s.thai_text,
        pronunciation: s.pronunciation,
        japanese_translation: s.japanese_translation,
        word_breakdown: [],
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
 * ユーザーの例文からの生成で5問に満たなかった場合、
 * 既出の sentence_id を除外したうえでデフォルト例文からランダム選出し、
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
  existing: QuizQuestion[]
): Promise<QuizQuestion[]> {
  const needed = MAX_QUESTIONS - existing.length;
  if (needed <= 0) return existing;

  // 既出の sentence_id を除外してデフォルト例文から候補を選出
  const usedIds = new Set(existing.map(q => q.sentence_id));
  const candidates = DEFAULT_SENTENCES
    .filter(s => !usedIds.has(s.sentence_id))
    .sort(() => Math.random() - 0.5)
    .slice(0, needed);

  if (candidates.length === 0) return existing;

  try {
    // Gemini API で補填用のクイズ問題を生成
    const quizResult = await geminiService.generateQuizQuestions(
      candidates.map(s => ({
        thai_text: s.thai_text,
        pronunciation: s.pronunciation,
        japanese_translation: s.japanese_translation,
        word_breakdown: [],
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
