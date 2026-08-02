import assert from "node:assert/strict";
import test from "node:test";
import { countUnreadMessages, unreadMessageWhere, type UnreadCandidate, resolveReadTarget, nextReadCursor } from "./unread";

const A = "user-a";
const B = "user-b";
const C = "user-c";
const AB = "conversation-ab";
const AC = "conversation-ac";
let tick = 0;

function message(
  conversationId: string,
  senderId: string,
): UnreadCandidate {
  tick += 1;
  return {
    conversationId,
    senderId,
    createdAt: new Date(Date.UTC(2026, 0, 1, 0, 0, tick)),
  };
}

function unread(
  messages: readonly UnreadCandidate[],
  conversationId: string,
  userId: string,
  lastReadAt: Date | null = null,
) {
  return countUnreadMessages(messages, {
    conversationId,
    userId,
    lastReadAt,
  });
}

function openConversation(
  messages: readonly UnreadCandidate[],
  conversationId: string,
): Date | null {
  return messages
    .filter((item) => item.conversationId === conversationId)
    .reduce<Date | null>(
      (latest, item) =>
        latest == null || item.createdAt > latest ? item.createdAt : latest,
      null,
    );
}

test("database predicate always excludes the current user's messages", () => {
  const where = unreadMessageWhere({
    conversationId: AB,
    userId: A,
    lastReadAt: null,
  });
  assert.deepEqual(where.senderId, { not: A });
  assert.deepEqual(where.hiddenBy, { none: { userId: A } });
  assert.equal(where.unsentAt, null);
});

test("1: A sends B 10 messages: A=0, B=10", () => {
  const messages = Array.from({ length: 10 }, () => message(AB, A));
  assert.equal(unread(messages, AB, A), 0);
  assert.equal(unread(messages, AB, B), 10);
});

test("2: B opens: both unread totals are zero and A may show Seen", () => {
  const messages = Array.from({ length: 10 }, () => message(AB, A));
  const bCursor = openConversation(messages, AB);
  assert.equal(unread(messages, AB, B, bCursor), 0);
  assert.equal(unread(messages, AB, A), 0);
  assert.ok(messages.at(-1)!.createdAt <= bCursor!);
});

test("3: B sends A one message: A=1, B=0", () => {
  const messages = [message(AB, B)];
  assert.equal(unread(messages, AB, A), 1);
  assert.equal(unread(messages, AB, B), 0);
});

test("4: rendering the inbox preview does not advance A's cursor", () => {
  const messages = [message(AB, B)];
  const aCursor = null;
  assert.equal(unread(messages, AB, A, aCursor), 1);
  assert.equal(unread(messages, AB, A, aCursor), 1);
});

test("5: A opens the conversation and unread becomes zero", () => {
  const messages = [message(AB, B)];
  const aCursor = openConversation(messages, AB);
  assert.equal(unread(messages, AB, A, aCursor), 0);
});

test("6: an incoming message rendered in A's active chat stays read", () => {
  const messages = [message(AB, B)];
  const aCursor = openConversation(messages, AB);
  assert.equal(unread(messages, AB, A, aCursor), 0);
});

test("7: activity in another conversation remains independently unread", () => {
  const messages = [
    message(AB, B),
    ...Array.from({ length: 4 }, () => message(AC, C)),
  ];
  const abCursor = openConversation(messages, AB);
  assert.equal(unread(messages, AB, A, abCursor), 0);
  assert.equal(unread(messages, AC, A), 4);
});

test("8: A's own outgoing message never increments A's unread count", () => {
  const messages = [message(AC, A)];
  assert.equal(unread(messages, AC, A), 0);
});

test("9: five read messages followed by one new message yields exactly one", () => {
  const messages = Array.from({ length: 5 }, () => message(AB, B));
  const aCursor = openConversation(messages, AB);
  messages.push(message(AB, B));
  assert.equal(unread(messages, AB, A, aCursor), 1);
});

test("10: a backend cursor update clears every device's derived count", () => {
  const messages = Array.from({ length: 4 }, () => message(AB, B));
  let persistedCursor: Date | null = null;
  assert.equal(unread(messages, AB, A, persistedCursor), 4);
  assert.equal(unread(messages, AB, A, persistedCursor), 4);
  persistedCursor = openConversation(messages, AB);
  assert.equal(unread(messages, AB, A, persistedCursor), 0);
  assert.equal(unread(messages, AB, A, persistedCursor), 0);
});

test("duplicates/out-of-order realtime delivery cannot change authoritative count", () => {
  const first = message(AB, B);
  const second = message(AB, B);
  const persisted = [first, second];
  assert.equal(unread(persisted, AB, A), 2);
  assert.equal(unread(persisted, AB, A), 2);
});

const READ_TARGETS = [
  { id: "m1", createdAt: new Date("2026-08-02T19:00:00Z") },
  { id: "m2", createdAt: new Date("2026-08-02T20:00:00Z") },
  { id: "m3", createdAt: new Date("2026-08-02T20:18:56Z") },
];

test("read target: an explicitly named message is used as-is", () => {
  assert.equal(resolveReadTarget(READ_TARGETS, "m2")?.id, "m2");
});

test("read target: an omitted id falls back to the newest visible message", () => {
  // Regression: older clients POST /read with no body at all. Rejecting them
  // with a 400 froze that participant's cursor, leaving an unread badge that
  // could never be cleared.
  assert.equal(resolveReadTarget(READ_TARGETS, undefined)?.id, "m3");
});

test("read target: a stale or deleted id falls back instead of failing", () => {
  assert.equal(resolveReadTarget(READ_TARGETS, "since-deleted")?.id, "m3");
});

test("read target: an empty conversation resolves to nothing", () => {
  assert.equal(resolveReadTarget([], "anything"), null);
});

test("read cursor never moves backwards", () => {
  const later = new Date("2026-08-02T20:18:56Z");
  const earlier = new Date("2026-08-02T19:00:00Z");
  assert.equal(nextReadCursor(later, earlier).toISOString(), later.toISOString());
  assert.equal(nextReadCursor(earlier, later).toISOString(), later.toISOString());
  assert.equal(nextReadCursor(null, later).toISOString(), later.toISOString());
});
