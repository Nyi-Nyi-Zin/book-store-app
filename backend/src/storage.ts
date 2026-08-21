import { createReadStream, existsSync } from 'node:fs';
import path from 'node:path';
import { GetObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

const provider = process.env.STORAGE_PROVIDER ?? 'local';
const bucket = process.env.STORAGE_BUCKET ?? '';
const endpoint = process.env.STORAGE_ENDPOINT;
const region = process.env.STORAGE_REGION ?? 'auto';
const accessKeyId = process.env.STORAGE_ACCESS_KEY_ID;
const secretAccessKey = process.env.STORAGE_SECRET_ACCESS_KEY;

const s3 = provider === 's3' && bucket && accessKeyId && secretAccessKey
  ? new S3Client({
      region,
      endpoint: endpoint || undefined,
      forcePathStyle: process.env.STORAGE_FORCE_PATH_STYLE === 'true',
      credentials: { accessKeyId, secretAccessKey },
    })
  : null;

export function storageConfigured(): boolean {
  return provider === 's3' && Boolean(s3 && bucket);
}

export function storageProvider(): string {
  return provider;
}

export async function putObjectFromFile(input: {
  key: string;
  localPath: string;
  contentType: string;
}): Promise<string> {
  if (!existsSync(input.localPath)) throw new Error('Storage source file does not exist');
  if (!s3 || !bucket) return path.resolve(input.localPath);
  await s3.send(new PutObjectCommand({
    Bucket: bucket,
    Key: input.key,
    Body: createReadStream(input.localPath),
    ContentType: input.contentType,
  }));
  return input.key;
}

export async function signedDownloadUrl(key: string, expiresInSeconds = 900): Promise<string | null> {
  if (!s3 || !bucket) return null;
  return getSignedUrl(
    s3,
    new GetObjectCommand({ Bucket: bucket, Key: key }),
    { expiresIn: expiresInSeconds },
  );
}

export function storageReadyForProduction(): boolean {
  return provider === 's3' && storageConfigured();
}
