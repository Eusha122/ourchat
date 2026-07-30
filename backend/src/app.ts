import express, { type NextFunction, type Request, type Response } from "express";
import cors from "cors";
import { prisma } from "./prisma";
import { authRouter } from "./routes/auth";
import { usersRouter } from "./routes/users";

export const app = express();

app.use(cors());
app.use(express.json());

app.use("/auth", authRouter);
app.use("/users", usersRouter);

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
