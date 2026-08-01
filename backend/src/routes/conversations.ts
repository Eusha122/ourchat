import { Router, type Request, type Response } from "express";
import { requireAuth } from "../middleware/auth";
import { prisma } from "../prisma";
import { chatAttachmentUpload } from "../lib/attachmentUpload";
import { fetchLinkMetadata } from "../lib/linkMetadata";
import { sendMessagePush } from "../lib/push";
import { postAuthorSelect, toPublicMessage } from "../lib/serializers";
import { uploadFile } from "../lib/storage";
import { getIO } from "../socket";
import {
  messagesQuerySchema,
  sendMessageSchema,
  startConversationSchema,
} from "../validation/conversations";

export const conversationsRouter = Router();

async function requireParticipant(conversationId: string, userId: string) {
  return prisma.conversationParticipant.findUnique({
    where: { conversationId_userId: { conversationId, userId } },
  });
}

const messageInclude = {
  sender: { select: postAuthorSelect },
  reactions: { select: { userId: true, emoji: true } },
} as const;

function messagePreviewText(message: {
  type: string;
  text: string | null;
}): string {
  if (message.text) return message.text;
  switch (message.type) {
    case "IMAGE":
      return "Sent a photo";
    case "FILE":
      return "Sent a file";
    case "LINK":
      return "Sent a link";
    default:
      return "Sent a message";
  }
}

async function emitMessageUpdated(
  conversationId: string,
  message: Parameters<typeof toPublicMessage>[0],
) {
  const participants = await prisma.conversationParticipant.findMany({
    where: { conversationId },
    select: { userId: true },
  });
  getIO()
    .to(`conversation:${conversationId}`)
    .to(participants.map(({ userId }) => `user:${userId}`))
    .emit("message:updated", toPublicMessage(message));
}

conversationsRouter.post("/", requireAuth, async (req, res) => {
  const parsed = startConversationSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const target = await prisma.user.findUnique({
    where: { username: parsed.data.username },
  });
  if (!target) {
    res.status(404).json({ error: "User not found" });
    return;
  }
  if (target.id === req.userId) {
    res.status(400).json({ error: "You can't start a conversation with yourself" });
    return;
  }

  const myConversationIds = (
    await prisma.conversationParticipant.findMany({
      where: { userId: req.userId },
      select: { conversationId: true },
    })
  ).map((p) => p.conversationId);

  const existing = await prisma.conversation.findFirst({
    where: {
      id: { in: myConversationIds },
      participants: { some: { userId: target.id } },
    },
  });

  const conversation =
    existing ??
    (await prisma.conversation.create({
      data: {
        participants: {
          create: [{ userId: req.userId! }, { userId: target.id }],
        },
      },
    }));

  res.status(existing ? 200 : 201).json({
    conversation: { id: conversation.id, otherParticipant: postAuthorFields(target) },
  });
});

function postAuthorFields(user: {
  id: string;
  username: string;
  displayName: string | null;
  avatarUrl: string | null;
}) {
  return {
    id: user.id,
    username: user.username,
    displayName: user.displayName,
    avatarUrl: user.avatarUrl,
  };
}

conversationsRouter.get("/", requireAuth, async (req, res) => {
  const participations = await prisma.conversationParticipant.findMany({
    where: { userId: req.userId },
    include: {
      conversation: {
        include: {
          participants: { include: { user: { select: postAuthorSelect } } },
          messages: {
            where: { hiddenBy: { none: { userId: req.userId } } },
            orderBy: { createdAt: "desc" },
            take: 1,
          },
        },
      },
    },
  });

  const maybeResults = await Promise.all(
    participations.map(async (p) => {
      const other = p.conversation.participants.find(
        (pt) => pt.userId !== req.userId,
      )?.user;
      // A conversation whose peer no longer exists (deleted account cascades
      // away their participant row) has nothing to render. Drop it here
      // rather than emitting an entry with no `otherParticipant` — clients
      // treat that field as required, so a single malformed row would
      // otherwise break parsing of the whole list.
      if (!other) return null;

      const lastMessage = p.conversation.messages[0] ?? null;
      const unreadCount = await prisma.message.count({
        where: {
          conversationId: p.conversationId,
          senderId: { not: req.userId },
          unsentAt: null,
          hiddenBy: { none: { userId: req.userId } },
          ...(p.lastReadAt ? { createdAt: { gt: p.lastReadAt } } : {}),
        },
      });

      return {
        id: p.conversationId,
        otherParticipant: other,
        lastMessage: lastMessage
          ? {
              id: lastMessage.id,
              text: lastMessage.text,
              senderId: lastMessage.senderId,
              createdAt: lastMessage.createdAt,
            }
          : null,
        unreadCount,
      };
    }),
  );

  const results = maybeResults.filter((entry) => entry !== null);

  results.sort((a, b) => {
    const aTime = a.lastMessage?.createdAt.getTime() ?? 0;
    const bTime = b.lastMessage?.createdAt.getTime() ?? 0;
    return bTime - aTime;
  });

  res.json({ conversations: results });
});

conversationsRouter.get("/:conversationId", requireAuth, async (req, res) => {
  const conversationId = req.params.conversationId as string;
  const participant = await prisma.conversationParticipant.findUnique({
    where: { conversationId_userId: { conversationId, userId: req.userId! } },
    include: {
      conversation: {
        include: {
          participants: { include: { user: { select: postAuthorSelect } } },
          messages: {
            where: { hiddenBy: { none: { userId: req.userId } } },
            orderBy: { createdAt: "desc" },
            take: 1,
          },
        },
      },
    },
  });

  if (!participant) {
    res.status(404).json({ error: "Conversation not found" });
    return;
  }

  const otherParticipantRow = participant.conversation.participants.find(
    (pt) => pt.userId !== req.userId,
  );
  const other = otherParticipantRow?.user;
  if (!other) {
    res.status(404).json({ error: "Conversation participant not found" });
    return;
  }

  const lastMessage = participant.conversation.messages[0] ?? null;
  const unreadCount = await prisma.message.count({
    where: {
      conversationId,
      senderId: { not: req.userId },
      unsentAt: null,
      hiddenBy: { none: { userId: req.userId } },
      ...(participant.lastReadAt
        ? { createdAt: { gt: participant.lastReadAt } }
        : {}),
    },
  });

  res.json({
    conversation: {
      id: conversationId,
      otherParticipant: other,
      lastMessage: lastMessage
        ? {
            id: lastMessage.id,
            text: lastMessage.text,
            senderId: lastMessage.senderId,
            createdAt: lastMessage.createdAt,
          }
        : null,
      unreadCount,
      // Drives the "Seen" receipt: any of my messages sent at or before this
      // instant has been read by them. Null until they've ever opened it.
      otherLastReadAt: otherParticipantRow?.lastReadAt ?? null,
    },
  });
});

conversationsRouter.get("/:conversationId/messages", requireAuth, async (req, res) => {
  const conversationId = req.params.conversationId as string;
  const participant = await requireParticipant(conversationId, req.userId!);
  if (!participant) {
    res.status(403).json({ error: "Not a participant in this conversation" });
    return;
  }

  const parsed = messagesQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const take = parsed.data.take ?? 30;
  const { cursor } = parsed.data;

  const messages = await prisma.message.findMany({
    where: {
      conversationId,
      hiddenBy: { none: { userId: req.userId } },
    },
    take: take + 1,
    ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    include: messageInclude,
  });

  const hasMore = messages.length > take;
  if (hasMore) messages.pop();
  const nextCursor = hasMore ? messages[messages.length - 1]!.id : null;

  res.json({ messages: messages.map(toPublicMessage), nextCursor });
});

async function handleSendMessage(req: Request, res: Response) {
  const conversationId = req.params.conversationId as string;
  const participant = await requireParticipant(conversationId, req.userId!);
  if (!participant) {
    res.status(403).json({ error: "Not a participant in this conversation" });
    return;
  }

  const parsed = sendMessageSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  let linkUrl: string | null = parsed.data.linkUrl ?? null;
  let linkTitle: string | null = null;
  let linkImageUrl: string | null = null;
  let fileSize: number | null = null;

  if (parsed.data.type === "LINK") {
    const metadata = await fetchLinkMetadata(parsed.data.linkUrl!);
    linkTitle = metadata.title;
    linkImageUrl = metadata.imageUrl;
  } else if (parsed.data.type === "IMAGE" || parsed.data.type === "FILE") {
    if (!req.file) {
      res.status(400).json({ error: "No file uploaded" });
      return;
    }
    const originalName = req.file.originalname || "file";
    const dotIndex = originalName.lastIndexOf(".");
    const extension = dotIndex >= 0 ? originalName.slice(dotIndex + 1) : "bin";
    const publicOrigin = `${req.protocol}://${req.get("host")}`;
    const uploadedUrl = await uploadFile({
      buffer: req.file.buffer,
      contentType: req.file.mimetype,
      keyPrefix: "chat",
      fileExtension: extension,
      publicOrigin,
    });

    if (parsed.data.type === "IMAGE") {
      linkImageUrl = uploadedUrl;
    } else {
      linkUrl = uploadedUrl;
      linkTitle = originalName;
      fileSize = req.file.size;
    }
  }

  const message = await prisma.message.create({
    data: {
      conversationId,
      senderId: req.userId!,
      type: parsed.data.type,
      text: parsed.data.text,
      linkUrl,
      linkTitle,
      linkImageUrl,
      fileSize,
    },
    include: messageInclude,
  });

  const payload = toPublicMessage(message);

  const participants = await prisma.conversationParticipant.findMany({
    where: { conversationId },
    select: { userId: true },
  });

  const io = getIO();
  // Deliver to anyone with this conversation open (the `conversation:` room)
  // AND to every other participant's personal room, so the message still
  // arrives even if they haven't opened this conversation on their device.
  // Chaining `.to()` targets a union of rooms and Socket.IO dedupes per
  // socket, so a participant who happens to be in both never gets it twice.
  io.to(`conversation:${conversationId}`)
    .to(participants.map(({ userId }) => `user:${userId}`))
    .emit("message:new", payload);

  // Every participant — including the sender — needs this to keep their own
  // chat list in sync; ChatsScreen only refreshes an entry (or a brand new
  // conversation) in response to this event, not `message:new`.
  for (const { userId } of participants) {
    io.to(`user:${userId}`).emit("conversation:updated", {
      conversationId,
      lastMessage: {
        id: message.id,
        text: message.text,
        senderId: message.senderId,
        createdAt: message.createdAt,
      },
    });
  }

  // Push notifications are additive to the socket-based delivery above: the
  // socket path only reaches a device with an active connection (app open,
  // foreground or backgrounded), so this is what gets a message through when
  // the app has been fully killed. Fire-and-forget — a push failure must
  // never fail the send itself.
  const senderName = message.sender.displayName || `@${message.sender.username}`;
  const preview = messagePreviewText(message);
  for (const { userId } of participants) {
    if (userId === req.userId) continue;
    sendMessagePush(userId, {
      title: senderName,
      body: preview,
      conversationId,
    }).catch((error) => console.error("push send failed", error));
  }

  res.status(201).json({ message: payload });
}

async function findMessageForParticipant(
  conversationId: string,
  messageId: string,
  userId: string,
) {
  const participant = await requireParticipant(conversationId, userId);
  if (!participant) return null;
  return prisma.message.findFirst({
    where: { id: messageId, conversationId },
    include: messageInclude,
  });
}

conversationsRouter.post(
  "/:conversationId/messages/:messageId/hide",
  requireAuth,
  async (req, res) => {
    const conversationId = req.params.conversationId as string;
    const messageId = req.params.messageId as string;
    const message = await findMessageForParticipant(
      conversationId,
      messageId,
      req.userId!,
    );
    if (!message) {
      res.status(404).json({ error: "Message not found" });
      return;
    }

    await prisma.messageHide.upsert({
      where: { messageId_userId: { messageId, userId: req.userId! } },
      create: { messageId, userId: req.userId! },
      update: {},
    });
    getIO().to(`user:${req.userId}`).emit("message:removed", {
      conversationId,
      messageId,
    });
    res.json({ ok: true });
  },
);

conversationsRouter.post(
  "/:conversationId/messages/:messageId/unsend",
  requireAuth,
  async (req, res) => {
    const conversationId = req.params.conversationId as string;
    const messageId = req.params.messageId as string;
    const message = await findMessageForParticipant(
      conversationId,
      messageId,
      req.userId!,
    );
    if (!message) {
      res.status(404).json({ error: "Message not found" });
      return;
    }
    if (message.senderId !== req.userId) {
      res.status(403).json({ error: "Only the sender can unsend a message" });
      return;
    }

    const updated = await prisma.message.update({
      where: { id: messageId },
      data: {
        text: null,
        linkUrl: null,
        linkTitle: null,
        linkImageUrl: null,
        fileSize: null,
        unsentAt: new Date(),
      },
      include: messageInclude,
    });
    await emitMessageUpdated(conversationId, updated);
    res.json({ message: toPublicMessage(updated) });
  },
);

conversationsRouter.post(
  "/:conversationId/messages/:messageId/reactions",
  requireAuth,
  async (req, res) => {
    const conversationId = req.params.conversationId as string;
    const messageId = req.params.messageId as string;
    const emoji = typeof req.body?.emoji === "string" ? req.body.emoji.trim() : "";
    if (!emoji || [...emoji].length > 8) {
      res.status(400).json({ error: "Choose a valid reaction" });
      return;
    }
    const message = await findMessageForParticipant(
      conversationId,
      messageId,
      req.userId!,
    );
    if (!message || message.unsentAt) {
      res.status(404).json({ error: "Message not found" });
      return;
    }

    const mine = message.reactions.find((reaction) => reaction.userId === req.userId);
    if (mine?.emoji === emoji) {
      await prisma.messageReaction.delete({
        where: { messageId_userId: { messageId, userId: req.userId! } },
      });
    } else {
      await prisma.messageReaction.upsert({
        where: { messageId_userId: { messageId, userId: req.userId! } },
        create: { messageId, userId: req.userId!, emoji },
        update: { emoji },
      });
    }
    const updated = await prisma.message.findUniqueOrThrow({
      where: { id: messageId },
      include: messageInclude,
    });
    await emitMessageUpdated(conversationId, updated);
    res.json({ message: toPublicMessage(updated) });
  },
);

conversationsRouter.post(
  "/:conversationId/messages",
  requireAuth,
  (req, res) => {
    // IMAGE/FILE messages arrive as multipart form-data (the file plus a
    // `type` field); TEXT/LINK stay plain JSON. Only run multer for the
    // former so the JSON path is untouched.
    if (req.is("multipart/form-data")) {
      chatAttachmentUpload.single("file")(req, res, (err) => {
        if (err) {
          res.status(400).json({ error: err.message });
          return;
        }
        handleSendMessage(req, res).catch((error) => {
          console.error(error);
          res.status(500).json({ error: "Internal server error" });
        });
      });
      return;
    }

    handleSendMessage(req, res).catch((error) => {
      console.error(error);
      res.status(500).json({ error: "Internal server error" });
    });
  },
);

conversationsRouter.post("/:conversationId/read", requireAuth, async (req, res) => {
  const conversationId = req.params.conversationId as string;
  const participant = await requireParticipant(conversationId, req.userId!);
  if (!participant) {
    res.status(403).json({ error: "Not a participant in this conversation" });
    return;
  }

  const readAt = new Date();
  await prisma.conversationParticipant.update({
    where: { conversationId_userId: { conversationId, userId: req.userId! } },
    data: { lastReadAt: readAt },
  });

  // Tell the other side so their "Seen" receipt updates live, the same way
  // opening a thread flips the receipt on Instagram/Messenger.
  const participants = await prisma.conversationParticipant.findMany({
    where: { conversationId, userId: { not: req.userId } },
    select: { userId: true },
  });
  const io = getIO();
  for (const { userId } of participants) {
    io.to(`user:${userId}`).emit("conversation:read", {
      conversationId,
      userId: req.userId,
      readAt: readAt.toISOString(),
    });
  }

  res.json({ ok: true });
});
