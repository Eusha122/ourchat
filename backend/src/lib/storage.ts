import { randomUUID } from "crypto";
import { mkdir, writeFile } from "fs/promises";
import path from "path";
import { r2Configured, uploadToR2 } from "./r2";

const uploadsRoot = path.join(process.cwd(), "uploads");

/// Uses R2 when configured; otherwise saves to a local `uploads/` directory
/// served by Express, so chat attachments work out of the box in dev without
/// requiring Cloudflare credentials.
export async function uploadFile(params: {
  buffer: Buffer;
  contentType: string;
  keyPrefix: string;
  fileExtension: string;
  publicOrigin: string;
}): Promise<string> {
  if (r2Configured) {
    return uploadToR2(params);
  }

  const dir = path.join(uploadsRoot, params.keyPrefix);
  await mkdir(dir, { recursive: true });
  const filename = `${randomUUID()}.${params.fileExtension}`;
  await writeFile(path.join(dir, filename), params.buffer);

  return `${params.publicOrigin.replace(/\/$/, "")}/uploads/${params.keyPrefix}/${filename}`;
}
