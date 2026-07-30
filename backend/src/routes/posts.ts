import { Router } from "express";
import { requireAuth } from "../middleware/auth";
import { prisma } from "../prisma";
import { ALLOWED_IMAGE_MIME_TYPES, imageUpload } from "../lib/imageUpload";
import { postInclude } from "../lib/postQueries";
import { r2Configured, uploadToR2 } from "../lib/r2";
import { postAuthorSelect, toPublicComment, toPublicPost } from "../lib/serializers";
import {
  createCommentSchema,
  createPostSchema,
  feedQuerySchema,
} from "../validation/posts";

export const postsRouter = Router();

postsRouter.post("/", requireAuth, (req, res) => {
  if (!r2Configured) {
    res.status(503).json({ error: "Media storage is not configured yet" });
    return;
  }

  imageUpload.single("image")(req, res, async (err) => {
    if (err) {
      res.status(400).json({ error: err.message });
      return;
    }
    if (!req.file) {
      res.status(400).json({ error: "No image uploaded" });
      return;
    }

    const parsed = createPostSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: parsed.error.flatten() });
      return;
    }

    const extension = ALLOWED_IMAGE_MIME_TYPES[req.file.mimetype];
    const imageUrl = await uploadToR2({
      buffer: req.file.buffer,
      contentType: req.file.mimetype,
      keyPrefix: "posts",
      fileExtension: extension,
    });

    const created = await prisma.post.create({
      data: {
        authorId: req.userId!,
        imageUrl,
        caption: parsed.data.caption,
      },
      include: postInclude(req.userId!),
    });

    res.status(201).json({ post: toPublicPost(created) });
  });
});

postsRouter.get("/", requireAuth, async (req, res) => {
  const parsed = feedQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const take = parsed.data.take ?? 20;
  const { cursor } = parsed.data;

  const posts = await prisma.post.findMany({
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

postsRouter.get("/:postId", requireAuth, async (req, res) => {
  const postId = req.params.postId as string;
  const post = await prisma.post.findUnique({
    where: { id: postId },
    include: postInclude(req.userId!),
  });
  if (!post) {
    res.status(404).json({ error: "Post not found" });
    return;
  }
  res.json({ post: toPublicPost(post) });
});

postsRouter.post("/:postId/like", requireAuth, async (req, res) => {
  const postId = req.params.postId as string;
  const postExists = await prisma.post.findUnique({
    where: { id: postId },
    select: { id: true },
  });
  if (!postExists) {
    res.status(404).json({ error: "Post not found" });
    return;
  }

  await prisma.postLike.upsert({
    where: {
      postId_userId: { postId, userId: req.userId! },
    },
    create: { postId, userId: req.userId! },
    update: {},
  });

  const likeCount = await prisma.postLike.count({ where: { postId } });
  res.json({ likeCount, likedByMe: true });
});

postsRouter.delete("/:postId/like", requireAuth, async (req, res) => {
  const postId = req.params.postId as string;
  await prisma.postLike.deleteMany({
    where: { postId, userId: req.userId! },
  });

  const likeCount = await prisma.postLike.count({ where: { postId } });
  res.json({ likeCount, likedByMe: false });
});

postsRouter.get("/:postId/comments", requireAuth, async (req, res) => {
  const postId = req.params.postId as string;
  const parsed = feedQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const take = parsed.data.take ?? 20;
  const { cursor } = parsed.data;

  const comments = await prisma.comment.findMany({
    where: { postId },
    take: take + 1,
    ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    orderBy: [{ createdAt: "asc" }, { id: "asc" }],
    include: { author: { select: postAuthorSelect } },
  });

  const hasMore = comments.length > take;
  if (hasMore) comments.pop();
  const nextCursor = hasMore ? comments[comments.length - 1]!.id : null;

  res.json({ comments: comments.map(toPublicComment), nextCursor });
});

postsRouter.post("/:postId/comments", requireAuth, async (req, res) => {
  const postId = req.params.postId as string;
  const postExists = await prisma.post.findUnique({
    where: { id: postId },
    select: { id: true },
  });
  if (!postExists) {
    res.status(404).json({ error: "Post not found" });
    return;
  }

  const parsed = createCommentSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const comment = await prisma.comment.create({
    data: {
      postId,
      authorId: req.userId!,
      text: parsed.data.text,
    },
    include: { author: { select: postAuthorSelect } },
  });

  res.status(201).json({ comment: toPublicComment(comment) });
});
