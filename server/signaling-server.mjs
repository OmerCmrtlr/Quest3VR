import os from "node:os";
import { WebSocketServer } from "ws";

const PORT = Number(process.env.SIGNAL_PORT ?? 8787);

/** @typedef {{ id: string; role: "host" | "viewer" | null; sessionId: string | null }} ClientMeta */
/** @typedef {{ hostId: string | null; hostSocket: import("ws").WebSocket | null; viewers: Map<string, import("ws").WebSocket> }} Room */

const wss = new WebSocketServer({ port: PORT });

/** @type {Map<string, Room>} */
const rooms = new Map();
/** @type {Map<import("ws").WebSocket, ClientMeta>} */
const clients = new Map();

function createId() {
  return Math.random().toString(36).slice(2, 10);
}

/** @param {import("ws").WebSocket} socket @param {unknown} payload */
function send(socket, payload) {
  if (socket.readyState !== socket.OPEN) return;
  socket.send(JSON.stringify(payload));
}

/** @param {string} sessionId */
function ensureRoom(sessionId) {
  const existing = rooms.get(sessionId);
  if (existing) return existing;

  const room = {
    hostId: null,
    hostSocket: null,
    viewers: new Map(),
  };

  rooms.set(sessionId, room);
  return room;
}

/** @param {Room} room @param {string} targetId */
function resolveTargetSocket(room, targetId) {
  if (room.hostId === targetId && room.hostSocket) {
    return room.hostSocket;
  }

  return room.viewers.get(targetId) ?? null;
}

/** @param {string} sessionId */
function cleanupRoom(sessionId) {
  const room = rooms.get(sessionId);
  if (!room) return;
  if (room.hostSocket || room.viewers.size > 0) return;
  rooms.delete(sessionId);
}

/** @param {ClientMeta} meta @param {import("ws").WebSocket} socket */
function removeClientFromRoom(meta, socket) {
  if (!meta.role || !meta.sessionId) return;

  const room = rooms.get(meta.sessionId);
  if (!room) {
    meta.role = null;
    meta.sessionId = null;
    return;
  }

  if (meta.role === "host") {
    if (room.hostSocket === socket) {
      room.hostSocket = null;
      room.hostId = null;
      room.viewers.forEach((viewerSocket) => send(viewerSocket, { type: "host-left" }));
      console.log(`[signal] host left session=${meta.sessionId}`);
    }
  } else {
    room.viewers.delete(meta.id);
    if (room.hostSocket) {
      send(room.hostSocket, { type: "viewer-left", from: meta.id });
    }
    console.log(`[signal] viewer left session=${meta.sessionId} id=${meta.id}`);
  }

  cleanupRoom(meta.sessionId);
  meta.role = null;
  meta.sessionId = null;
}

function listLanUrls() {
  const values = Object.values(os.networkInterfaces()).flat().filter(Boolean);
  const ipv4 = values.filter((item) => item.family === "IPv4" && !item.internal);
  return ipv4.map((item) => `ws://${item.address}:${PORT}`);
}

wss.on("connection", (socket) => {
  const meta = {
    id: createId(),
    role: null,
    sessionId: null,
  };

  clients.set(socket, meta);
  send(socket, { type: "connected", id: meta.id });

  socket.on("message", (raw) => {
    let payload;
    try {
      payload = JSON.parse(raw.toString());
    } catch {
      send(socket, { type: "error", message: "Geçersiz JSON" });
      return;
    }

    if (!payload || typeof payload !== "object") return;

    if (payload.type === "hello") {
      const role = payload.role === "viewer" ? "viewer" : "host";
      const sessionId =
        typeof payload.sessionId === "string" && payload.sessionId.trim()
          ? payload.sessionId.trim().toUpperCase()
          : "QUEST3";

      removeClientFromRoom(meta, socket);

      meta.role = role;
      meta.sessionId = sessionId;

      const room = ensureRoom(sessionId);

      if (role === "host") {
        if (room.hostSocket && room.hostSocket !== socket) {
          send(room.hostSocket, { type: "host-replaced" });
          room.hostSocket.close();
        }

        room.hostSocket = socket;
        room.hostId = meta.id;

        room.viewers.forEach((viewerSocket) => {
          send(viewerSocket, { type: "host-ready", from: meta.id });
        });

        console.log(`[signal] host joined session=${sessionId} id=${meta.id}`);
        return;
      }

      room.viewers.set(meta.id, socket);

      if (room.hostSocket && room.hostId) {
        send(room.hostSocket, { type: "viewer-joined", from: meta.id });
        send(socket, { type: "host-ready", from: room.hostId });
      } else {
        send(socket, { type: "waiting-host" });
      }

      console.log(`[signal] viewer joined session=${sessionId} id=${meta.id}`);
      return;
    }

    if (!meta.sessionId) {
      send(socket, { type: "error", message: "Önce hello mesajı gönderilmeli" });
      return;
    }

    if (payload.type === "offer" || payload.type === "answer" || payload.type === "ice") {
      if (typeof payload.to !== "string" || !payload.to) {
        send(socket, { type: "error", message: "Mesaj hedefi (to) eksik" });
        return;
      }

      const room = rooms.get(meta.sessionId);
      if (!room) {
        send(socket, { type: "error", message: "Session bulunamadı" });
        return;
      }

      const target = resolveTargetSocket(room, payload.to);
      if (!target) {
        send(socket, { type: "error", message: `Hedef bulunamadı: ${payload.to}` });
        return;
      }

      send(target, {
        ...payload,
        from: meta.id,
      });
    }
  });

  socket.on("close", () => {
    removeClientFromRoom(meta, socket);
    clients.delete(socket);
  });
});

console.log(`[signal] WebSocket server running on ws://0.0.0.0:${PORT}`);
for (const url of listLanUrls()) {
  console.log(`[signal] LAN: ${url}`);
}