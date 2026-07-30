import "dotenv/config";
import { prisma } from "../src/prisma";

async function main() {
  const user = await prisma.user.findFirstOrThrow({
    where: { username: "testuser" },
  });
  const post = await prisma.post.create({
    data: {
      authorId: user.id,
      imageUrl: "https://example.com/fake.jpg",
      caption: "Seeded test post",
    },
  });
  console.log(JSON.stringify({ postId: post.id }));
}

main().finally(() => prisma.$disconnect());
