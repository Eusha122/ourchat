export type UnreadCandidate = {
  conversationId: string;
  senderId: string;
  createdAt: Date;
  unsentAt?: Date | null;
  hiddenForUserIds?: readonly string[];
};

/**
 * The single database predicate used everywhere an unread total is needed.
 * The cursor belongs to one conversation participant, so it is inherently
 * per-user and remains correct when a conversation gains more participants.
 */
export function unreadMessageWhere(input: {
  conversationId: string;
  userId: string;
  lastReadAt: Date | null | undefined;
}) {
  return {
    conversationId: input.conversationId,
    senderId: { not: input.userId },
    unsentAt: null,
    hiddenBy: { none: { userId: input.userId } },
    ...(input.lastReadAt
      ? { createdAt: { gt: input.lastReadAt } }
      : {}),
  };
}

/** Pure counterpart used by the regression suite for cursor scenarios. */
export function countUnreadMessages(
  messages: readonly UnreadCandidate[],
  input: {
    conversationId: string;
    userId: string;
    lastReadAt: Date | null | undefined;
  },
): number {
  return messages.filter((message) => {
    if (message.conversationId !== input.conversationId) return false;
    if (message.senderId === input.userId) return false;
    if (message.unsentAt != null) return false;
    if (message.hiddenForUserIds?.includes(input.userId)) return false;
    return input.lastReadAt == null || message.createdAt > input.lastReadAt;
  }).length;
}

/**
 * Resolves which message a read receipt should advance the cursor to.
 *
 * A client may omit the id (older builds) or name one that has since been
 * removed. Both used to be rejected outright, which froze that participant's
 * cursor permanently — and a frozen cursor is an unread badge that can never
 * be cleared. Falling back to the newest message the user can already see is
 * safe: it only moves the cursor forward, and only across messages that were
 * visible to them anyway.
 */
export function resolveReadTarget(
  visibleMessages: readonly { id: string; createdAt: Date }[],
  requestedId: string | undefined,
): { id: string; createdAt: Date } | null {
  if (requestedId) {
    const exact = visibleMessages.find((m) => m.id === requestedId);
    if (exact) return exact;
  }
  return visibleMessages.reduce<{ id: string; createdAt: Date } | null>(
    (newest, m) =>
      newest == null || m.createdAt > newest.createdAt ? m : newest,
    null,
  );
}

/** A cursor must never move backwards, so a late receipt cannot re-hide reads. */
export function nextReadCursor(
  current: Date | null | undefined,
  target: Date,
): Date {
  return current && current > target ? current : target;
}
