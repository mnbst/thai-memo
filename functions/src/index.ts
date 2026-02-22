import * as admin from 'firebase-admin';

// Initialize Firebase Admin
admin.initializeApp();

// Export Cloud Functions
export { generateThaiSentence } from './generateThaiSentence';
export { notificationBatch } from './notificationBatch';
export { sendNotifications } from './sendNotifications';
