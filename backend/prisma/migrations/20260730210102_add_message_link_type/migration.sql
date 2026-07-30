-- CreateEnum
CREATE TYPE "MessageType" AS ENUM ('TEXT', 'LINK');

-- AlterTable
ALTER TABLE "Message" ADD COLUMN     "linkImageUrl" TEXT,
ADD COLUMN     "linkTitle" TEXT,
ADD COLUMN     "linkUrl" TEXT,
ADD COLUMN     "type" "MessageType" NOT NULL DEFAULT 'TEXT',
ALTER COLUMN "text" DROP NOT NULL;
