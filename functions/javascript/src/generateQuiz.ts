import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { GeminiService, QuizQuestion } from './services/geminiService';
import { getGeminiApiKey } from './services/secretManager';
import { DEFAULT_SENTENCES } from './constants/defaultQuizQuestions';
import { todayJST } from './utils/formatDate';

const db = admin.firestore();

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
    const uid = request.auth?.uid;
    if (!uid) {
      throw new functions.https.HttpsError('unauthenticated', '認証が必要です');
    }

    // Quota check
    const userRef = db.collection('users').doc(uid);
    const userDoc = await userRef.get();
    const userData = userDoc.data() || {};
    const tier: string = userData.tier || 'free';
    const maxCount = tier === 'premium' ? 10 : 1;
    const today = todayJST();
    const lastQuizDate: string = userData.last_quiz_date || '';
    let dailyQuizCount: number = userData.daily_quiz_count || 0;
    if (lastQuizDate !== today) {
      dailyQuizCount = 0;
    }
    if (dailyQuizCount >= maxCount) {
      throw new functions.https.HttpsError('resource-exhausted', `本日のクイズ生成上限（${maxCount}回）に達しました`);
    }

    const apiKey = await getGeminiApiKey();
    const geminiService = new GeminiService(apiKey);

    // review_queueからユーザーの最新エントリ取得
    const reviewSnapshot = await db
      .collection('review_queue')
      .where('uid', '==', uid)
      .orderBy('created_at', 'desc')
      .limit(1)
      .get();

    // review_queueにデータがない or sentencesが空 → デフォルト例文からGemini生成
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

    if (sentences.length === 0) {
      const result = await generateFromDefaults(geminiService);
      await userRef.set({ daily_quiz_count: dailyQuizCount + 1, last_quiz_date: today }, { merge: true });
      return result;
    }

    // 最大20問からランダム5問を抽出（sentences, sentenceIds, srsIntervalsを同期シャッフル）
    const indices = sentences.map((_: unknown, i: number) => i).sort(() => Math.random() - 0.5);
    const selected = indices.slice(0, MAX_QUESTIONS);
    const pickedSentences = selected.map((i: number) => sentences[i]);
    const pickedIds = selected.map((i: number) => sentenceIds[i]);
    const pickedIntervals = selected.map((i: number) => srsIntervals[i]);

    try {
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
 * generateFromDefaults - デフォルト例文（21件）からランダム5問をGeminiで生成
 *
 * review_queueが空のユーザー（初回登録直後など）向けのフォールバック。
 */
async function generateFromDefaults(geminiService: GeminiService): Promise<{ questions: QuizQuestion[] }> {
  const selected = [...DEFAULT_SENTENCES]
    .sort(() => Math.random() - 0.5)
    .slice(0, MAX_QUESTIONS);

  try {
    const quizResult = await geminiService.generateQuizQuestions(
      selected.map(s => ({
        thai_text: s.thai_text,
        pronunciation: s.pronunciation,
        japanese_translation: s.japanese_translation,
        word_breakdown: [],
      }))
    );

    const questions: QuizQuestion[] = quizResult.questions.map((q, i) => ({
      ...q,
      sentence_id: selected[i]?.sentence_id || '',
      srs_interval: 0,
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
 * fillWithDefaults - 5問未満の場合にデフォルト例文からGemini生成して補填
 *
 * 既出のsentence_idを除外し、不足分をデフォルト例文からランダム選出してGemini生成。
 * Gemini生成失敗時は既存の問題のみで返却（部分的成功を許容）。
 */
async function fillWithDefaults(
  geminiService: GeminiService,
  existing: QuizQuestion[]
): Promise<QuizQuestion[]> {
  const needed = MAX_QUESTIONS - existing.length;
  if (needed <= 0) return existing;

  const usedIds = new Set(existing.map(q => q.sentence_id));
  const candidates = DEFAULT_SENTENCES
    .filter(s => !usedIds.has(s.sentence_id))
    .sort(() => Math.random() - 0.5)
    .slice(0, needed);

  if (candidates.length === 0) return existing;

  try {
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
      srs_interval: 0,
      japanese_translation: candidates[i]?.japanese_translation || '',
      sentence_pronunciation: candidates[i]?.pronunciation || '',
    }));

    return [...existing, ...fillerQuestions];
  } catch (error) {
    console.error('Failed to generate filler quiz:', error);
    return existing;
  }
}
