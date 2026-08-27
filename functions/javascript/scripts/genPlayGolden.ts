/**
 * genPlayGolden.ts — verifyPlayPurchase の判定を JS 実装から書き出す。
 *
 * google-auth-library をスタブし、本物の playBilling.ts を通して
 * 「どのレスポンスなら何を返すか」を記録する。
 * Go 版 internal/playbilling との差分テストに使う。
 * 出力先: functions/javascript/scripts/play_golden.json
 */
import * as fs from 'fs';
import * as path from 'path';

/* eslint-disable @typescript-eslint/no-explicit-any */

let stubbedResponse: any = null;
let requestedUrl = '';

const Module = require('module');
const origLoad = Module._load;
Module._load = function (request: string, ...rest: any[]) {
  if (request === 'google-auth-library') {
    return {
      GoogleAuth: class {
        async getClient() {
          return {
            async request({ url }: { url: string }) {
              requestedUrl = url;
              return { data: stubbedResponse };
            },
          };
        }
      },
    };
  }
  return origLoad.call(this, request, ...rest);
};

const { verifyPlayPurchase } = require('../src/services/playBilling');

const STATES = [
  'SUBSCRIPTION_STATE_ACTIVE',
  'SUBSCRIPTION_STATE_CANCELED',
  'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
  'SUBSCRIPTION_STATE_ON_HOLD',
  'SUBSCRIPTION_STATE_PAUSED',
  'SUBSCRIPTION_STATE_EXPIRED',
  'SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED',
  'SUBSCRIPTION_STATE_UNSPECIFIED',
  'SOMETHING_NEW_FROM_GOOGLE',
];

const EXPIRY = '2026-09-30T12:34:56.789Z';

type Case = {
  name: string;
  response: any;
  requested_url: string;
  valid: boolean;
  expires_at: number | null;
  auto_renewing: boolean;
  status: string;
};

async function main() {
  const specs: { name: string; response: any }[] = [];

  for (const state of STATES) {
    specs.push({
      name: `${state} / 自動更新ON`,
      response: {
        kind: 'androidpublisher#subscriptionPurchaseV2',
        subscriptionState: state,
        lineItems: [{
          productId: 'premium_monthly',
          expiryTime: EXPIRY,
          autoRenewingPlan: { autoRenewEnabled: true },
        }],
      },
    });
    specs.push({
      name: `${state} / 自動更新OFF`,
      response: {
        kind: 'androidpublisher#subscriptionPurchaseV2',
        subscriptionState: state,
        lineItems: [{
          productId: 'premium_monthly',
          expiryTime: EXPIRY,
          autoRenewingPlan: { autoRenewEnabled: false },
        }],
      },
    });
  }

  specs.push({
    name: 'expiryTime なし → expired',
    response: {
      kind: 'k', subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
      lineItems: [{ productId: 'premium_monthly', expiryTime: '' }],
    },
  });
  specs.push({
    name: 'lineItems が空 → expired',
    response: {
      kind: 'k', subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE', lineItems: [],
    },
  });
  specs.push({
    name: 'lineItems ごと無い → expired',
    response: { kind: 'k', subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE' },
  });
  specs.push({
    name: 'autoRenewingPlan なし → autoRenewing=false',
    response: {
      kind: 'k', subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
      lineItems: [{ productId: 'premium_monthly', expiryTime: EXPIRY }],
    },
  });
  specs.push({
    name: 'オフセット付きの expiryTime',
    response: {
      kind: 'k', subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
      lineItems: [{
        productId: 'premium_monthly',
        expiryTime: '2026-09-30T21:34:56+09:00',
        autoRenewingPlan: { autoRenewEnabled: true },
      }],
    },
  });
  specs.push({
    name: 'ナノ秒精度の expiryTime',
    response: {
      kind: 'k', subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
      lineItems: [{
        productId: 'premium_monthly',
        expiryTime: '2026-09-30T12:34:56.123456789Z',
        autoRenewingPlan: { autoRenewEnabled: true },
      }],
    },
  });

  const cases: Case[] = [];
  for (const spec of specs) {
    stubbedResponse = spec.response;
    requestedUrl = '';
    const r = await verifyPlayPurchase(
      'com.thaimemo.thai_memo', 'premium_monthly', 'token-abc123'
    );
    cases.push({
      name: spec.name,
      response: spec.response,
      requested_url: requestedUrl,
      valid: r.valid,
      expires_at: r.expiresAt ? r.expiresAt.getTime() : null,
      auto_renewing: r.autoRenewing,
      status: r.status,
    });
  }

  const out = path.join(process.cwd(), 'scripts', 'play_golden.json');
  fs.writeFileSync(out, JSON.stringify(cases, null, 1));
  console.error(`wrote ${cases.length} cases -> ${out}`);
}

main();
