import * as functions from 'firebase-functions/v2';
import * as nodemailer from 'nodemailer';
import { SecretManagerServiceClient } from '@google-cloud/secret-manager';

const secretClient = new SecretManagerServiceClient();

async function getGmailAppPassword(): Promise<string> {
  const projectId = process.env.GCLOUD_PROJECT;
  const [version] = await secretClient.accessSecretVersion({
    name: `projects/${projectId}/secrets/gmail-app-password/versions/latest`,
  });
  const password = version.payload?.data?.toString();
  if (!password) throw new Error('gmail-app-password is empty');
  return password;
}

export const sendContactEmail = functions.https.onCall(
  { region: 'asia-northeast1' },
  async (request) => {
    if (!request.auth) {
      throw new functions.https.HttpsError('unauthenticated', '認証が必要です');
    }

    const { name, email, message } = request.data as {
      name: string;
      email: string;
      message: string;
    };

    if (!name || !email || !message) {
      throw new functions.https.HttpsError('invalid-argument', '必須項目が不足しています');
    }
    if (message.length > 2000) {
      throw new functions.https.HttpsError('invalid-argument', 'メッセージは2000文字以内で入力してください');
    }

    const appPassword = await getGmailAppPassword();
    const transporter = nodemailer.createTransport({
      service: 'gmail',
      auth: {
        user: 'gcp.demo.776@gmail.com',
        pass: appPassword,
      },
    });

    await transporter.sendMail({
      from: '"まいにちタイ語" <gcp.demo.776@gmail.com>',
      to: 'gcp.demo.776@gmail.com',
      subject: `【お問い合わせ】${name}様より`,
      text: [
        `お名前: ${name}`,
        `メールアドレス: ${email}`,
        `ユーザーID: ${request.auth?.uid ?? '未認証'}`,
        '',
        '--- メッセージ ---',
        message,
      ].join('\n'),
    });
  }
);
