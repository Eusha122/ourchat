import { z } from "zod";

export const updateProfileSchema = z.object({
  displayName: z.string().min(1).max(50).optional(),
  bio: z.string().max(160).optional(),
});

export const searchUsersSchema = z.object({
  q: z.string().min(1).max(50),
  take: z.coerce.number().int().min(1).max(50).optional(),
});
