import type { Server as HttpServer } from "http";
import { Server } from "socket.io";
import { verifyAccessToken } from "./lib/jwt";
import { prisma } from "./prisma";

let io: Server | undefined;

type CallKind = "audio" | "video";

type ActiveCall = {
  conversationId: string;
  callerId: string;
  calleeId: string;
};

// Signaling is intentionally transient. SDP/ICE never reaches the database;
// it only passes through Socket.IO while a peer-to-peer call is being set up.
const activeCalls = new Map<string, ActiveCall>();

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

        activeCalls.set(data.callId, {
          conversationId: data.conversationId,
          callerId: userId,
          calleeId: callee.userId,
        });
        io?.to(`user:${callee.userId}`).emit("call:offer", {
          callId: data.callId,
          conversationId: data.conversationId,
          kind: data.kind,
          offer: data.offer,
          caller: caller.user,
        });
      })().catch((error) => console.error("call offer relay failed", error));
    });

    socket.on("call:answer", (payload: unknown) => {
      const data = payload as { callId?: unknown; answer?: unknown };
      if (typeof data.callId !== "string" || !isSignal(data.answer)) return;
      const call = activeCalls.get(data.callId);
      if (!call || call.calleeId !== userId) return;
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
      const data = payload as { callId?: unknown; reason?: unknown };
      if (typeof data.callId !== "string") return;
      const call = activeCalls.get(data.callId);
      if (!call || (call.callerId !== userId && call.calleeId !== userId)) return;
      activeCalls.delete(data.callId);
      const peerId = call.callerId === userId ? call.calleeId : call.callerId;
      io?.to(`user:${peerId}`).emit("call:end", {
        callId: data.callId,
        reason: typeof data.reason === "string" ? data.reason : "ended",
      });
    });
  });

  return io;
}

export function getIO(): Server {
  if (!io) throw new Error("Socket.IO not initialized");
  return io;
}
