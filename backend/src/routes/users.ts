import { Router } from "express";
import { requireAuth } from "../middleware/auth";
import { prisma } from "../prisma";
import { ALLOWED_IMAGE_MIME_TYPES, imageUpload } from "../lib/imageUpload";
import { r2Configured, uploadToR2 } from "../lib/r2";
import { toPublicUser } from "../lib/serializers";
import { updateProfileSchema } from "../validation/users";

export const usersRouter = Router();

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

  imageUpload.single("avatar")(req, res, async (err) => {
    if (err) {
      res.status(400).json({ error: err.message });
      return;
    }
    if (!req.file) {
      res.status(400).json({ error: "No file uploaded" });
      return;
    }

    const extension = ALLOWED_IMAGE_MIME_TYPES[req.file.mimetype];
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
