/**
 * dev Firestore に対して JS 版 applyTier を1回だけ流す。
 *
 * Go 版との差分テスト（functions/go/set_user_tier_live_test.go）から呼ばれる。
 * 種まきと比較は Go 側が行い、ここは JS 実装を走らせるだけ。
 *
 *   echo '{"uid":..,"tier":"premium","durationDays":30}' \
 *     | node .difftest-build/scripts/runApplyTier.js
 */
import * as admin from 'firebase-admin';

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: process.env.GCLOUD_PROJECT,
});

// tierService は読み込み時に admin.firestore() を掴むので、
// initializeApp より後に require する（import だと巻き上げられてしまう）。
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { applyTier } = require('../src/services/tierService');

async function main() {
  const chunks: Buffer[] = [];
  for await (const c of process.stdin) chunks.push(c as Buffer);
  const req = JSON.parse(Buffer.concat(chunks).toString());

  const result = await applyTier({
    uid: req.uid,
    tier: req.tier,
    durationDays: req.durationDays,
    source: req.source ?? 'admin',
    actor: req.actor ?? null,
    reason: req.reason,
    force: req.force === true,
  });
  process.stdout.write(JSON.stringify(result));
}

main().catch((e) => {
  process.stdout.write(JSON.stringify({ error: String((e && e.message) || e) }));
});
