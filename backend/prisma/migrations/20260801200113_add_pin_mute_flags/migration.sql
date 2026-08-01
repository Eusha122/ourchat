-- AlterTable
ALTER TABLE "ConversationParticipant" ADD COLUMN     "mutedCalls" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "mutedMessages" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "pinned" BOOLEAN NOT NULL DEFAULT false;
