/**
 * dailyBatch.ts — 深夜バッチ処理
 *
 * 毎日 JST 0:00 に実行され、以下を行う:
 *   1. ユーザーごとの日次クォータをリセット
 *   2. UVM の P 値を減衰（estimated_vocab ± 20 帯域内のみ）
 *   3. 30日以上前の古い例文を削除
 *
 * dev環境: HTTPトリガー / tester・prod環境: Cloud Scheduler
 */
import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { isDevOnly } from './config/environment';
import { nowJST } from './utils/formatDate';
import { notifyUtcHour } from './utils/notifyUtcHour';
import { deleteUserFirestoreData } from './deleteUserData';
import {
  FREE_DAILY_SENTENCES, FREE_DAILY_QUIZZES,
  PREMIUM_DAILY_SENTENCES, PREMIUM_DAILY_QUIZZES,
} from './constants/quota';

const db = admin.firestore();

const CONCURRENCY = 5;

/**
 * 匿名ユーザー掃除の定数
 *
 * 匿名（Google/Apple未リンク）かつ ANON_INACTIVE_DAYS 日以上非アクティブな
 * ユーザーを完全削除する。アクティブな匿名ユーザーは残し、UVM・SRS等の
 * パーソナライズを維持する（link昇格までの体験を壊さない）。
 */
/**
 * この日数以上トークン更新がない匿名ユーザーを削除対象とする。
 *
 * 匿名 doc は端末の fcm_token を握ったまま残りやすい（匿名で試してから
 * サインインすると解除経路を通らない）。重複トークン掃除で通知の重複自体は
 * 止まるが、残骸を長く残す理由もないため短めに置く。
 */
const ANON_INACTIVE_DAYS = 3;
/** 1回の実行で削除する匿名ユーザーの上限（負荷平準化） */
const MAX_ANON_DELETIONS_PER_RUN = 500;

/**
 * UVM P値減衰の定数
 *
 * 例文選定では estimated_vocab ± 10 帯域内で P が最も低い語を選出する。
 * 新規（未登録）語は P=0.02 で扱うため、露出済みだが復習されていない語の
 * P を毎日 0.01 ずつ減衰させることで、放置された語が新語より優先されるようにする。
 * 全登録単語に適用する。
 */
const P_DECAY_PER_DAY = 0.001;
const P_DECAY_MIN = 0.0;
const BATCH_LIMIT = 500;

async function dailyBatchHandler() {
  console.log('dailyBatch started');

  // 本体処理の前に匿名ユーザーを完全削除する。
  // 掃除の失敗が本体処理を巻き込まないよう try/catch で隔離する。
  try {
    await cleanupAnonymousUsers();
  } catch (e) {
    console.error('cleanupAnonymousUsers failed', e);
  }

  const usersSnapshot = await db.collection('users').get();
  if (usersSnapshot.empty) {
    console.log('No users found');
    return;
  }

  await clearDuplicateFcmTokens(usersSnapshot.docs);

  // CONCURRENCY件ずつ並行処理。allSettledで一部失敗しても継続
  const users = usersSnapshot.docs;
  for (let i = 0; i < users.length; i += CONCURRENCY) {
    const chunk = users.slice(i, i + CONCURRENCY);
    await Promise.allSettled(
      chunk.map(async (userDoc) => {
        await resetQuota(userDoc);
        await decayUvmP(userDoc);
      })
    );
  }

  await cleanOldSentences();
  console.log('dailyBatch completed');
}

/**
 * 非アクティブな匿名ユーザーと、Auth に存在しない孤児 doc を完全削除する。
 *
 * 手順:
 *   1. Auth 全ユーザーを 1000 件ずつページング列挙し、全 uid を authUids に記録
 *      しつつ、匿名（providerData 空 = Google/Apple 未リンク）かつ最終トークン
 *      更新が ANON_INACTIVE_DAYS 日以上前のユーザーを削除
 *   2. Firestore の users を走査し、authUids に無い doc（= 削除済みユーザーの
 *      キャッシュトークンで復活した孤児 doc）の Firestore データを削除
 *
 * 削除は Firestore データ同期削除 → Auth ユーザー削除の順で「完全に消えた状態」を保証。
 * onDelete トリガー(deleteUserData)任せだと非同期のため本体走査時にdocが残る。
 * onDelete の再削除は冪等で無害。1回あたり MAX_ANON_DELETIONS_PER_RUN 件で打ち切り。
 */
async function cleanupAnonymousUsers(): Promise<void> {
  const authUids = new Set<string>();
  const inactiveCutoff =
    Date.now() - ANON_INACTIVE_DAYS * 24 * 60 * 60 * 1000;
  let deleted = 0;
  let capped = false;
  let pageToken: string | undefined;

  // 1. Auth 全ユーザー列挙 → 非アクティブな匿名を削除、全 uid を記録
  do {
    const result = await admin.auth().listUsers(1000, pageToken);
    pageToken = result.pageToken;

    for (const user of result.users) {
      authUids.add(user.uid);

      // 匿名判定: 外部プロバイダ（Google/Apple等）が一切紐づいていない
      if (user.providerData.length > 0) continue;

      // 非アクティブ判定: 最終トークン更新（なければ最終サインイン）が
      // ANON_INACTIVE_DAYS 日以内ならアクティブとみなし残す
      const lastActive = Date.parse(
        user.metadata.lastRefreshTime ??
          user.metadata.lastSignInTime ??
          user.metadata.creationTime
      );
      if (!Number.isNaN(lastActive) && lastActive > inactiveCutoff) continue;
      if (capped) continue;

      try {
        await deleteUserFirestoreData(user.uid);
        await admin.auth().deleteUser(user.uid);
        deleted++;
      } catch (e) {
        console.error(`Failed to delete anonymous user ${user.uid}`, e);
      }

      if (deleted >= MAX_ANON_DELETIONS_PER_RUN) capped = true;
    }
  } while (pageToken);

  // 2. 孤児 doc 掃除: Auth に存在しない users doc の Firestore データを削除
  let orphans = 0;
  const usersSnapshot = await db.collection('users').get();
  for (const userDoc of usersSnapshot.docs) {
    if (authUids.has(userDoc.id)) continue;
    try {
      await deleteUserFirestoreData(userDoc.id);
      orphans++;
    } catch (e) {
      console.error(`Failed to delete orphan doc ${userDoc.id}`, e);
    }
  }

  console.log(
    `cleanupAnonymousUsers: deleted ${deleted} anonymous user(s), ${orphans} orphan doc(s)`
  );
}

/** 最終アクティブとみなすタイムスタンプ（新しいものが勝つ） */
const ACTIVITY_FIELDS = [
  'last_active_at',
  'last_sentence_generated_at',
  'last_notified_at',
  'last_opened_at',
];

function lastActivityMillis(data: Record<string, unknown>): number {
  let latest = 0;
  for (const field of ACTIVITY_FIELDS) {
    const value = data[field] as { toMillis?: () => number } | undefined;
    const millis = value?.toMillis?.();
    if (typeof millis === 'number' && millis > latest) latest = millis;
  }
  return latest;
}

/**
 * 同じ fcm_token を複数の users doc が持っている場合に、登録を残す1件を除いた
 * uid を返す。
 *
 * fcm_token は端末単位の値なのに users/{uid} に持たせているため、同じ端末で
 * アカウントを切り替えると旧 doc に生きたトークンが残り、その端末には使った
 * アカウントの数だけ毎日例文が届く（匿名で試してからサインインした場合など）。
 * クライアントはサインアウト時に自分の登録を解除するが、アプリ削除・再インストールや
 * 匿名からの移行では解除が走らないため、ここを最後の砦にする。
 *
 * 残すのは最終アクティブが最も新しい doc。同着は uid 順で決めて結果を安定させる。
 */
export function duplicateTokenUids(
  users: { id: string; data: Record<string, unknown> }[]
): string[] {
  const byToken = new Map<string, { id: string; activity: number }[]>();
  for (const user of users) {
    const token = user.data.fcm_token;
    if (typeof token !== 'string' || !token) continue;
    const entry = { id: user.id, activity: lastActivityMillis(user.data) };
    const group = byToken.get(token);
    if (group) group.push(entry);
    else byToken.set(token, [entry]);
  }

  const stale: string[] = [];
  for (const group of byToken.values()) {
    if (group.length < 2) continue;
    group.sort((a, b) =>
      b.activity - a.activity || a.id.localeCompare(b.id));
    stale.push(...group.slice(1).map((entry) => entry.id));
  }
  return stale;
}

/** 重複登録のうち最新の1件以外から fcm_token を消す */
async function clearDuplicateFcmTokens(
  docs: FirebaseFirestore.QueryDocumentSnapshot[]
): Promise<void> {
  const stale = duplicateTokenUids(
    docs.map((doc) => ({ id: doc.id, data: doc.data() || {} }))
  );
  if (stale.length === 0) return;

  for (const uid of stale) {
    try {
      await db.collection('users').doc(uid).update({
        fcm_token: admin.firestore.FieldValue.delete(),
        daily_reminder_enabled: false,
      });
    } catch (e) {
      console.error(`Failed to clear duplicate fcm_token for ${uid}`, e);
    }
  }
  console.log(
    `clearDuplicateFcmTokens: cleared ${stale.length} duplicate registration(s)`
  );
}

/** 期限切れ判定の猶予（更新直後の通知遅延で誤って free に落とさないため） */
const EXPIRY_DEMOTION_MARGIN_MS = 24 * 60 * 60 * 1000;

/**
 * tierに応じて remaining_sentences / remaining_quizzes を日次リセット。
 *
 * ストア通知の取りこぼし対策として、subscription.expires_at を24時間以上
 * 過ぎた premium は free に落とす（猶予期間中は維持）。
 * subscription フィールドがない premium（dev環境の手動設定等）は対象外。
 */
export async function resetQuota(
  userDoc: FirebaseFirestore.QueryDocumentSnapshot
): Promise<void> {
  const userData = userDoc.data() || {};
  const tier: string = userData.tier || 'free';
  const subscription = userData.subscription ?? {};
  const expiresAtMs: number | undefined =
    subscription.expires_at?.toMillis?.();

  const subscriptionLapsed =
    tier === 'premium' &&
    typeof expiresAtMs === 'number' &&
    subscription.status !== 'grace_period' &&
    Date.now() - expiresAtMs > EXPIRY_DEMOTION_MARGIN_MS;

  const isPremium = tier === 'premium' && !subscriptionLapsed;
  const sentenceResetValue = isPremium ?
    PREMIUM_DAILY_SENTENCES :
    FREE_DAILY_SENTENCES;
  const quizResetValue = isPremium ?
    PREMIUM_DAILY_QUIZZES :
    FREE_DAILY_QUIZZES;

  if (subscriptionLapsed) {
    console.log(`resetQuota: demoting lapsed premium user ${userDoc.id}`);
  }

  // 配信バッチが時刻でクエリできるよう、毎日ここで作り直す。全ユーザーを
  // どのみち走査しているので追加の読み取りは発生せず、端末の移動や DST 切り替え、
  // 旧クライアントからの設定変更にも1日以内に追従する。
  // 算出不能（DST春の飛び時刻）なら既存値を維持する。
  const utcHour = notifyUtcHour(
    userData.timezone,
    userData.preferred_generation_hour,
  );

  // TODO: is_first_generation / is_first_quiz_generation フラグが旧ユーザーに残存。十分行き渡ったら一括削除する
  await db.collection('users').doc(userDoc.id).set(
    {
      remaining_sentences: sentenceResetValue,
      remaining_quizzes: quizResetValue,
      daily_sentence_generated: false,
      ...(utcHour !== null ? { notify_utc_hour: utcHour } : {}),
      ...(subscriptionLapsed ? {
        tier: 'free',
        subscription: { status: 'expired' },
      } : {}),
    },
    { merge: true }
  );
}

/** 全登録 UVM 語に対し P 減衰を適用（batch上限500件ずつcommit） */
async function decayUvmP(
  userDoc: FirebaseFirestore.QueryDocumentSnapshot,
): Promise<void> {
  const uvmRef = db.collection('users').doc(userDoc.id).collection('uvm');
  const uvmSnapshot = await uvmRef.get();
  if (uvmSnapshot.empty) return;

  let batch = db.batch();
  let writeCount = 0;
  let totalCount = 0;

  for (const doc of uvmSnapshot.docs) {
    const p: number = (doc.data() || {}).p ?? 0;
    if (p <= P_DECAY_MIN) continue;

    const newP = Math.max(P_DECAY_MIN, p - P_DECAY_PER_DAY);
    batch.update(doc.ref, { p: newP });
    writeCount++;
    totalCount++;

    if (writeCount >= BATCH_LIMIT) {
      await batch.commit();
      batch = db.batch();
      writeCount = 0;
    }
  }

  if (writeCount > 0) {
    await batch.commit();
  }

  if (totalCount > 0) {
    console.log(`decayUvmP: uid=${userDoc.id}, updated ${totalCount} word(s)`);
  }
}

/** 30日以上前の例文を全ユーザーからバッチ削除 */
async function cleanOldSentences(): Promise<void> {
  const jstNow = nowJST();
  const thirtyDaysAgo = new Date(jstNow);
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
  thirtyDaysAgo.setHours(0, 0, 0, 0);
  // JST→UTC変換（Firestoreクエリ用）
  const cutoffUtc = new Date(thirtyDaysAgo.getTime() - 9 * 60 * 60 * 1000);

  const usersSnapshot = await db.collection('users').get();

  for (const userDoc of usersSnapshot.docs) {
    const oldSentences = await db
      .collection('users').doc(userDoc.id)
      .collection('sentences')
      .where('created_at', '<', admin.firestore.Timestamp.fromDate(cutoffUtc))
      .get();

    if (oldSentences.empty) continue;

    const batch = db.batch();
    for (const doc of oldSentences.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }
}

/** dev: HTTPトリガー / tester・prod: Cloud Scheduler (JST 0:00) */
export const dailyBatch = isDevOnly()
  ? functions.https.onRequest({
    region: 'asia-northeast1',
    timeoutSeconds: 1800,
  }, async (_req, res) => {
    await dailyBatchHandler();
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
      await dailyBatchHandler();
    }
  );
