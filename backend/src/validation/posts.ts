import { z } from "zod";

export const createPostSchema = z.object({
  caption: z.string().max(2000).optional(),
});

export const createCommentSchema = z.object({
  text: z.string().min(1).max(500),
});

export const feedQuerySchema = z.object({
  cursor: z.string().uuid().optional(),
  take: z.coerce.number().int().min(1).max(50).optional(),
});
