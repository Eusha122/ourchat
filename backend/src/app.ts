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

// Public, deliberately small release manifest for the Android sideloaded
// application.  Publish a new APK by changing these environment variables on
// the VPS and restarting the backend; the app compares this build number to
// the `+build` number baked into its installed package.
app.get("/app-version", (_req, res) => {
  const configuredVersion = Number.parseInt(
    process.env.APP_VERSION_CODE ?? "1",
    10,
  );
  const versionCode = Number.isSafeInteger(configuredVersion)
    ? configuredVersion
    : 1;
  const downloadUrl = process.env.APP_DOWNLOAD_URL?.trim() || null;
  const releaseNotes = process.env.APP_RELEASE_NOTES?.trim() || null;

  // Do not let a CDN/browser cache an old manifest after a release is
  // published; clients should see the new build on their next app launch.
  res.set("Cache-Control", "no-store");
  res.json({ versionCode, downloadUrl, releaseNotes });
});

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
