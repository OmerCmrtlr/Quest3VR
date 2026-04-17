import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { cn } from "./utils/cn";

type Mode = "host" | "viewer";
type SignalState = "disconnected" | "connecting" | "connected";

// Sistem durum tipleri
interface SystemStatus {
  gstreamer: "unknown" | "ok" | "error";
  udpStream: "unknown" | "sending" | "error";
  webStream: "unknown" | "active" | "inactive";
  tabletReachable: "unknown" | "yes" | "no";
}

const ICE_CONFIG: RTCConfiguration = {
  iceServers: [{ urls: "stun:stun.l.google.com:19302" }],
};

const LAPTOP_IP = "192.168.2.207";
const TABLET_IP = "192.168.2.154";
const UDP_PORT = 5010;

function createSessionId() {
  return Math.random().toString(36).slice(2, 8).toUpperCase();
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function getInitialMode(): Mode {
  const mode = new URLSearchParams(window.location.search).get("mode");
  return mode === "viewer" ? "viewer" : "host";
}

function getInitialSession() {
  const raw = new URLSearchParams(window.location.search).get("session");
  return raw?.trim().toUpperCase() || createSessionId();
}

function getInitialSignalUrl() {
  const proto = window.location.protocol === "https:" ? "wss" : "ws";
  return `${proto}://${window.location.hostname}:8787`;
}

// Sistem Durum Paneli
function SystemStatusPanel({
  status,
  laptopIp,
  tabletIp,
  udpPort,
  onLaptopIpChange,
  onTabletIpChange,
  onTestStream,
  onStopStream,
  streamActive,
}: {
  status: SystemStatus;
  laptopIp: string;
  tabletIp: string;
  udpPort: number;
  onLaptopIpChange: (ip: string) => void;
  onTabletIpChange: (ip: string) => void;
  onTestStream: () => void;
  onStopStream: () => void;
  streamActive: boolean;
}) {
  const badge = (state: string, okLabel: string, errLabel: string, unknownLabel: string) => {
    const map: Record<string, string> = {
      ok: "bg-green-900 text-green-300 border-green-700",
      active: "bg-green-900 text-green-300 border-green-700",
      sending: "bg-green-900 text-green-300 border-green-700",
      yes: "bg-green-900 text-green-300 border-green-700",
      error: "bg-rose-900 text-rose-300 border-rose-700",
      no: "bg-rose-900 text-rose-300 border-rose-700",
      inactive: "bg-slate-800 text-slate-400 border-slate-600",
      unknown: "bg-slate-800 text-slate-400 border-slate-600",
    };
    const labelMap: Record<string, string> = {
      ok: okLabel,
      active: okLabel,
      sending: okLabel,
      yes: okLabel,
      error: errLabel,
      no: errLabel,
      inactive: unknownLabel,
      unknown: unknownLabel,
    };
    return (
      <span className={cn("rounded border px-2 py-0.5 text-xs font-mono", map[state] ?? map.unknown)}>
        {labelMap[state] ?? unknownLabel}
      </span>
    );
  };

  return (
    <div className="rounded-xl border border-slate-700 bg-slate-900/70 p-4 space-y-4">
      <h2 className="text-sm font-bold text-cyan-300">🔧 Sistem Kontrol Paneli</h2>

      {/* IP Ayarları */}
      <div className="grid grid-cols-2 gap-3">
        <label className="block text-xs">
          <span className="text-slate-400 mb-1 block">Laptop IP (Gönderici)</span>
          <input
            value={laptopIp}
            onChange={(e) => onLaptopIpChange(e.target.value)}
            className="w-full rounded border border-slate-700 bg-slate-950 px-2 py-1.5 text-xs font-mono outline-none ring-cyan-500 focus:ring"
          />
        </label>
        <label className="block text-xs">
          <span className="text-slate-400 mb-1 block">Tablet IP (Alıcı)</span>
          <input
            value={tabletIp}
            onChange={(e) => onTabletIpChange(e.target.value)}
            className="w-full rounded border border-slate-700 bg-slate-950 px-2 py-1.5 text-xs font-mono outline-none ring-cyan-500 focus:ring"
          />
        </label>
      </div>

      {/* Durum Göstergeleri */}
      <div className="rounded border border-slate-700 bg-slate-950 p-3 space-y-2">
        <p className="text-xs font-semibold text-slate-300 mb-2">Sistem Durumu</p>
        <div className="grid grid-cols-2 gap-2 text-xs">
          <div className="flex items-center justify-between">
            <span className="text-slate-400">Web Stream:</span>
            {badge(status.webStream, "✓ Aktif", "✗ Hata", "? Bilinmiyor")}
          </div>
          <div className="flex items-center justify-between">
            <span className="text-slate-400">UDP Port {udpPort}:</span>
            {badge(status.udpStream, "✓ Gönderiyor", "✗ Hata", "? Test edilmedi")}
          </div>
        </div>
      </div>

      {/* Terminal Komutları */}
      <div className="rounded border border-slate-700 bg-slate-950 p-3 space-y-2">
        <p className="text-xs font-semibold text-slate-300">Terminal Komutları (Kopyala-Çalıştır)</p>

        <div className="space-y-2">
          <div>
            <p className="text-[10px] text-slate-500 mb-1">1. Firewall aç:</p>
            <code className="block text-[10px] text-green-300 bg-slate-900 px-2 py-1 rounded font-mono break-all">
              sudo ufw allow 5010/udp && sudo ufw reload
            </code>
          </div>
          <div>
            <p className="text-[10px] text-slate-500 mb-1">2. Test stream başlat (kamerasız):</p>
            <code className="block text-[10px] text-green-300 bg-slate-900 px-2 py-1 rounded font-mono break-all">
              {`python3 /home/bnfnc/Projects/Quest3/godot-pack/python/stereo_webcam_gst_sender.py --host ${tabletIp} --port ${udpPort} --test`}
            </code>
          </div>
          <div>
            <p className="text-[10px] text-slate-500 mb-1">3. Gerçek kamera stream:</p>
            <code className="block text-[10px] text-green-300 bg-slate-900 px-2 py-1 rounded font-mono break-all">
              {`python3 /home/bnfnc/Projects/Quest3/godot-pack/python/stereo_webcam_gst_sender.py --host ${tabletIp} --port ${udpPort} --device /dev/video0`}
            </code>
          </div>
          <div>
            <p className="text-[10px] text-slate-500 mb-1">4. UDP paket kontrol (laptop'ta):</p>
            <code className="block text-[10px] text-green-300 bg-slate-900 px-2 py-1 rounded font-mono break-all">
              sudo tcpdump -i any udp port 5010 -c 10 -q
            </code>
          </div>
          <div>
            <p className="text-[10px] text-slate-500 mb-1">5. ADB logcat (tablet bağlıysa):</p>
            <code className="block text-[10px] text-green-300 bg-slate-900 px-2 py-1 rounded font-mono break-all">
              adb logcat -v time | grep -E "ExtReceiver|VideoMesh|ExternalTexture"
            </code>
          </div>
        </div>
      </div>

      {/* Web Stream Kontrol */}
      <div className="flex gap-2">
        <button
          onClick={onTestStream}
          disabled={streamActive}
          className={cn(
            "rounded px-3 py-2 text-xs font-semibold",
            streamActive
              ? "bg-slate-700 text-slate-500 cursor-not-allowed"
              : "bg-emerald-600 text-white hover:bg-emerald-500"
          )}
        >
          {streamActive ? "Web Stream Aktif" : "Web Stream Başlat"}
        </button>
        <button
          onClick={onStopStream}
          disabled={!streamActive}
          className={cn(
            "rounded px-3 py-2 text-xs font-semibold",
            !streamActive
              ? "bg-slate-700 text-slate-500 cursor-not-allowed"
              : "bg-rose-600 text-white hover:bg-rose-500"
          )}
        >
          Durdur
        </button>
      </div>

      {/* Quest3 / Tablet Geçiş Notu */}
      <div className="rounded border border-cyan-900 bg-cyan-950/30 p-3 text-xs text-cyan-200">
        <p className="font-semibold mb-1">📱 Cihaz Geçişi</p>
        <p>Tablet → Quest3 geçişinde sadece "Tablet IP" alanını Quest3 IP'siyle değiştir.</p>
        <p className="mt-1 text-cyan-300">Quest3 IP: ADB ile bul → <code className="bg-slate-900 px-1 rounded">adb shell ip addr | grep wlan</code></p>
      </div>
    </div>
  );
}

interface StereoViewportProps {
  stream: MediaStream | null;
  title: string;
  emptyText: string;
  shiftPx: number;
  zoom: number;
  mirror: boolean;
}

function StereoViewport({ stream, title, emptyText, shiftPx, zoom, mirror }: StereoViewportProps) {
  const leftRef = useRef<HTMLVideoElement>(null);
  const rightRef = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    for (const video of [leftRef.current, rightRef.current]) {
      if (!video) continue;
      video.srcObject = stream;
      if (stream) void video.play().catch(() => undefined);
    }
  }, [stream]);

  if (!stream) {
    return (
      <div className="w-full rounded-xl border border-slate-700 bg-slate-900/70 p-8 text-center text-slate-400">
        {emptyText}
      </div>
    );
  }

  const leftTransform = `${mirror ? "scaleX(-1) " : ""}translateX(-${Math.abs(shiftPx)}px) scale(${zoom})`;
  const rightTransform = `${mirror ? "scaleX(-1) " : ""}translateX(${Math.abs(shiftPx)}px) scale(${zoom})`;

  return (
    <div className="overflow-hidden rounded-xl border border-slate-700 bg-black">
      <div className="border-b border-slate-700 bg-slate-900/80 px-3 py-2 text-xs font-semibold text-cyan-300">
        {title}
      </div>
      <div className="grid grid-cols-2">
        <div className="relative h-[42vh] min-h-[240px] overflow-hidden border-r border-slate-700">
          <video ref={leftRef} autoPlay muted playsInline className="h-full w-full object-cover"
            style={{ transform: leftTransform }} />
          <span className="absolute left-2 top-2 rounded bg-slate-900/70 px-2 py-0.5 text-[11px] text-slate-200">Sol Göz</span>
        </div>
        <div className="relative h-[42vh] min-h-[240px] overflow-hidden">
          <video ref={rightRef} autoPlay muted playsInline className="h-full w-full object-cover"
            style={{ transform: rightTransform }} />
          <span className="absolute left-2 top-2 rounded bg-slate-900/70 px-2 py-0.5 text-[11px] text-slate-200">Sağ Göz</span>
        </div>
      </div>
    </div>
  );
}

export default function App() {
  const [mode, setMode] = useState<Mode>(getInitialMode);
  const [sessionId, setSessionId] = useState(getInitialSession);
  const [signalUrl, setSignalUrl] = useState(getInitialSignalUrl);
  const [laptopIp, setLaptopIp] = useState(LAPTOP_IP);
  const [tabletIp, setTabletIp] = useState(TABLET_IP);

  const [signalState, setSignalState] = useState<SignalState>("disconnected");
  const [statusText, setStatusText] = useState("Hazır");
  const [errorText, setErrorText] = useState("");
  const [viewerCount, setViewerCount] = useState(0);
  const [eyeShiftPx, setEyeShiftPx] = useState(16);
  const [eyeZoom, setEyeZoom] = useState(1.04);

  const [localStream, setLocalStream] = useState<MediaStream | null>(null);
  const [remoteStream, setRemoteStream] = useState<MediaStream | null>(null);

  const [sysStatus, setSysStatus] = useState<SystemStatus>({
    gstreamer: "unknown",
    udpStream: "unknown",
    webStream: "unknown",
    tabletReachable: "unknown",
  });

  const wsRef = useRef<WebSocket | null>(null);
  const localStreamRef = useRef<MediaStream | null>(null);
  const viewerPeerRef = useRef<RTCPeerConnection | null>(null);
  const viewerHostIdRef = useRef("");
  const hostPeersRef = useRef<Map<string, RTCPeerConnection>>(new Map());
  const pendingViewersRef = useRef<Set<string>>(new Set());

  const normalizedSessionId = useMemo(
    () => sessionId.trim().toUpperCase() || "QUEST3",
    [sessionId]
  );

  const viewerLink = useMemo(() => {
    const proto = window.location.protocol === "https:" ? "https" : "http";
    const portPart = window.location.port ? `:${window.location.port}` : "";
    return `${proto}://${laptopIp}${portPart}/?mode=viewer&session=${encodeURIComponent(normalizedSessionId)}`;
  }, [laptopIp, normalizedSessionId]);

  useEffect(() => { localStreamRef.current = localStream; }, [localStream]);

  const sendSignal = useCallback((payload: Record<string, unknown>) => {
    const ws = wsRef.current;
    if (!ws || ws.readyState !== WebSocket.OPEN) return;
    ws.send(JSON.stringify(payload));
  }, []);

  const closeHostPeer = useCallback((viewerId: string) => {
    hostPeersRef.current.get(viewerId)?.close();
    hostPeersRef.current.delete(viewerId);
    pendingViewersRef.current.delete(viewerId);
    setViewerCount(hostPeersRef.current.size);
  }, []);

  const closeAllHostPeers = useCallback(() => {
    for (const peer of hostPeersRef.current.values()) peer.close();
    hostPeersRef.current.clear();
    pendingViewersRef.current.clear();
    setViewerCount(0);
  }, []);

  const closeViewerPeer = useCallback(() => {
    viewerPeerRef.current?.close();
    viewerPeerRef.current = null;
    viewerHostIdRef.current = "";
    setRemoteStream(null);
  }, []);

  const createHostPeer = useCallback(async (viewerId: string) => {
    const stream = localStreamRef.current;
    if (!stream) { pendingViewersRef.current.add(viewerId); return; }
    closeHostPeer(viewerId);
    const peer = new RTCPeerConnection(ICE_CONFIG);
    hostPeersRef.current.set(viewerId, peer);
    setViewerCount(hostPeersRef.current.size);
    stream.getTracks().forEach((t) => peer.addTrack(t, stream));
    peer.onicecandidate = (e) => {
      if (e.candidate) sendSignal({ type: "ice", to: viewerId, candidate: e.candidate.toJSON() });
    };
    peer.onconnectionstatechange = () => {
      if (["failed", "closed", "disconnected"].includes(peer.connectionState)) closeHostPeer(viewerId);
    };
    const offer = await peer.createOffer({ offerToReceiveAudio: false, offerToReceiveVideo: false });
    await peer.setLocalDescription(offer);
    sendSignal({ type: "offer", to: viewerId, sdp: offer });
  }, [closeHostPeer, sendSignal]);

  const ensureViewerPeer = useCallback((hostId: string) => {
    if (viewerPeerRef.current && viewerHostIdRef.current === hostId) return viewerPeerRef.current;
    viewerPeerRef.current?.close();
    viewerHostIdRef.current = hostId;
    const peer = new RTCPeerConnection(ICE_CONFIG);
    viewerPeerRef.current = peer;
    peer.onicecandidate = (e) => {
      if (e.candidate && viewerHostIdRef.current)
        sendSignal({ type: "ice", to: viewerHostIdRef.current, candidate: e.candidate.toJSON() });
    };
    peer.ontrack = (e) => {
      const [s] = e.streams;
      if (s) { setRemoteStream(s); setStatusText("Host görüntüsü geliyor."); }
    };
    peer.onconnectionstatechange = () => {
      if (["failed", "closed"].includes(peer.connectionState)) {
        setStatusText("Bağlantı kapandı.");
        closeViewerPeer();
      }
    };
    return peer;
  }, [closeViewerPeer, sendSignal]);

  const startCamera = useCallback(async () => {
    if (localStreamRef.current) return;
    setErrorText("");
    setStatusText("Webcam açılıyor...");
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: false,
        video: { width: { ideal: 1280 }, height: { ideal: 720 }, frameRate: { ideal: 30, max: 30 } },
      });
      setLocalStream(stream);
      localStreamRef.current = stream;
      setStatusText("Webcam aktif.");
      setSysStatus((s) => ({ ...s, webStream: "active" }));
      const waiting = Array.from(pendingViewersRef.current);
      pendingViewersRef.current.clear();
      for (const id of waiting) await createHostPeer(id);
    } catch {
      setErrorText("Webcam açılamadı. localhost'tan aç ve kamera iznini ver.");
      setSysStatus((s) => ({ ...s, webStream: "error" }));
    }
  }, [createHostPeer]);

  const stopCamera = useCallback(() => {
    localStreamRef.current?.getTracks().forEach((t) => t.stop());
    localStreamRef.current = null;
    setLocalStream(null);
    closeAllHostPeers();
    setSysStatus((s) => ({ ...s, webStream: "inactive" }));
    setStatusText("Webcam durduruldu.");
  }, [closeAllHostPeers]);

  const handleSignalMessage = useCallback(async (rawData: string) => {
    let payload: unknown;
    try { payload = JSON.parse(rawData); } catch { return; }
    if (!isObject(payload) || !isNonEmptyString(payload.type)) return;

    if (payload.type === "error" && isNonEmptyString(payload.message)) { setErrorText(payload.message); return; }
    if (payload.type === "host-ready" && mode === "viewer") { setStatusText("Host hazır..."); return; }
    if (payload.type === "waiting-host" && mode === "viewer") { setStatusText("Host bekleniyor."); return; }
    if (payload.type === "host-left" && mode === "viewer") { closeViewerPeer(); setStatusText("Host kapandı."); return; }

    if (mode === "host") {
      if (payload.type === "viewer-joined" && isNonEmptyString(payload.from)) {
        await createHostPeer(payload.from); setStatusText(`Viewer bağlandı (${payload.from}).`); return;
      }
      if (payload.type === "viewer-left" && isNonEmptyString(payload.from)) {
        closeHostPeer(payload.from); return;
      }
      if (payload.type === "answer" && isNonEmptyString(payload.from) && isObject(payload.sdp)) {
        await hostPeersRef.current.get(payload.from)?.setRemoteDescription(
          new RTCSessionDescription(payload.sdp as RTCSessionDescriptionInit)
        ); return;
      }
      if (payload.type === "ice" && isNonEmptyString(payload.from) && isObject(payload.candidate)) {
        await hostPeersRef.current.get(payload.from)?.addIceCandidate(
          new RTCIceCandidate(payload.candidate as RTCIceCandidateInit)
        ); return;
      }
      return;
    }

    if (payload.type === "offer" && isNonEmptyString(payload.from) && isObject(payload.sdp)) {
      const peer = ensureViewerPeer(payload.from);
      await peer.setRemoteDescription(new RTCSessionDescription(payload.sdp as RTCSessionDescriptionInit));
      const answer = await peer.createAnswer();
      await peer.setLocalDescription(answer);
      sendSignal({ type: "answer", to: payload.from, sdp: answer });
      return;
    }
    if (payload.type === "ice" && isObject(payload.candidate)) {
      await viewerPeerRef.current?.addIceCandidate(new RTCIceCandidate(payload.candidate as RTCIceCandidateInit));
    }
  }, [closeHostPeer, closeViewerPeer, createHostPeer, ensureViewerPeer, mode, sendSignal]);

  useEffect(() => {
    const ws = new WebSocket(signalUrl);
    wsRef.current = ws;
    setSignalState("connecting");
    ws.onopen = () => {
      setSignalState("connected");
      ws.send(JSON.stringify({ type: "hello", role: mode, sessionId: normalizedSessionId }));
      setStatusText(mode === "host" ? "Sinyal bağlı. Webcam başlat." : "Sinyal bağlı. Host bekleniyor.");
    };
    ws.onmessage = (e) => { if (typeof e.data === "string") void handleSignalMessage(e.data); };
    ws.onerror = () => setErrorText("Sinyal bağlantısı kurulamadı. `npm run signal` çalıştırın.");
    ws.onclose = () => { if (wsRef.current === ws) { wsRef.current = null; setSignalState("disconnected"); } };
    return () => ws.close();
  }, [handleSignalMessage, mode, normalizedSessionId, signalUrl]);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    params.set("mode", mode); params.set("session", normalizedSessionId);
    window.history.replaceState({}, "", `${window.location.pathname}?${params.toString()}`);
  }, [mode, normalizedSessionId]);

  useEffect(() => {
    if (mode === "viewer") { closeAllHostPeers(); stopCamera(); return; }
    closeViewerPeer(); setRemoteStream(null);
  }, [closeAllHostPeers, closeViewerPeer, mode, stopCamera]);

  useEffect(() => () => {
    closeAllHostPeers(); closeViewerPeer();
    localStreamRef.current?.getTracks().forEach((t) => t.stop());
  }, [closeAllHostPeers, closeViewerPeer]);

  const copyViewerLink = useCallback(async () => {
    try { await navigator.clipboard.writeText(viewerLink); setStatusText("Link kopyalandı."); }
    catch { setErrorText("Kopyalanamadı, elle kopyalayın."); }
  }, [viewerLink]);

  const signalBadgeClass = signalState === "connected"
    ? "bg-green-950 text-green-300 border-green-700"
    : signalState === "connecting"
    ? "bg-yellow-950 text-yellow-300 border-yellow-700"
    : "bg-slate-900 text-slate-300 border-slate-700";

  const activeStream = mode === "host" ? localStream : remoteStream;

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100">
      <main className="mx-auto w-full max-w-6xl space-y-4 px-4 py-4">
        <header className="rounded-xl border border-slate-700 bg-slate-900/70 p-4">
          <h1 className="text-lg font-bold text-cyan-300">Quest3 / Tablet Stereo Webcam</h1>
          <div className="mt-2 flex flex-wrap gap-2 text-xs">
            <span className={cn("rounded border px-2 py-1", signalBadgeClass)}>
              {signalState === "connected" ? "Sinyal: Bağlı" : signalState === "connecting" ? "Sinyal: Bağlanıyor" : "Sinyal: Kapalı"}
            </span>
            <span className="rounded border border-slate-700 bg-slate-900 px-2 py-1">Session: {normalizedSessionId}</span>
            <span className="rounded border border-slate-700 bg-slate-900 px-2 py-1">Viewer: {viewerCount}</span>
            <span className="rounded border border-slate-700 bg-slate-900 px-2 py-1 font-mono">
              {laptopIp} → {tabletIp}:{UDP_PORT}
            </span>
          </div>
        </header>

        {/* Sistem Durum Paneli */}
        <SystemStatusPanel
          status={sysStatus}
          laptopIp={laptopIp}
          tabletIp={tabletIp}
          udpPort={UDP_PORT}
          onLaptopIpChange={setLaptopIp}
          onTabletIpChange={setTabletIp}
          onTestStream={() => void startCamera()}
          onStopStream={stopCamera}
          streamActive={!!localStream}
        />

        <section className="grid gap-4 lg:grid-cols-2">
          <div className="space-y-3 rounded-xl border border-slate-700 bg-slate-900/70 p-4">
            <div>
              <p className="mb-2 text-xs font-semibold uppercase text-slate-400">Mod</p>
              <div className="flex gap-2">
                {(["host", "viewer"] as Mode[]).map((m) => (
                  <button key={m} onClick={() => setMode(m)}
                    className={cn("rounded px-3 py-2 text-sm font-semibold",
                      mode === m ? "bg-cyan-600 text-white" : "border border-slate-700 bg-slate-900 text-slate-300")}>
                    {m === "host" ? "Host (Laptop)" : "Viewer (Tablet/Quest)"}
                  </button>
                ))}
              </div>
            </div>
            <label className="block text-sm">
              <span className="mb-1 block text-slate-300">Session Kodu</span>
              <input value={sessionId} onChange={(e) => setSessionId(e.target.value.toUpperCase())}
                className="w-full rounded border border-slate-700 bg-slate-950 px-3 py-2 text-sm outline-none ring-cyan-500 focus:ring" />
            </label>
            <label className="block text-sm">
              <span className="mb-1 block text-slate-300">Sinyal Sunucusu</span>
              <input value={signalUrl} onChange={(e) => setSignalUrl(e.target.value.trim())}
                className="w-full rounded border border-slate-700 bg-slate-950 px-3 py-2 text-sm outline-none ring-cyan-500 focus:ring" />
            </label>
            <div className="rounded border border-slate-700 bg-slate-950 p-3 text-xs">
              <p className="font-semibold text-slate-200 mb-1">Viewer Link:</p>
              <p className="break-all font-mono text-cyan-300">{viewerLink}</p>
              <button onClick={() => void copyViewerLink()}
                className="mt-2 rounded bg-cyan-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-cyan-500">
                Kopyala
              </button>
            </div>
            {mode === "host" && (
              <div className="flex gap-2">
                <button onClick={() => void startCamera()}
                  className="rounded bg-emerald-600 px-3 py-2 text-sm font-semibold text-white hover:bg-emerald-500">
                  Webcam Başlat
                </button>
                <button onClick={stopCamera}
                  className="rounded bg-rose-600 px-3 py-2 text-sm font-semibold text-white hover:bg-rose-500">
                  Durdur
                </button>
              </div>
            )}
          </div>

          <div className="space-y-3 rounded-xl border border-slate-700 bg-slate-900/70 p-4 text-sm">
            <div>
              <p className="text-xs font-semibold uppercase text-slate-400">Durum</p>
              <p className="mt-1 rounded border border-slate-700 bg-slate-950 px-3 py-2 text-slate-200">{statusText}</p>
            </div>
            {errorText && <div className="rounded border border-rose-700 bg-rose-950/40 px-3 py-2 text-rose-200">{errorText}</div>}
            <div className="rounded border border-slate-700 bg-slate-950 p-3 text-xs text-slate-300">
              <p className="font-semibold text-slate-200 mb-2">Başlangıç Adımları</p>
              <ol className="list-decimal pl-5 space-y-1">
                <li><code className="text-cyan-300">npm run signal</code> → sinyal sunucu</li>
                <li><code className="text-cyan-300">npm run dev</code> → web arayüz</li>
                <li>Laptop'ta Host modunda webcam başlat</li>
                <li>Tablette Viewer linkini aç</li>
                <li>Shift ve Zoom kaydırıcılarla 3D ayarla</li>
              </ol>
            </div>
          </div>
        </section>

        <section className="space-y-4 rounded-xl border border-slate-700 bg-slate-900/60 p-4">
          <StereoViewport
            stream={activeStream}
            title={mode === "host" ? "Host Stereo Preview" : "Viewer Stereo Preview"}
            emptyText={mode === "host" ? "Webcam henüz başlatılmadı." : "Host görüntüsü bekleniyor."}
            shiftPx={eyeShiftPx} zoom={eyeZoom} mirror={mode === "host"}
          />
          <div className="grid gap-4 md:grid-cols-2">
            <label className="text-sm">
              <span className="mb-1 block text-slate-300">Eye Shift: {eyeShiftPx}px</span>
              <input type="range" min={0} max={48} value={eyeShiftPx}
                onChange={(e) => setEyeShiftPx(Number(e.target.value))} className="w-full" />
            </label>
            <label className="text-sm">
              <span className="mb-1 block text-slate-300">Zoom: {eyeZoom.toFixed(2)}x</span>
              <input type="range" min={1} max={1.4} step={0.01} value={eyeZoom}
                onChange={(e) => setEyeZoom(Number(e.target.value))} className="w-full" />
            </label>
          </div>
        </section>
      </main>
    </div>
  );
}
