import { v2 as cloudinary } from "cloudinary";
import { uploadFile } from "./storage";

const cloudName = process.env.CLOUDINARY_CLOUD_NAME?.trim();
const apiKey = process.env.CLOUDINARY_API_KEY?.trim();
const apiSecret = process.env.CLOUDINARY_API_SECRET?.trim();

export const cloudinaryConfigured = Boolean(cloudName && apiKey && apiSecret);

if (cloudinaryConfigured) {
  cloudinary.config({
    cloud_name: cloudName,
    api_key: apiKey,
    api_secret: apiSecret,
    secure: true,
  });
}

export type StoredMedia = {
  url: string;
  thumbnailUrl: string | null;
  width: number | null;
  height: number | null;
  isVideo: boolean;
};

/// Cloudinary derives thumbnails on the fly from the delivery URL, so the
/// grid can fetch small crops instead of full-resolution originals.
function thumbnailFor(url: string): string | null {
  const marker = "/upload/";
  const at = url.indexOf(marker);
  if (at === -1) return null;
  return `${url.slice(0, at + marker.length)}c_fill,w_500,h_500,q_auto,f_auto/${url.slice(
    at + marker.length,
  )}`;
}

/// Stores album media. Prefers Cloudinary when it's configured; otherwise
/// falls back to the same R2/local-disk path chat attachments already use, so
/// the feature works before credentials are in place and switching over is
/// purely an environment change.
export async function uploadAlbumMedia(params: {
  buffer: Buffer;
  contentType: string;
  fileExtension: string;
  publicOrigin: string;
}): Promise<StoredMedia> {
  const isVideo = params.contentType.startsWith("video/");

  if (!cloudinaryConfigured) {
    const url = await uploadFile({
      buffer: params.buffer,
      contentType: params.contentType,
      keyPrefix: "albums",
      fileExtension: params.fileExtension,
      publicOrigin: params.publicOrigin,
    });
    return { url, thumbnailUrl: null, width: null, height: null, isVideo };
  }

  const result = await new Promise<{
    secure_url: string;
    width?: number;
    height?: number;
    resource_type?: string;
  }>((resolve, reject) => {
    const stream = cloudinary.uploader.upload_stream(
      { folder: "ourchat/albums", resource_type: "auto" },
      (error, uploaded) => {
        if (error || !uploaded) {
          reject(error ?? new Error("Cloudinary upload failed"));
          return;
        }
        resolve(uploaded as never);
      },
    );
    stream.end(params.buffer);
  });

  return {
    url: result.secure_url,
    thumbnailUrl: thumbnailFor(result.secure_url),
    width: result.width ?? null,
    height: result.height ?? null,
    isVideo: result.resource_type === "video" || isVideo,
  };
}
