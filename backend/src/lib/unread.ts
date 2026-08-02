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
