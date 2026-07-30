import { Router } from "express";
import { requireAuth } from "../middleware/auth";
import { prisma } from "../prisma";
import { ALLOWED_IMAGE_MIME_TYPES, imageUpload } from "../lib/imageUpload";
import { postInclude } from "../lib/postQueries";
import { r2Configured, uploadToR2 } from "../lib/r2";
import {
  postAuthorSelect,
  toPublicPost,
  toPublicProfile,
  toPublicUser,
} from "../lib/serializers";
import { feedQuerySchema } from "../validation/posts";
import { searchUsersSchema, updateProfileSchema } from "../validation/users";

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

// NOTE: /search must be registered before /:username so it isn't shadowed.
usersRouter.get("/search", requireAuth, async (req, res) => {
  const parsed = searchUsersSchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const users = await prisma.user.findMany({
    where: { username: { contains: parsed.data.q, mode: "insensitive" } },
    select: postAuthorSelect,
    orderBy: { username: "asc" },
    take: parsed.data.take ?? 20,
  });

  res.json({ users });
});

usersRouter.get("/:username", requireAuth, async (req, res) => {
  const username = req.params.username as string;
  const user = await prisma.user.findUnique({ where: { username } });
  if (!user) {
    res.status(404).json({ error: "User not found" });
    return;
  }
  res.json({ user: toPublicProfile(user) });
});

usersRouter.get("/:username/posts", requireAuth, async (req, res) => {
  const username = req.params.username as string;
  const parsed = feedQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const user = await prisma.user.findUnique({
    where: { username },
    select: { id: true },
  });
  if (!user) {
    res.status(404).json({ error: "User not found" });
    return;
  }

  const take = parsed.data.take ?? 20;
  const { cursor } = parsed.data;

  const posts = await prisma.post.findMany({
    where: { authorId: user.id },
    take: take + 1,
    ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    include: postInclude(req.userId!),
  });

  const hasMore = posts.length > take;
  if (hasMore) posts.pop();
  const nextCursor = hasMore ? posts[posts.length - 1]!.id : null;

  res.json({ posts: posts.map(toPublicPost), nextCursor });
});
