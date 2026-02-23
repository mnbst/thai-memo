const DEV_PROJECT_ID = 'thai-memo-dev';

// 本番以外のプロジェクトID（dev + tester）
const NON_PROD_PROJECT_IDS = [DEV_PROJECT_ID, 'thai-memo-67139'];

function getProjectId(): string {
  return process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || '';
}

/** dev環境のみ（スケジューラ無効） */
export function isDevOnly(): boolean {
  return getProjectId() === DEV_PROJECT_ID;
}

/** dev + tester（本番以外） */
export function isDev(): boolean {
  return NON_PROD_PROJECT_IDS.includes(getProjectId());
}
