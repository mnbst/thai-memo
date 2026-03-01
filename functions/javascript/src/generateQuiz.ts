import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { GeminiService, QuizQuestion } from './services/geminiService';
import { getGeminiApiKey } from './services/secretManager';
import { DEFAULT_SENTENCES } from './constants/defaultQuizQuestions';

const db = admin.firestore();

const MAX_QUESTIONS = 5;

/**
 * クイズ生成（オンデマンド）: review_queueまたはデフォルト例文 → Geminiでクイズ生成 → クライアントに返却
 */
export const generateQuiz = functions.https.onCall(
  {
    region: 'asia-northeast1',
    timeoutSeconds: 60,
    memory: '512MiB',
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new functions.https.HttpsError('unauthenticated', '認証が必要です');
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
      return await generateFromDefaults(geminiService);
    }

    const reviewDoc = reviewSnapshot.docs[0];
    const reviewData = reviewDoc.data();
    const sentences = reviewData.sentences || [];
    const sentenceIds: string[] = reviewData.sentence_ids || [];
    const srsIntervals: number[] = reviewData.srs_intervals || [];

    if (sentences.length === 0) {
      return await generateFromDefaults(geminiService);
    }

    try {
      const quizResult = await geminiService.generateQuizQuestions(
        sentences.map((s: {
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
        sentence_id: sentenceIds[i] || '',
        srs_interval: srsIntervals[i] || 0,
        japanese_translation: sentences[i]?.japanese_translation || '',
        sentence_pronunciation: sentences[i]?.pronunciation || '',
      }));

      // 5問未満ならデフォルト例文からGemini生成して補填
      if (questions.length < MAX_QUESTIONS) {
        questions = await fillWithDefaults(geminiService, questions);
      }

      return { questions: questions.slice(0, MAX_QUESTIONS) };
    } catch (error) {
      console.error('Failed to generate quiz:', error);
      throw new functions.https.HttpsError('internal', 'クイズの生成に失敗しました');
    }
  }
);

/**
 * デフォルト例文からGemini経由でクイズを生成
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
 * 5問未満の場合、デフォルト例文からGemini生成して補填
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
