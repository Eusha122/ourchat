import type { Comment, Prisma, User } from "../generated/prisma/client";

export function toPublicUser(user: User) {
  return {
    id: user.id,
    username: user.username,
    email: user.email,
    displayName: user.displayName,
    bio: user.bio,
    avatarUrl: user.avatarUrl,
    createdAt: user.createdAt,
  };
}

/** Same as {@link toPublicUser} but omits email, for viewing other users. */
export function toPublicProfile(user: User) {
  return {
    id: user.id,
    username: user.username,
    displayName: user.displayName,
    bio: user.bio,
    avatarUrl: user.avatarUrl,
    createdAt: user.createdAt,
  };
}

export const postAuthorSelect = {
  id: true,
  username: true,
  displayName: true,
  avatarUrl: true,
} as const satisfies Prisma.UserSelect;

type PostWithRelations = Prisma.PostGetPayload<{
  include: {
    author: { select: typeof postAuthorSelect };
    _count: { select: { likes: true; comments: true } };
    likes: { select: { userId: true } };
  };
}>;

export function toPublicPost(post: PostWithRelations) {
  return {
    id: post.id,
    imageUrl: post.imageUrl,
    caption: post.caption,
    createdAt: post.createdAt,
    author: post.author,
    likeCount: post._count.likes,
    commentCount: post._count.comments,
    likedByMe: post.likes.length > 0,
  };
}

type CommentWithAuthor = Comment & {
  author: Prisma.UserGetPayload<{ select: typeof postAuthorSelect }>;
};

export function toPublicComment(comment: CommentWithAuthor) {
  return {
    id: comment.id,
    text: comment.text,
    createdAt: comment.createdAt,
    author: comment.author,
  };
}

type MessageWithSender = Prisma.MessageGetPayload<{
  include: { sender: { select: typeof postAuthorSelect } };
}>;

export function toPublicMessage(message: MessageWithSender) {
  return {
    id: message.id,
    conversationId: message.conversationId,
    text: message.text,
    createdAt: message.createdAt,
    sender: message.sender,
  };
}
