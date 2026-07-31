import multer from "multer";

/// One field ("file"), 20MB cap, no mimetype filter — IMAGE vs FILE is
/// validated against the caller-declared `type` in the route itself, since
/// multer parses text fields and the file together for multipart requests.
export const chatAttachmentUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 20 * 1024 * 1024 },
});
