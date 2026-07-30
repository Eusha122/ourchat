import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { randomUUID } from "crypto";

const accountId = process.env.R2_ACCOUNT_ID;
const bucketName = process.env.R2_BUCKET_NAME;
const publicUrl = process.env.R2_PUBLIC_URL;

export const r2Configured = Boolean(
  accountId &&
    bucketName &&
    publicUrl &&
    process.env.R2_ACCESS_KEY_ID &&
    process.env.R2_SECRET_ACCESS_KEY,
);

const r2Client = r2Configured
  ? new S3Client({
      region: "auto",
      endpoint: `https://${accountId}.r2.cloudflarestorage.com`,
      credentials: {
        accessKeyId: process.env.R2_ACCESS_KEY_ID!,
        secretAccessKey: process.env.R2_SECRET_ACCESS_KEY!,
      },
    })
  : null;

export async function uploadToR2(params: {
  buffer: Buffer;
  contentType: string;
  keyPrefix: string;
  fileExtension: string;
}): Promise<string> {
  if (!r2Client || !bucketName || !publicUrl) {
    throw new Error("R2 is not configured");
  }

  const key = `${params.keyPrefix}/${randomUUID()}.${params.fileExtension}`;

  await r2Client.send(
    new PutObjectCommand({
      Bucket: bucketName,
      Key: key,
      Body: params.buffer,
      ContentType: params.contentType,
    }),
  );

  return `${publicUrl.replace(/\/$/, "")}/${key}`;
}
