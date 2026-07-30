import "dotenv/config";
import { createServer } from "http";
import { app } from "./app";
import { initSocket } from "./socket";

const PORT = process.env.PORT ? Number(process.env.PORT) : 4000;

const httpServer = createServer(app);
initSocket(httpServer);

httpServer.listen(PORT, () => {
  console.log(`Backend listening on http://localhost:${PORT}`);
});
