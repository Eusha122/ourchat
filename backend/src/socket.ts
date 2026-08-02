import type { Server as HttpServer } from "http";
import { Server } from "socket.io";
import { verifyAccessToken } from "./lib/jwt";
import { prisma } from "./prisma";
import {
  messageReplySelect,
  postAuthorSelect,
  toPublicMessage,
} from "./lib/serializers";
import { sendCallPush } from "./lib/push";

let io: Server | undefined;

type CallKind = "audio" | "video";

type ActiveCall = {
  conversationId: string;
  callerId: string;
  calleeId: string;
  messageId: string;
  kind: CallKind;
  startedAt: Date;
  acceptedAt?: Date;
  // Kept only so a callee who wasn't connected when the call started (app
  // closed) can be resent the same offer once their socket reconnects —
  // see the `connection` handler below. Never persisted to the database.
  offer: { type: string; sdp: string };
  caller: {
    id: string;
    username: string;
    displayName: string | null;
    avatarUrl: string | null;
  };
};

// Signaling is intentionally transient. SDP/ICE never reaches the database;
// it only passes through Socket.IO while a peer-to-peer call is being set up.
const activeCalls = new Map<string, ActiveCall>();

// Presence is in-memory only (not persisted) — counts active sockets per user
// so a device with multiple tabs/reconnects doesn't flicker offline early.
const onlineCounts = new Map<string, number>();
// Keep the person visibly online for three minutes after their last socket
// disconnect. This absorbs app switching/network changes and matches the
// familiar Instagram-style online grace period.
const offlineTimers = new Map<string, ReturnType<typeof setTimeout>>();
const OFFLINE_GRACE_MS = 3 * 60 * 1000;

async function getConversationPartnerIds(userId: string): Promise<string[]> {
  const own = await prisma.conversationParticipant.findMany({
    where: { userId },
    select: { conversationId: true },
  });
  const conversationIds = own.map((p) => p.conversationId);
  if (conversationIds.length === 0) return [];
  const others = await prisma.conversationParticipant.findMany({
    where: { conversationId: { in: conversationIds }, userId: { not: userId } },
    select: { userId: true },
  });
  return [...new Set(others.map((o) => o.userId))];
}

async function broadcastPresence(
  userId: string,
  online: boolean,
  lastActiveAt: Date,
) {
  const partnerIds = await getConversationPartnerIds(userId);
  for (const partnerId of partnerIds) {
    io?.to(`user:${partnerId}`).emit("presence:update", {
      userId,
      online,
      lastActiveAt: lastActiveAt.toISOString(),
    });
  }
}
const callMessageInclude = {
  sender: { select: postAuthorSelect },
  reactions: { select: { userId: true, emoji: true } },
  replyTo: { select: messageReplySelect },
} as const;

async function emitCallMessage(
  conversationId: string,
  message: Parameters<typeof toPublicMessage>[0],
  event: "message:new" | "message:updated",
) {
  const participants = await prisma.conversationParticipant.findMany({
    where: { conversationId },
    select: { userId: true },
  });
  io
    ?.to(`conversation:${conversationId}`)
    .to(participants.map(({ userId }) => `user:${userId}`))
    .emit(event, toPublicMessage(message));
}

async function concludeCall(
  callId: string,
  reason: string,
  notifyUserIds: string[],
) {
  const call = activeCalls.get(callId);
  if (!call) return;
  activeCalls.delete(callId);

  const acceptedAt = call.acceptedAt;
  const duration = acceptedAt != null
    ? Math.max(0, Math.floor((Date.now() - acceptedAt.getTime()) / 1000))
    : null;
  const status = acceptedAt != null
    ? "COMPLETED"
    : reason === "declined"
      ? "DECLINED"
      : "MISSED";
  const label = `${call.kind} call`;
  const summary = status === "COMPLETED"
    ? `${label} ended${duration != null ? ` • ${duration}s` : ""}`
    : status === "DECLINED"
      ? `${label} declined`
      : `${label} missed`;
  const callMessage = await prisma.message.update({
    where: { id: call.messageId },
    data: {
      callStatus: status,
      callDurationSeconds: duration,
      text: summary,
    },
    include: callMessageInclude,
  });
  await emitCallMessage(call.conversationId, callMessage, "message:updated");
  for (const userId of notifyUserIds) {
    io?.to(`user:${userId}`).emit("call:end", { callId, reason });
  }
}

function isCallKind(value: unknown): value is CallKind {
  return value === "audio" || value === "video";
}

function isSignal(value: unknown): value is { type: string; sdp: string } {
  return Boolean(
    value &&
      typeof value === "object" &&
      typeof (value as { type?: unknown }).type === "string" &&
      typeof (value as { sdp?: unknown }).sdp === "string",
  );
}

function isCandidate(value: unknown): value is {
  candidate: string;
  sdpMid: string | null;
  sdpMLineIndex: number | null;
} {
  return Boolean(
    value &&
      typeof value === "object" &&
      typeof (value as { candidate?: unknown }).candidate === "string",
  );
}

export function initSocket(httpServer: HttpServer): Server {
  io = new Server(httpServer, { cors: { origin: "*" } });

  io.use((socket, next) => {
    const token = socket.handshake.auth?.token as string | undefined;
    if (!token) {
      next(new Error("Missing auth token"));
      return;
    }
    try {
      const payload = verifyAccessToken(token);
      socket.data.userId = payload.sub;
      next();
    } catch {
      next(new Error("Invalid or expired token"));
    }
  });

  io.on("connection", (socket) => {
    const userId = socket.data.userId as string;
    socket.join(`user:${userId}`);

    const pendingOffline = offlineTimers.get(userId);
    if (pendingOffline) {
      clearTimeout(pendingOffline);
      offlineTimers.delete(userId);
    }
    const previousCount = onlineCounts.get(userId) ?? 0;
    onlineCounts.set(userId, previousCount + 1);
    if (previousCount === 0) {
      const now = new Date();
      void prisma.user
        .update({ where: { id: userId }, data: { lastActiveAt: now } })
        .catch((error) => console.error("presence timestamp failed", error));
      void broadcastPresence(userId, true, now).catch((error) =>
        console.error("presence broadcast failed", error),
      );
    }

    // Lets a freshly opened conversation screen ask for the other person's
    // current status instead of waiting for their next state change.
    socket.on("presence:query", (targetUserId: unknown) => {
      if (typeof targetUserId !== "string") return;
      void prisma.user
        .findUnique({
          where: { id: targetUserId },
          select: { lastActiveAt: true },
        })
        .then((target) => {
          if (!target) return;
          socket.emit("presence:update", {
            userId: targetUserId,
            online:
              (onlineCounts.get(targetUserId) ?? 0) > 0 ||
              offlineTimers.has(targetUserId),
            lastActiveAt: target.lastActiveAt.toISOString(),
          });
        })
        .catch((error) => console.error("presence query failed", error));
    });

    // Replays any call this user is being rung for right now — covers a
    // callee whose app was fully closed when the offer first went out (they
    // only had the push alert, no live socket to receive the real offer on)
    // and is only just reconnecting, e.g. by tapping that notification.
    for (const [callId, call] of activeCalls) {
      if (call.calleeId !== userId || call.acceptedAt != null) continue;
      socket.emit("call:offer", {
        callId,
        conversationId: call.conversationId,
        kind: call.kind,
        offer: call.offer,
        caller: call.caller,
      });
    }

    socket.on("disconnect", () => {
      const count = onlineCounts.get(userId) ?? 0;
      if (count <= 1) {
        onlineCounts.delete(userId);
        const timer = setTimeout(() => {
          offlineTimers.delete(userId);
          const lastActiveAt = new Date();
          void prisma.user
            .update({ where: { id: userId }, data: { lastActiveAt } })
            .then(() => broadcastPresence(userId, false, lastActiveAt))
            .catch((error) => console.error("presence broadcast failed", error));
        }, OFFLINE_GRACE_MS);
        offlineTimers.set(userId, timer);
      } else {
        onlineCounts.set(userId, count - 1);
      }
    });

    socket.on("conversation:join", (conversationId: string) => {
      socket.join(`conversation:${conversationId}`);
    });

    socket.on("conversation:leave", (conversationId: string) => {
      socket.leave(`conversation:${conversationId}`);
    });

    socket.on(
      "typing",
      (payload: { conversationId: string; isTyping: boolean }) => {
        socket
          .to(`conversation:${payload.conversationId}`)
          .emit("typing", { userId, isTyping: payload.isTyping });
      },
    );

    socket.on("call:offer", (payload: unknown) => {
      void (async () => {
        const data = payload as {
          callId?: unknown;
          conversationId?: unknown;
          kind?: unknown;
          offer?: unknown;
        };
        if (
          typeof data.callId !== "string" ||
          typeof data.conversationId !== "string" ||
          !isCallKind(data.kind) ||
          !isSignal(data.offer)
        ) {
          return;
        }
        const callId = data.callId;
        const participants = await prisma.conversationParticipant.findMany({
          where: { conversationId: data.conversationId },
          include: {
            user: {
              select: {
                id: true,
                username: true,
                displayName: true,
                avatarUrl: true,
              },
            },
          },
        });
        const caller = participants.find((participant) => participant.userId === userId);
        const callee = participants.find((participant) => participant.userId !== userId);
        // Our current product is one-to-one chat. Never let an arbitrary
        // socket signal a user it does not share a conversation with.
        if (!caller || !callee || participants.length !== 2) return;

        const callMessage = await prisma.message.create({
          data: {
            conversationId: data.conversationId,
            senderId: userId,
            type: "CALL",
            text: `Started a ${data.kind} call`,
            callKind: data.kind === "video" ? "VIDEO" : "AUDIO",
            callStatus: "STARTED",
          },
          include: callMessageInclude,
        });
        activeCalls.set(callId, {
          conversationId: data.conversationId,
          callerId: userId,
          calleeId: callee.userId,
          messageId: callMessage.id,
          kind: data.kind,
          startedAt: new Date(),
          offer: data.offer,
          caller: caller.user,
        });
        setTimeout(() => {
          const active = activeCalls.get(callId);
          if (!active || active.acceptedAt != null) return;
          void concludeCall(callId, "timeout", [
            active.callerId,
            active.calleeId,
          ]).catch((error) => console.error("call timeout failed", error));
        }, 35_000);
        await emitCallMessage(data.conversationId, callMessage, "message:new");
        // Acknowledge only after the conversation membership check completed.
        // The caller buffers its first ICE candidates until this point, which
        // avoids dropping them while this async database lookup is in flight.
        socket.emit("call:ready", { callId });
        io?.to(`user:${callee.userId}`).emit("call:offer", {
          callId,
          conversationId: data.conversationId,
          kind: data.kind,
          offer: data.offer,
          caller: caller.user,
        });
        // Reaches the callee even if they have no socket connected at all
        // right now (app closed); the actual offer above is replayed to them
        // over the socket once they reconnect, within the 35s call window —
        // see the `connection` handler's activeCalls resync. Skipped if
        // they've muted calls from this conversation.
        if (!callee.mutedCalls) {
          sendCallPush(callee.userId, {
            callId,
            conversationId: data.conversationId,
            callerName: caller.user.displayName || `@${caller.user.username}`,
            isVideo: data.kind === "video",
          }).catch((error) => console.error("call push send failed", error));
        }
      })().catch((error) => console.error("call offer relay failed", error));
    });

    socket.on("call:answer", (payload: unknown) => {
      const data = payload as { callId?: unknown; answer?: unknown };
      if (typeof data.callId !== "string" || !isSignal(data.answer)) return;
      const call = activeCalls.get(data.callId);
      if (!call || call.calleeId !== userId) return;
      call.acceptedAt = new Date();
      io?.to(`user:${call.callerId}`).emit("call:answer", {
        callId: data.callId,
        answer: data.answer,
      });
    });

    socket.on("call:ice", (payload: unknown) => {
      const data = payload as { callId?: unknown; candidate?: unknown };
      if (typeof data.callId !== "string" || !isCandidate(data.candidate)) return;
      const call = activeCalls.get(data.callId);
      if (!call || (call.callerId !== userId && call.calleeId !== userId)) return;
      const peerId = call.callerId === userId ? call.calleeId : call.callerId;
      io?.to(`user:${peerId}`).emit("call:ice", {
        callId: data.callId,
        candidate: data.candidate,
      });
    });

    socket.on("call:end", (payload: unknown) => {
      void (async () => {
      const data = payload as { callId?: unknown; reason?: unknown };
      if (typeof data.callId !== "string") return;
      const call = activeCalls.get(data.callId);
      if (!call || (call.callerId !== userId && call.calleeId !== userId)) return;
      activeCalls.delete(data.callId);
      const peerId = call.callerId === userId ? call.calleeId : call.callerId;
      const reason = typeof data.reason === "string" ? data.reason : "ended";
      const acceptedAt = call.acceptedAt;
      const wasConnected = acceptedAt != null;
      const duration = acceptedAt != null
        ? Math.max(0, Math.floor((Date.now() - acceptedAt.getTime()) / 1000))
        : null;
      const status = wasConnected
        ? "COMPLETED"
        : reason === "declined"
          ? "DECLINED"
          : "MISSED";
      const label = `${call.kind} call`;
      const summary = status === "COMPLETED"
        ? `${label} ended${duration != null ? ` • ${duration}s` : ""}`
        : status === "DECLINED"
          ? `${label} declined`
          : `${label} missed`;
      const callMessage = await prisma.message.update({
        where: { id: call.messageId },
        data: {
          callStatus: status,
          callDurationSeconds: duration,
          text: summary,
        },
        include: callMessageInclude,
      });
      await emitCallMessage(call.conversationId, callMessage, "message:updated");
      io?.to(`user:${peerId}`).emit("call:end", {
        callId: data.callId,
        reason,
      });
      })().catch((error) => console.error("call end relay failed", error));
    });
  });

  return io;
}

export function getIO(): Server {
  if (!io) throw new Error("Socket.IO not initialized");
  return io;
}
