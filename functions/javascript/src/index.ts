import * as admin from 'firebase-admin';

// Initialize Firebase Admin（2nd gen では FIREBASE_CONFIG が未設定の場合があるため明示指定）
const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  ...(projectId && { projectId }),
});

// Export Cloud Functions
export { dailyBatch, noonReset } from './dailyBatch';
export { deleteUserData } from './deleteUserData';
export { generateQuiz } from './generateQuiz';
export { onUserCreate } from './onUserCreate';
export { verifySubscription } from './verifySubscription';
export { subscriptionStatus } from './subscriptionStatus';
export { handlePlayNotification } from './handlePlayNotification';
export { handleAppStoreNotification } from './handleAppStoreNotification';
export { sendContactEmail } from './sendContactEmail';
