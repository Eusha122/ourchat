import { createHmac } from "crypto";

const fallbackStunServers = [
  { urls: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"] },
];

function turnUrls(): string[] {
  return (process.env.TURN_URLS ?? "")
    .split(",")
    .map((url) => url.trim())
    .filter((url) => url.startsWith("turn:") || url.startsWith("turns:"));
}

/**
 * Returns short-lived TURN credentials for the signed-in user. Coturn's
 * `use-auth-secret` mode derives the same credential from TURN_SHARED_SECRET,
 * so no permanent relay password is shipped in the APK or stored on device.
 */
export function iceServersForUser(userId: string) {
  const urls = turnUrls();
  const sharedSecret = process.env.TURN_SHARED_SECRET?.trim();
  if (!sharedSecret || urls.length === 0) return fallbackStunServers;

  const expiresAt = Math.floor(Date.now() / 1000) + 60 * 60;
  const username = `${expiresAt}:${userId}`;
  const credential = createHmac("sha1", sharedSecret)
    .update(username)
    .digest("base64");

  return [
    ...fallbackStunServers,
    { urls, username, credential },
  ];
}
