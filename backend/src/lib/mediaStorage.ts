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
///
/// Videos need different treatment: they live under /video/upload/, so simply
/// injecting an image transform yields another *video* URL, which an image
/// widget cannot render. Swapping the extension for .jpg with `so_0` asks
/// Cloudinary for a still poster frame instead.
function thumbnailFor(url: string, isVideo: boolean): string | null {
  const marker = "/upload/";
  const at = url.indexOf(marker);
  if (at === -1) return null;

  const head = url.slice(0, at + marker.length);
  const tail = url.slice(at + marker.length);

  if (isVideo) {
    const stillTail = tail.replace(/\.[^./]+$/, ".jpg");
    return `${head}so_0,c_fill,w_500,h_500,q_auto/${stillTail}`;
  }
  return `${head}c_fill,w_500,h_500,q_auto,f_auto/${tail}`;
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

  const storedIsVideo = result.resource_type === "video" || isVideo;
  return {
    url: result.secure_url,
    thumbnailUrl: thumbnailFor(result.secure_url, storedIsVideo),
    width: result.width ?? null,
    height: result.height ?? null,
    isVideo: storedIsVideo,
  };
}

/// Best-effort cleanup: deleting the row is what actually removes the item
/// from the album, so a Cloudinary failure here is logged and swallowed
/// rather than blocking the delete the user is waiting on.
export async function deleteAlbumMedia(url: string, isVideo: boolean) {
  if (!cloudinaryConfigured) return;
  const match = /\/upload\/(?:v\d+\/)?(.+?)\.[^./]+$/.exec(url);
  if (!match) return;
  try {
    await cloudinary.uploader.destroy(match[1]!, {
      resource_type: isVideo ? "video" : "image",
    });
  } catch (error) {
    console.error("Cloudinary delete failed", error);
  }
}
