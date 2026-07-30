import { z } from "zod";

export const startConversationSchema = z.object({
  username: z.string().min(1),
});

export const sendMessageSchema = z.object({
  text: z.string().min(1).max(4000),
});

export const messagesQuerySchema = z.object({
  cursor: z.string().uuid().optional(),
  take: z.coerce.number().int().min(1).max(100).optional(),
});
