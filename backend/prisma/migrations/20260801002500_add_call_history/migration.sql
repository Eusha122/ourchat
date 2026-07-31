ALTER TYPE "MessageType" ADD VALUE 'CALL';

CREATE TYPE "CallKind" AS ENUM ('AUDIO', 'VIDEO');
CREATE TYPE "CallStatus" AS ENUM ('STARTED', 'COMPLETED', 'MISSED', 'DECLINED');

ALTER TABLE "Message"
  ADD COLUMN "callKind" "CallKind",
  ADD COLUMN "callStatus" "CallStatus",
  ADD COLUMN "callDurationSeconds" INTEGER;
