import { Router } from "express";
import { Prisma } from "../generated/prisma/client";
import { requireAuth } from "../middleware/auth";
import { hashPassword, verifyPassword } from "../lib/password";
import {
  signAccessToken,
  signRefreshToken,
  verifyRefreshToken,
} from "../lib/jwt";
import { prisma } from "../prisma";
import { toPublicUser } from "../lib/serializers";
import { loginSchema, refreshSchema, registerSchema } from "../validation/auth";

export const authRouter = Router();

authRouter.post("/register", async (req, res) => {
  const parsed = registerSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const { username, email, password, displayName } = parsed.data;
  const passwordHash = await hashPassword(password);

  try {
    const user = await prisma.user.create({
      data: { username, email, passwordHash, displayName },
    });

    res.status(201).json({
      user: toPublicUser(user),
      accessToken: signAccessToken(user.id),
      refreshToken: signRefreshToken(user.id),
    });
  } catch (err) {
    if (
      err instanceof Prisma.PrismaClientKnownRequestError &&
      err.code === "P2002"
    ) {
      res.status(409).json({ error: "Username or email is already taken" });
      return;
    }
    throw err;
  }
});

authRouter.post("/login", async (req, res) => {
  const parsed = loginSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const { usernameOrEmail, password } = parsed.data;
  const user = await prisma.user.findFirst({
    where: {
      OR: [{ username: usernameOrEmail }, { email: usernameOrEmail }],
    },
  });

  if (!user || !(await verifyPassword(password, user.passwordHash))) {
    res.status(401).json({ error: "Invalid credentials" });
    return;
  }

  res.json({
    user: toPublicUser(user),
    accessToken: signAccessToken(user.id),
    refreshToken: signRefreshToken(user.id),
  });
});

authRouter.post("/refresh", async (req, res) => {
  const parsed = refreshSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  try {
    const payload = verifyRefreshToken(parsed.data.refreshToken);
    res.json({
      accessToken: signAccessToken(payload.sub),
      refreshToken: signRefreshToken(payload.sub),
    });
  } catch {
    res.status(401).json({ error: "Invalid or expired refresh token" });
  }
});

authRouter.get("/me", requireAuth, async (req, res) => {
  const user = await prisma.user.findUnique({ where: { id: req.userId } });
  if (!user) {
    res.status(404).json({ error: "User not found" });
    return;
  }
  res.json({ user: toPublicUser(user) });
});
