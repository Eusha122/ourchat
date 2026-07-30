import type { Server as HttpServer } from "http";
import { Server } from "socket.io";
import { verifyAccessToken } from "./lib/jwt";

let io: Server | undefined;

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
  });

  return io;
}

export function getIO(): Server {
  if (!io) throw new Error("Socket.IO not initialized");
  return io;
}
