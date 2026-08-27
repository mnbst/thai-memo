/**
 * genQuotaGolden.ts — dailyBatch の resetQuota が書き込む内容を JS 実装から書き出す。
 *
 * Go 版 quotaResetPayload との差分テスト（functions/go/daily_batch_golden_test.go）に使う。
 * firebase-admin / firebase-functions は require をフックして差し替える。
 * jest 無しで本物の src/dailyBatch.ts を読ませるため。
 * 出力先: functions/javascript/scripts/quota_golden.json
 */
import * as fs from 'fs';
import * as path from 'path';

/* eslint-disable @typescript-eslint/no-explicit-any */

// --- 時刻を固定する -------------------------------------------------------
// resetQuota は Date.now() と new Date() を直に呼ぶ。Go 側へは now を明示的に
// 渡して比較するので、JS 側もここで固定しないと突き合わせられない。
const NOW_MS = Date.parse('2026-08-27T15:30:00Z');
const RealDate = Date;
class FixedDate extends RealDate {
  constructor(...args: any[]) {
    if (args.length === 0) super(NOW_MS);
    else super(...(args as []));
  }
  static now() {
    return NOW_MS;
  }
}
(global as any).Date = FixedDate;

// --- firebase-admin / firebase-functions のスタブ -------------------------
const SERVER_TIMESTAMP = { __sentinel: 'serverTimestamp' };
const DELETE_SENTINEL = { __sentinel: 'delete' };

function makeTimestamp(ms: number) {
  return { __timestamp: ms, toMillis: () => ms, toDate: () => new RealDate(ms) };
}

let captured: any = null;

const adminStub: any = {
  firestore: Object.assign(
    () => ({
      collection: () => ({
        doc: () => ({
          set: async (payload: any) => {
            captured = payload;
          },
        }),
      }),
    }),
    {
      Timestamp: {
        fromMillis: makeTimestamp,
        fromDate: (d: Date) => makeTimestamp(d.getTime()),
      },
      FieldValue: {
        serverTimestamp: () => SERVER_TIMESTAMP,
        delete: () => DELETE_SENTINEL,
      },
    }
  ),
  auth: () => ({}),
  apps: [],
};

const functionsStub: any = {
  https: { onRequest: (_c: unknown, h: unknown) => h },
  scheduler: { onSchedule: (_c: unknown, h: unknown) => h },
  // deleteUserData.ts が読み込み時に評価する v1 の auth トリガー
  region: () => ({ auth: { user: () => ({ onDelete: (h: unknown) => h }) } }),
};

const Module = require('module');
const origLoad = Module._load;
Module._load = function (request: string, ...rest: any[]) {
  if (request === 'firebase-admin') return adminStub;
  if (request === 'firebase-functions/v2') return functionsStub;
  if (request === 'firebase-functions/v1') return functionsStub;
  return origLoad.call(this, request, ...rest);
};

// dailyBatch は読み込み時に admin.firestore() を呼ぶので、スタブ設置後に require する。
const { resetQuota, duplicateTokenUids } = require('../src/dailyBatch');

// --- ケース生成 -----------------------------------------------------------

/** 再現可能な擬似乱数（mulberry32） */
function rng(seed: number) {
  return function () {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const DAY = 24 * 60 * 60 * 1000;
const rand = rng(20260827);
const pick = <T>(xs: T[]): T => xs[Math.floor(rand() * xs.length)];

const TIERS = ['free', 'premium', undefined, 'unknown-tier'];
const PLATFORMS = ['ios', 'android', 'manual', undefined, 'web'];
const STATUSES = ['active', 'canceled', 'grace_period', 'expired', undefined];
// 期限切れ判定の境界（24h / 30日）をまたぐオフセットを必ず含める
const EXPIRY_OFFSETS = [
  -40 * DAY, -31 * DAY, -30 * DAY, -30 * DAY + 1, -25 * DAY,
  -2 * DAY, -DAY - 1, -DAY, -DAY + 1, -3600_000, 0, 5 * DAY, null,
];
// トライアル期限（JST 0:00 に揃っているもの・いないものの両方）
const JST = 9 * 60 * 60 * 1000;
const alignedFuture = Math.ceil((NOW_MS + 2 * DAY + JST) / DAY) * DAY - JST;
const TRIALS = [
  null, alignedFuture, alignedFuture + 3600_000, NOW_MS + 3600_000,
  NOW_MS - 3600_000, NOW_MS, NOW_MS - 5 * DAY,
];
const TIMEZONES = [
  undefined, 'Asia/Tokyo', 'Asia/Kolkata', 'America/Los_Angeles',
  'Pacific/Chatham', 'Not/AZone', '', 'Europe/Berlin',
];
const HOURS = [undefined, 0, 2, 10, 23, 7];

type Case = { uid: string; data: any; expected: any };

/** Timestamp / sentinel をタグ付き JSON に落とす */
function encode(value: any): any {
  if (value === null || value === undefined) return value;
  if (typeof value === 'object') {
    if (value.__sentinel === 'serverTimestamp') return { $server_timestamp: true };
    if (typeof value.__timestamp === 'number') return { $timestamp_ms: value.__timestamp };
    const out: any = {};
    for (const [k, v] of Object.entries(value)) out[k] = encode(v);
    return out;
  }
  return value;
}

const cases: Case[] = [];

async function main() {
  for (let i = 0; i < 4000; i++) {
    const data: any = {};

    const tier = pick(TIERS);
    if (tier !== undefined) data.tier = tier;

    // subscription は「無い」「空」「中身あり」の3通り
    const subShape = rand();
    if (subShape > 0.25) {
      const sub: any = {};
      const platform = pick(PLATFORMS);
      if (platform !== undefined) sub.platform = platform;
      const status = pick(STATUSES);
      if (status !== undefined) sub.status = status;
      const offset = pick(EXPIRY_OFFSETS);
      if (offset !== null) sub.expires_at = makeTimestamp(NOW_MS + offset);
      data.subscription = subShape > 0.35 ? sub : {};
    }

    const trial = pick(TRIALS);
    if (trial !== null) data.premium_trial_expires_at = makeTimestamp(trial);
    if (rand() < 0.3) data.premium_trial_ended_at = makeTimestamp(NOW_MS - DAY);

    const tz = pick(TIMEZONES);
    if (tz !== undefined) data.timezone = tz;
    const hour = pick(HOURS);
    if (hour !== undefined) data.preferred_generation_hour = hour;

    // 既存フィールドが残っていてもリセット結果は変わらないことを確認する
    if (rand() < 0.3) data.remaining_sentences = 99;
    if (rand() < 0.3) data.is_first_generation = true;

    const uid = `case-${i}`;
    captured = null;
    await resetQuota({ id: uid, data: () => data } as any);
    if (captured === null) throw new Error(`${uid}: set が呼ばれていない`);
    cases.push({ uid, data: encode(data), expected: encode(captured) });
  }

  const out = path.join(process.cwd(), 'scripts', 'quota_golden.json');
  fs.writeFileSync(out, JSON.stringify(cases, null, 1));
  console.error(`wrote ${cases.length} cases -> ${out}`);

  // --- duplicateTokenUids ---------------------------------------------
  // 同じ端末トークンを複数 doc が持つ状況を作り、どれを残すかを比べる。
  const TOKENS = ['tok-a', 'tok-b', 'tok-c', '', null, 123];
  const ACT_FIELDS = [
    'last_active_at', 'last_sentence_generated_at',
    'last_notified_at', 'last_opened_at',
  ];
  const dupCases: { users: any[]; expected: string[] }[] = [];
  for (let i = 0; i < 1500; i++) {
    const n = 1 + Math.floor(rand() * 6);
    const users: any[] = [];
    for (let j = 0; j < n; j++) {
      const data: any = {};
      const token = pick(TOKENS);
      if (token !== null) data.fcm_token = token;
      // 活動時刻は同着を作りやすい粗い刻みにする（uid 順の決着を踏ませる）
      for (const f of ACT_FIELDS) {
        if (rand() < 0.45) {
          data[f] = makeTimestamp(NOW_MS - Math.floor(rand() * 5) * DAY);
        }
      }
      // uid の並びと活動順をわざとずらす
      users.push({ id: `u-${(j * 7) % 10}-${j}`, data });
    }
    dupCases.push({ users: users.map((u) => ({ id: u.id, data: encode(u.data) })),
      expected: duplicateTokenUids(users) });
  }
  const dupOut = path.join(process.cwd(), 'scripts', 'dup_token_golden.json');
  fs.writeFileSync(dupOut, JSON.stringify(dupCases, null, 1));
  console.error(`wrote ${dupCases.length} cases -> ${dupOut}`);
}

main();
