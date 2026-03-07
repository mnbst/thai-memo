/**
 * notificationBatch.ts — 深夜バッチ処理（復習キュー生成 + 古い例文削除）
 *
 * 「まいにちタイ語」アプリでは、ユーザーが過去に学習した例文を
 * SRS（間隔反復学習）アルゴリズムに基づいて復習させる仕組みがある。
 *
 * 本ファイルの深夜バッチは毎日 JST 0:00 に実行され、以下の処理を行う:
 *   1. Firestore の review_queue コレクションを全削除（前日分のクリア）
 *   2. 全ユーザーに対して SRS ベースで復習対象の例文を選出し、review_queue に保存
 *   3. 30日以上前の古い例文を Firestore から削除（ストレージ節約）
 *
 * 生成された review_queue は、sendNotifications 関数で FCM 通知の配信時に使用され、
 * また generateQuiz 関数でクイズ問題の生成元データとしても活用される。
 *
 * 【環境別動作】
 * - dev環境: HTTPリクエストで手動実行（スケジューラなし）
 * - tester/prod環境: Cloud Scheduler で JST 0:00 に自動実行
 *
 * タイムアウト: 1800秒（30分）
 * リージョン: asia-northeast1（東京）
 */
import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { isDevOnly } from './config/environment';
import { formatDate, nowJST } from './utils/formatDate';
import { DEFAULT_SENTENCES } from './constants/defaultQuizQuestions';

/** Firestore インスタンス */
const db = admin.firestore();

/**
 * SRS（間隔反復学習）の復習間隔（日数）
 * 例文の作成日から1日後、3日後、7日後、30日後に復習対象として選出される
 */
const SRS_DAYS = [1, 3, 7, 30];

/** 1回のバッチで1ユーザーに対して選出する復習例文の最大数 */
const MAX_REVIEW_SENTENCES = 20;

/** SRS各間隔ごとに選出する例文の最大数 */
const MAX_PER_INTERVAL = 5;

/** ユーザー処理の並行実行数（同時に処理するユーザー数） */
const CONCURRENCY = 5;

/**
 * notificationBatchHandler - 深夜バッチのメイン処理
 *
 * 全ユーザーの review_queue を再生成する。
 * 1. review_queue コレクションを全削除（前日分のクリア）
 * 2. 全ユーザーを CONCURRENCY 件ずつ並行処理（processUser）
 * 3. 30日以上前の例文を Firestore から削除（cleanOldSentences）
 *
 * スケジュール: JST 0:00（prod/tester） / HTTP手動実行（dev）
 * タイムアウト: 1800秒
 */
async function notificationBatchHandler() {
  console.log('notificationBatch started');

  // 前日分の review_queue を全削除してからリビルドする
  await deleteCollection('review_queue');

  // 全ユーザーのドキュメントを取得
  const usersSnapshot = await db.collection('users').get();

  if (usersSnapshot.empty) {
    console.log('No users found');
    return;
  }

  // JST基準の現在日時と日付文字列を取得（SRS計算に使用）
  const jstNow = nowJST();
  const today = formatDate(jstNow);

  let totalQueued = 0;

  // ユーザーを CONCURRENCY 件ずつのチャンクに分割して並行処理
  // Promise.allSettled を使い、一部ユーザーの処理失敗が他に影響しないようにする
  const users = usersSnapshot.docs;
  for (let i = 0; i < users.length; i += CONCURRENCY) {
    const chunk = users.slice(i, i + CONCURRENCY);
    const results = await Promise.allSettled(
      chunk.map(userDoc => processUser(userDoc.id, jstNow, today))
    );
    for (const r of results) {
      if (r.status === 'fulfilled' && r.value) totalQueued++;
    }
  }

  // 30日以上前の古い例文を削除してストレージを節約
  await cleanOldSentences();

  console.log(`notificationBatch completed: users_queued=${totalQueued}`);
}

/**
 * processUser - ユーザー単位の review_queue 生成
 *
 * 指定ユーザーの例文を SRS アルゴリズムで選出し、
 * Firestore の review_queue コレクションに1ドキュメントとして保存する。
 * 選出された例文が0件の場合はスキップする（false を返却）。
 *
 * @param uid - Firebase Auth のユーザーID
 * @param jstNow - JST基準の現在日時（SRS日数計算に使用）
 * @param today - JST基準の今日の日付文字列（YYYY-MM-DD形式）
 * @returns true: キューに追加成功 / false: スキップまたはエラー
 */
async function processUser(
  uid: string,
  jstNow: Date,
  today: string,
): Promise<boolean> {
  try {
    // SRSベースで復習対象の例文を選出
    const selectedSentences = await selectSentencesBySRS(uid, jstNow);

    // 選出例文が0件の場合はスキップ
    if (selectedSentences.length === 0) {
      return false;
    }

    // review_queue に1ドキュメントとして保存
    // sentences: クイズ生成時に使用する例文データ（タイ文・発音・日本語訳・単語分解）
    // sentence_ids: 元の例文ドキュメントID（クイズ結果の紐づけに使用）
    // srs_intervals: 各例文のSRS間隔（クライアント側の表示に使用）
    await db.collection('review_queue').doc().set({
      uid,
      scheduled_date: today,
      sentences: selectedSentences.map(s => ({
        thai_text: s.data.thai_text,
        pronunciation: s.data.pronunciation,
        japanese_translation: s.data.japanese_translation,
        word_breakdown: s.data.word_breakdown || [],
      })),
      sentence_ids: selectedSentences.map(s => s.id),
      srs_intervals: selectedSentences.map(s => s.srsInterval),
      question_count: selectedSentences.length,
      sent: false,  // sendNotifications で送信済みになると true に更新される
      created_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    return true;
  } catch (error) {
    console.error(`Error processing user ${uid}:`, error);
    return false;
  }
}

/**
 * selectSentencesBySRS - SRS（間隔反復学習）ベースの例文選出（最大20件）
 *
 * ユーザーの全例文を Firestore から取得し、以下の優先度で最大20件を選出する:
 *
 *   【優先度1〜4】SRS各間隔（1,3,7,30日）ごとに:
 *     1. ジャスト該当日（±0日）から最大5件取得
 *     2. 5件未満なら±1日の範囲からランダム補填して5件にする
 *
 *   【優先度5】全間隔合計で20件未満なら:
 *     - 上記に該当しないユーザー例文からランダム補充
 *
 *   【優先度6】それでも20件未満なら:
 *     - デフォルト例文（DEFAULT_SENTENCES: 20件）からランダム補充
 *
 * @param uid - Firebase Auth のユーザーID
 * @param jstNow - JST基準の現在日時
 * @returns 選出された例文の配列（最大20件）
 */

/** 選出された例文の情報を保持する型 */
interface SelectedSentence {
  /** 例文のドキュメントID（Firestore上のID、またはデフォルト例文の場合は "default_N"） */
  id: string;
  /** 例文のデータ（thai_text, pronunciation, japanese_translation, word_breakdown） */
  data: FirebaseFirestore.DocumentData;
  /** この例文が選出されたSRS間隔（日数）。-1: SRS対象外のランダム補充、0: デフォルト例文 */
  srsInterval: number;
}

async function selectSentencesBySRS(
  uid: string,
  jstNow: Date
): Promise<SelectedSentence[]> {
  const selected: SelectedSentence[] = [];
  /** 重複選出を防ぐためのIDセット */
  const usedIds = new Set<string>();

  // ユーザーの全例文を作成日時の降順で取得
  const allSentencesSnapshot = await db
    .collection('users').doc(uid)
    .collection('sentences')
    .orderBy('created_at', 'desc')
    .get();

  // 例文が1件もない場合は空配列を返す（デフォルト例文のみで補充される）
  if (allSentencesSnapshot.empty) return [];

  // 各例文の作成日からの経過日数を事前計算（JST基準）
  // パフォーマンスのため、ループ外で1回だけ計算しておく
  const jstNowMs = jstNow.getTime();
  const docsWithDays = allSentencesSnapshot.docs.map(doc => {
    const createdAt = doc.data().created_at?.toDate();
    let diffDays = -1;
    if (createdAt) {
      // Firestore の Timestamp を JST に変換してから日数差を計算
      const jstCreated = new Date(createdAt.toLocaleString('en-US', { timeZone: 'Asia/Tokyo' }));
      diffDays = Math.floor((jstNowMs - jstCreated.getTime()) / (24 * 60 * 60 * 1000));
    }
    return { doc, diffDays };
  });

  // 【優先度1〜4】SRS各間隔（1,3,7,30日）ごとに例文を選出
  // 各間隔で最大5件、ジャスト該当日→±1日の範囲で選出
  for (const days of SRS_DAYS) {
    if (selected.length >= MAX_REVIEW_SENTENCES) break;

    // ジャスト該当日（±0日）の例文を取得
    const exact = docsWithDays.filter(d =>
      !usedIds.has(d.doc.id) && d.diffDays === days
    );
    const take = Math.min(MAX_PER_INTERVAL, exact.length, MAX_REVIEW_SENTENCES - selected.length);
    for (let i = 0; i < take; i++) {
      selected.push({ id: exact[i].doc.id, data: exact[i].doc.data(), srsInterval: days });
      usedIds.add(exact[i].doc.id);
    }

    // 5件未満なら±1日の範囲からランダム補填（SRS間隔に近い例文を追加）
    const needed = Math.min(MAX_PER_INTERVAL - take, MAX_REVIEW_SENTENCES - selected.length);
    if (needed > 0) {
      const nearby = docsWithDays
        .filter(d => !usedIds.has(d.doc.id) && d.diffDays >= days - 1 && d.diffDays <= days + 1)
        .sort(() => Math.random() - 0.5);  // ランダムシャッフル
      for (let i = 0; i < Math.min(needed, nearby.length); i++) {
        selected.push({ id: nearby[i].doc.id, data: nearby[i].doc.data(), srsInterval: days });
        usedIds.add(nearby[i].doc.id);
      }
    }
  }

  // 【優先度5】SRS対象外のユーザー例文からランダム補充
  // SRS間隔に該当しなかった残りの例文からランダムに追加して20件を目指す
  if (selected.length < MAX_REVIEW_SENTENCES) {
    const remaining = allSentencesSnapshot.docs
      .filter(doc => !usedIds.has(doc.id))
      .sort(() => Math.random() - 0.5);  // ランダムシャッフル

    for (const doc of remaining) {
      if (selected.length >= MAX_REVIEW_SENTENCES) break;
      selected.push({ id: doc.id, data: doc.data(), srsInterval: -1 });  // srsInterval: -1 はSRS対象外を示す
      usedIds.add(doc.id);
    }
  }

  // 【優先度6】デフォルト例文から補充
  // ユーザーの例文だけでは20件に満たない場合（新規ユーザーなど）、
  // あらかじめ用意されたデフォルト例文（DEFAULT_SENTENCES）から補充する
  if (selected.length < MAX_REVIEW_SENTENCES) {
    const defaults = [...DEFAULT_SENTENCES]
      .sort(() => Math.random() - 0.5);  // ランダムシャッフル

    for (const s of defaults) {
      if (selected.length >= MAX_REVIEW_SENTENCES) break;
      if (usedIds.has(s.sentence_id)) continue;  // 既に選出済みの例文はスキップ
      selected.push({
        id: s.sentence_id,
        data: {
          thai_text: s.thai_text,
          pronunciation: s.pronunciation,
          japanese_translation: s.japanese_translation,
          word_breakdown: [],  // デフォルト例文には単語分解データがない
        },
        srsInterval: 0,  // srsInterval: 0 はデフォルト例文を示す
      });
      usedIds.add(s.sentence_id);
    }
  }

  return selected;
}

/**
 * cleanOldSentences - 30日以上前の例文を Firestore から一括削除
 *
 * ストレージ節約のため、全ユーザーの sentences サブコレクションから
 * 作成日が30日以上前の例文ドキュメントをバッチ削除する。
 * 日付の計算は JST 基準で行う。
 */
async function cleanOldSentences(): Promise<void> {
  // JST基準で30日前の0:00を計算
  const jstNow = nowJST();
  const thirtyDaysAgo = new Date(jstNow);
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
  thirtyDaysAgo.setHours(0, 0, 0, 0);
  // JST 0:00 = UTC前日15:00 なのでUTCに変換（Firestoreクエリ用）
  const cutoffUtc = new Date(thirtyDaysAgo.getTime() - 9 * 60 * 60 * 1000);

  // 全ユーザーをループして古い例文を削除
  const usersSnapshot = await db.collection('users').get();

  for (const userDoc of usersSnapshot.docs) {
    // カットオフ日時より前に作成された例文を検索
    const oldSentences = await db
      .collection('users').doc(userDoc.id)
      .collection('sentences')
      .where('created_at', '<', admin.firestore.Timestamp.fromDate(cutoffUtc))
      .get();

    if (oldSentences.empty) continue;

    // Firestore のバッチ書き込みで一括削除
    const batch = db.batch();
    for (const doc of oldSentences.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }
}

/**
 * notificationBatch — Cloud Function のエクスポート
 *
 * 環境によって実行方法が異なる:
 * - dev環境: HTTP トリガー（手動で curl 等で実行）
 * - tester/prod環境: Cloud Scheduler で JST 0:00 に自動実行
 */
export const notificationBatch = isDevOnly()
  ? functions.https.onRequest({
      region: 'asia-northeast1',
      timeoutSeconds: 1800,
    }, async (_req, res) => {
      await notificationBatchHandler();
      res.status(200).send('ok');
    })
  : functions.scheduler.onSchedule(
      {
        schedule: '0 0 * * *', // JST 0:00
        region: 'asia-northeast1',
        timeZone: 'Asia/Tokyo',
        timeoutSeconds: 1800,
      },
      async () => {
        await notificationBatchHandler();
      }
    );

/**
 * deleteCollection - Firestore コレクションの全ドキュメントを一括削除
 *
 * Firestore のバッチ書き込み上限（500件）に対応するため、
 * 500件ずつチャンクに分割して削除する。
 *
 * @param collectionPath - 削除対象の Firestore コレクションパス
 */
async function deleteCollection(collectionPath: string): Promise<void> {
  const snapshot = await db.collection(collectionPath).get();
  if (snapshot.empty) return;

  // Firestore のバッチ書き込みは1回500件まで
  const batchSize = 500;
  const docs = snapshot.docs;

  for (let i = 0; i < docs.length; i += batchSize) {
    const batch = db.batch();
    const chunk = docs.slice(i, i + batchSize);
    for (const doc of chunk) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }
}
