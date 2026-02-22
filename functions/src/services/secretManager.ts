import { SecretManagerServiceClient } from '@google-cloud/secret-manager';

const secretClient = new SecretManagerServiceClient();

export async function getGeminiApiKey(): Promise<string> {
  try {
    const projectId = process.env.GCLOUD_PROJECT;
    const secretName = `projects/${projectId}/secrets/gemini-api-key/versions/latest`;

    const [version] = await secretClient.accessSecretVersion({
      name: secretName,
    });

    const apiKey = version.payload?.data?.toString();
    if (!apiKey) {
      throw new Error('API key is empty');
    }

    return apiKey;
  } catch (error) {
    console.error('Failed to retrieve API key from Secret Manager:', error);
    throw new Error('SECRET_MANAGER_ERROR');
  }
}
