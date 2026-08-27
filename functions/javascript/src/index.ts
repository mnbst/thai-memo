import * as admin from 'firebase-admin';

// Initialize Firebase Admin（2nd gen では FIREBASE_CONFIG が未設定の場合があるため明示指定）
const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  ...(projectId && { projectId }),
});

// Firebase Auth triggers that remain on Node.js.
export { deleteUserData } from './deleteUserData';
export { onUserCreate } from './onUserCreate';
