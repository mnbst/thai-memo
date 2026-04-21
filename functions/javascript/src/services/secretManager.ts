import { SecretManagerServiceClient } from '@google-cloud/secret-manager';

const secretClient = new SecretManagerServiceClient();

async function getSecretValue(secretId: string): Promise<string> {
  const envName = secretId.toUpperCase().replace(/-/g, '_');
  const envValue = process.env[envName]?.trim();
  if (envValue) {
    return envValue;
  }

  try {
    const projectId = process.env.GCLOUD_PROJECT;
    const secretName = `projects/${projectId}/secrets/${secretId}/versions/latest`;

    const [version] = await secretClient.accessSecretVersion({
      name: secretName,
    });

    const apiKey = version.payload?.data?.toString();
    if (!apiKey) {
      throw new Error('API key is empty');
    }

    return apiKey;
  } catch (error) {
    console.error(`Failed to retrieve ${secretId} from Secret Manager:`, error);
    throw new Error('SECRET_MANAGER_ERROR');
  }
}

export async function getOpenAiApiKey(): Promise<string> {
  return getSecretValue('openai-api-key');
}

export async function getGeminiApiKey(): Promise<string> {
  return getSecretValue('gemini-api-key');
}
