import { postAuthorSelect } from "./serializers";

export function postInclude(viewerUserId: string) {
  return {
    author: { select: postAuthorSelect },
    _count: { select: { likes: true, comments: true } },
    likes: { where: { userId: viewerUserId }, select: { userId: true } },
  } as const;
}
