import { z } from "zod";

export const startConversationSchema = z.object({
  username: z.string().min(1),
});

export const sendMessageSchema = z
  .object({
    type: z.enum(["TEXT", "LINK", "IMAGE", "FILE"]).default("TEXT"),
    text: z.string().min(1).max(4000).optional(),
    linkUrl: z.string().url().optional(),
  })
  .refine(
    (data) => {
      if (data.type === "TEXT") return Boolean(data.text);
      if (data.type === "LINK") return Boolean(data.linkUrl);
      // IMAGE/FILE arrive as multipart uploads — the file itself is
      // validated separately once multer has parsed it.
      return true;
    },
    {
      message:
        "text is required for TEXT messages, linkUrl is required for LINK messages",
    },
  );

export const messagesQuerySchema = z.object({
  cursor: z.string().uuid().optional(),
  take: z.coerce.number().int().min(1).max(100).optional(),
});
