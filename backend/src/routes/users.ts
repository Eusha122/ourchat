import { Router } from "express";
import multer from "multer";
import { requireAuth } from "../middleware/auth";
import { prisma } from "../prisma";
import { r2Configured, uploadToR2 } from "../lib/r2";
import { toPublicUser } from "../lib/serializers";
import { updateProfileSchema } from "../validation/users";

export const usersRouter = Router();

const ALLOWED_MIME_TYPES: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (!ALLOWED_MIME_TYPES[file.mimetype]) {
      cb(new Error("Only JPEG, PNG, or WebP images are allowed"));
      return;
    }
    cb(null, true);
  },
});

usersRouter.patch("/me", requireAuth, async (req, res) => {
  const parsed = updateProfileSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const user = await prisma.user.update({
    where: { id: req.userId },
    data: parsed.data,
  });

  res.json({ user: toPublicUser(user) });
});

usersRouter.post("/me/avatar", requireAuth, (req, res) => {
  if (!r2Configured) {
    res.status(503).json({ error: "Media storage is not configured yet" });
    return;
  }

  upload.single("avatar")(req, res, async (err) => {
    if (err) {
      res.status(400).json({ error: err.message });
      return;
    }
    if (!req.file) {
      res.status(400).json({ error: "No file uploaded" });
      return;
    }

    const extension = ALLOWED_MIME_TYPES[req.file.mimetype];
    const avatarUrl = await uploadToR2({
      buffer: req.file.buffer,
      contentType: req.file.mimetype,
      keyPrefix: "avatars",
      fileExtension: extension,
    });

    const user = await prisma.user.update({
      where: { id: req.userId },
      data: { avatarUrl },
    });

    res.json({ user: toPublicUser(user) });
  });
});
