const DEV_PROJECT_IDS = ['thai-memo-67139', 'thai-memo-dev'];

export function isDev(): boolean {
  const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || '';
  return DEV_PROJECT_IDS.includes(projectId);
}
