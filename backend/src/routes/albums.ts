import { Router, type Request, type Response } from "express";
import multer from "multer";
import { z } from "zod";
import { requireAuth } from "../middleware/auth";
import { prisma } from "../prisma";
import { uploadAlbumMedia } from "../lib/mediaStorage";
import { postAuthorSelect } from "../lib/serializers";

export const albumsRouter = Router();

/// Videos are far larger than chat attachments, so this gets its own cap.
const albumUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 100 * 1024 * 1024 },
});

const createAlbumSchema = z.object({
  username: z.string().trim().min(1),
  name: z.string().trim().min(1).max(60),
});

const memberInclude = {
  members: { include: { user: { select: postAuthorSelect } } },
} as const;

type AlbumWithMembers = {
  id: string;
  name: string;
  createdById: string;
  createdAt: Date;
  members: { userId: string; user: { id: string; username: string; displayName: string | null; avatarUrl: string | null } }[];
};

function serializeAlbum(
  album: AlbumWithMembers,
  viewerId: string,
  extras: { itemCount: number; coverUrl: string | null },
) {
  return {
    id: album.id,
    name: album.name,
    createdById: album.createdById,
    createdAt: album.createdAt,
    // The other member is what the UI actually labels the album with; for a
    // self-only album (peer deleted their account) this is simply absent.
    otherMember:
      album.members.find((member) => member.userId !== viewerId)?.user ?? null,
    itemCount: extras.itemCount,
    coverUrl: extras.coverUrl,
  };
}

async function requireMembership(albumId: string, userId: string) {
  return prisma.albumMember.findUnique({
    where: { albumId_userId: { albumId, userId } },
  });
}

albumsRouter.post("/", requireAuth, async (req, res) => {
  const parsed = createAlbumSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const target = await prisma.user.findUnique({
    where: { username: parsed.data.username },
  });
  if (!target) {
    res.status(404).json({ error: "User not found" });
    return;
  }
  if (target.id === req.userId) {
    res.status(400).json({ error: "Pick someone else to share with" });
    return;
  }

  const album = await prisma.album.create({
    data: {
      name: parsed.data.name,
      createdById: req.userId!,
      members: {
        create: [{ userId: req.userId! }, { userId: target.id }],
      },
    },
    include: memberInclude,
  });

  res.status(201).json({
    album: serializeAlbum(album, req.userId!, { itemCount: 0, coverUrl: null }),
  });
});

albumsRouter.get("/", requireAuth, async (req, res) => {
  const memberships = await prisma.albumMember.findMany({
    where: { userId: req.userId },
    include: {
      album: {
        include: {
          ...memberInclude,
          _count: { select: { items: true } },
          items: {
            orderBy: { createdAt: "desc" },
            take: 1,
            select: { url: true, thumbnailUrl: true },
          },
        },
      },
    },
    orderBy: { album: { updatedAt: "desc" } },
  });

  const albums = memberships.map((membership) => {
    const cover = membership.album.items[0];
    return serializeAlbum(membership.album, req.userId!, {
      itemCount: membership.album._count.items,
      coverUrl: cover ? (cover.thumbnailUrl ?? cover.url) : null,
    });
  });

  res.json({ albums });
});

albumsRouter.get("/:albumId", requireAuth, async (req, res) => {
  const albumId = req.params.albumId as string;
  if (!(await requireMembership(albumId, req.userId!))) {
    res.status(403).json({ error: "Not a member of this album" });
    return;
  }

  const album = await prisma.album.findUnique({
    where: { id: albumId },
    include: {
      ...memberInclude,
      _count: { select: { items: true } },
      items: {
        orderBy: { createdAt: "desc" },
        include: { uploader: { select: postAuthorSelect } },
      },
    },
  });
  if (!album) {
    res.status(404).json({ error: "Album not found" });
    return;
  }

  res.json({
    album: serializeAlbum(album, req.userId!, {
      itemCount: album._count.items,
      coverUrl: album.items[0]
        ? (album.items[0].thumbnailUrl ?? album.items[0].url)
        : null,
    }),
    items: album.items.map((item) => ({
      id: item.id,
      url: item.url,
      thumbnailUrl: item.thumbnailUrl,
      type: item.type,
      width: item.width,
      height: item.height,
      caption: item.caption,
      createdAt: item.createdAt,
      uploader: item.uploader,
    })),
  });
});

async function handleUpload(req: Request, res: Response) {
  const albumId = req.params.albumId as string;
  if (!(await requireMembership(albumId, req.userId!))) {
    res.status(403).json({ error: "Not a member of this album" });
    return;
  }
  if (!req.file) {
    res.status(400).json({ error: "No file uploaded" });
    return;
  }

  const originalName = req.file.originalname || "upload";
  const dotIndex = originalName.lastIndexOf(".");
  const extension = dotIndex >= 0 ? originalName.slice(dotIndex + 1) : "bin";

  const rawCaption = req.body?.caption;
  const caption =
    typeof rawCaption === "string" && rawCaption.trim().length > 0
      ? rawCaption.trim().slice(0, 500)
      : null;

  const stored = await uploadAlbumMedia({
    buffer: req.file.buffer,
    contentType: req.file.mimetype,
    fileExtension: extension,
    publicOrigin: `${req.protocol}://${req.get("host")}`,
  });

  const item = await prisma.albumItem.create({
    data: {
      albumId,
      uploaderId: req.userId!,
      url: stored.url,
      thumbnailUrl: stored.thumbnailUrl,
      caption,
      type: stored.isVideo ? "VIDEO" : "IMAGE",
      width: stored.width,
      height: stored.height,
    },
    include: { uploader: { select: postAuthorSelect } },
  });

  // Keeps the album at the top of both members' lists.
  await prisma.album.update({
    where: { id: albumId },
    data: { updatedAt: new Date() },
  });

  res.status(201).json({
    item: {
      id: item.id,
      url: item.url,
      thumbnailUrl: item.thumbnailUrl,
      type: item.type,
      width: item.width,
      height: item.height,
      caption: item.caption,
      createdAt: item.createdAt,
      uploader: item.uploader,
    },
  });
}

albumsRouter.post("/:albumId/items", requireAuth, (req, res) => {
  albumUpload.single("file")(req, res, (err) => {
    if (err) {
      res.status(400).json({ error: err.message });
      return;
    }
    handleUpload(req, res).catch((error) => {
      console.error(error);
      res.status(500).json({ error: "Internal server error" });
    });
  });
});
