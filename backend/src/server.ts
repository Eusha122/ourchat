import "dotenv/config";
import { createServer } from "http";
import { Server } from "socket.io";
import { app } from "./app";

const PORT = process.env.PORT ? Number(process.env.PORT) : 4000;

const httpServer = createServer(app);
export const io = new Server(httpServer, {
  cors: { origin: "*" },
});

io.on("connection", (socket) => {
  console.log("socket connected:", socket.id);
});

httpServer.listen(PORT, () => {
  console.log(`Backend listening on http://localhost:${PORT}`);
});
