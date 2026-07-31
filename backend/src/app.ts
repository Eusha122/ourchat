import path from "path";
import express, { type NextFunction, type Request, type Response } from "express";
import cors from "cors";
import { prisma } from "./prisma";
import { authRouter } from "./routes/auth";
import { usersRouter } from "./routes/users";
import { postsRouter } from "./routes/posts";
import { conversationsRouter } from "./routes/conversations";

export const app = express();

app.use(cors());
app.use(express.json());

// Serves locally-stored chat attachments when R2 isn't configured (see
// lib/storage.ts) — a no-op path is still hit but empty if R2 is in use.
app.use("/uploads", express.static(path.join(process.cwd(), "uploads")));

app.use("/auth", authRouter);
app.use("/users", usersRouter);
app.use("/posts", postsRouter);
app.use("/conversations", conversationsRouter);

app.get("/health", async (_req, res) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ status: "ok", db: "connected" });
  } catch (err) {
    res.status(503).json({ status: "error", db: "unreachable" });
  }
});

app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
  console.error(err);
  res.status(500).json({ error: "Internal server error" });
});
