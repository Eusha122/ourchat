import path from "path";
import { cert, initializeApp, type App } from "firebase-admin/app";
import { getMessaging } from "firebase-admin/messaging";
import { prisma } from "../prisma";

const serviceAccountPath = path.join(
  process.cwd(),
  "firebase-service-account.json",
);

let app: App | null | undefined;

function getApp(): App | null {
  if (app !== undefined) return app;
  try {
    app = initializeApp({
      credential: cert(serviceAccountPath),
    });
  } catch (error) {
    // Missing/invalid credentials shouldn't crash message sending — push
    // notifications are additive on top of the existing socket delivery.
    console.error(
      "Firebase Admin init failed; push notifications disabled",
      error,
    );
    app = null;
  }
  return app;
}

/// Sends a data-only push to every device the recipient has registered.
/// Data-only (vs a "notification" payload) means Android never auto-displays
/// anything itself — the client fully controls rendering, which is what lets
/// it skip showing a duplicate when the conversation is already open and
/// being delivered live over the socket.
async function sendDataPush(userId: string, data: Record<string, string>) {
  const firebaseApp = getApp();
  if (!firebaseApp) return;

  const tokens = await prisma.deviceToken.findMany({
    where: { userId },
    select: { token: true },
  });
  if (tokens.length === 0) return;

  const response = await getMessaging(firebaseApp).sendEachForMulticast({
    tokens: tokens.map((t) => t.token),
    data,
    android: { priority: "high" },
  });

  const deadTokens: string[] = [];
  response.responses.forEach((result: { error?: { code?: string } | null; success: boolean }, index: number) => {
    const code = result.error?.code;
    if (
      code === "messaging/registration-token-not-registered" ||
      code === "messaging/invalid-registration-token" ||
      code === "messaging/invalid-argument"
    ) {
      deadTokens.push(tokens[index]!.token);
    }
  });
  if (deadTokens.length > 0) {
    await prisma.deviceToken.deleteMany({
      where: { token: { in: deadTokens } },
    });
  }
}

export async function sendMessagePush(
  userId: string,
  payload: { title: string; body: string; conversationId: string },
) {
  await sendDataPush(userId, {
    type: "message",
    conversationId: payload.conversationId,
    title: payload.title,
    body: payload.body,
  });
}

/// Alerts a device to an incoming call it isn't connected to receive over
/// the socket. Deliberately carries no SDP — offers go stale in seconds and
/// don't fit push payload limits anyway; the app resyncs the live offer over
/// the socket itself once it reconnects (see socket.ts's `connection`
/// handler replaying from `activeCalls`).
export async function sendCallPush(
  userId: string,
  payload: {
    callId: string;
    conversationId: string;
    callerName: string;
    isVideo: boolean;
  },
) {
  await sendDataPush(userId, {
    type: "call",
    callId: payload.callId,
    conversationId: payload.conversationId,
    callerName: payload.callerName,
    isVideo: String(payload.isVideo),
  });
}
