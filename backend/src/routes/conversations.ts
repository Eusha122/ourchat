import { Router } from "express";
import { requireAuth } from "../middleware/auth";
import { prisma } from "../prisma";
import { fetchLinkMetadata } from "../lib/linkMetadata";
import { postAuthorSelect, toPublicMessage } from "../lib/serializers";
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
          messages: { orderBy: { createdAt: "desc" }, take: 1 },
        },
      },
    },
  });

  const results = await Promise.all(
    participations.map(async (p) => {
      const other = p.conversation.participants.find(
        (pt) => pt.userId !== req.userId,
      )?.user;
      const lastMessage = p.conversation.messages[0] ?? null;
      const unreadCount = await prisma.message.count({
        where: {
          conversationId: p.conversationId,
          senderId: { not: req.userId },
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

  results.sort((a, b) => {
    const aTime = a.lastMessage?.createdAt.getTime() ?? 0;
    const bTime = b.lastMessage?.createdAt.getTime() ?? 0;
    return bTime - aTime;
  });

  res.json({ conversations: results });
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
    where: { conversationId },
    take: take + 1,
    ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    include: { sender: { select: postAuthorSelect } },
  });

  const hasMore = messages.length > take;
  if (hasMore) messages.pop();
  const nextCursor = hasMore ? messages[messages.length - 1]!.id : null;

  res.json({ messages: messages.map(toPublicMessage), nextCursor });
});

conversationsRouter.post("/:conversationId/messages", requireAuth, async (req, res) => {
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

  let linkTitle: string | null = null;
  let linkImageUrl: string | null = null;
  if (parsed.data.type === "LINK") {
    const metadata = await fetchLinkMetadata(parsed.data.linkUrl!);
    linkTitle = metadata.title;
    linkImageUrl = metadata.imageUrl;
  }

  const message = await prisma.message.create({
    data: {
      conversationId,
      senderId: req.userId!,
      type: parsed.data.type,
      text: parsed.data.text,
      linkUrl: parsed.data.linkUrl,
      linkTitle,
      linkImageUrl,
    },
    include: { sender: { select: postAuthorSelect } },
  });

  const payload = toPublicMessage(message);

  const io = getIO();
  io.to(`conversation:${conversationId}`).emit("message:new", payload);

  const otherParticipants = await prisma.conversationParticipant.findMany({
    where: { conversationId, userId: { not: req.userId } },
    select: { userId: true },
  });
  for (const { userId } of otherParticipants) {
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

  res.status(201).json({ message: payload });
});

conversationsRouter.post("/:conversationId/read", requireAuth, async (req, res) => {
  const conversationId = req.params.conversationId as string;
  const participant = await requireParticipant(conversationId, req.userId!);
  if (!participant) {
    res.status(403).json({ error: "Not a participant in this conversation" });
    return;
  }

  await prisma.conversationParticipant.update({
    where: { conversationId_userId: { conversationId, userId: req.userId! } },
    data: { lastReadAt: new Date() },
  });

  res.json({ ok: true });
});
