#!/usr/bin/env python3
"""
stereo_webcam_gst_sender.py - Laptop webcam -> Android tablet/Quest3
Zero-latency H264 RTP UDP stream

Kullanım:
  python3 stereo_webcam_gst_sender.py --host 192.168.1.55 --port 5010
  python3 stereo_webcam_gst_sender.py --host 192.168.1.55 --port 5010 --device /dev/video2
  python3 stereo_webcam_gst_sender.py --host 192.168.1.55 --port 5010 --test  # renk çubuğu test
"""

import argparse
import signal
import sys
import time

try:
    import gi
    gi.require_version("Gst", "1.0")
    gi.require_version("GLib", "2.0")
    from gi.repository import Gst, GLib
except Exception as exc:
    print(f"[Sender] HATA: GStreamer Python bağlantısı yok")
    print(f"  {exc}")
    print()
    print("Kurulum (Ubuntu/Debian):")
    print("  sudo apt install python3-gi python3-gst-1.0 \\")
    print("    gstreamer1.0-tools gstreamer1.0-plugins-base \\")
    print("    gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \\")
    print("    gstreamer1.0-plugins-ugly gstreamer1.0-libav")
    sys.exit(1)


# ---------------------------------------------------------------------------
# Pipeline Fabrikası
# ---------------------------------------------------------------------------

def build_h264_pipeline(device: str, host: str, port: int,
                         width: int, height: int, fps: int,
                         bitrate: int, latency_ms: int) -> str:
    """
    v4l2src -> videoconvert -> x264enc (zerolatency) -> RTP -> UDP

    latency_ms: encoder latency hedefi (ms). 0 = en düşük latency
    """
    return (
        # Kaynak
        f"v4l2src device={device} do-timestamp=true io-mode=mmap ! "
        "videoconvert ! videoscale ! videorate ! "
        f"video/x-raw,width={width},height={height},"
        f"framerate={fps}/1,format=I420 ! "

        # Encoder - zero latency
        f"x264enc "
        f"tune=zerolatency "
        f"speed-preset=ultrafast "
        f"bitrate={bitrate} "
        f"key-int-max={fps} "    # Her saniye keyframe
        f"bframes=0 "            # B-frame yok = düşük latency
        f"rc-lookahead=0 "
        f"sliced-threads=true "
        f"! "

        # RTP paketleme
        "rtph264pay pt=96 config-interval=1 mtu=1400 ! "

        # UDP gönder
        f"udpsink host={host} port={port} sync=false async=false"
    )


def build_mjpeg_pipeline(device: str, host: str, port: int,
                          width: int, height: int, fps: int,
                          quality: int) -> str:
    """
    v4l2src -> MJPEG -> RTP -> UDP
    Daha yüksek latency ama daha basit decode
    """
    return (
        f"v4l2src device={device} do-timestamp=true ! "
        "videoconvert ! videoscale ! videorate ! "
        f"video/x-raw,width={width},height={height},framerate={fps}/1 ! "
        f"jpegenc quality={quality} ! "
        "rtpjpegpay pt=26 ! "
        f"udpsink host={host} port={port} sync=false async=false"
    )


def build_test_pipeline(host: str, port: int,
                         width: int, height: int, fps: int,
                         bitrate: int) -> str:
    """
    videotestsrc (SMPTE renk çubuğu) -> H264 -> UDP
    Webcam olmadan pipeline testi için
    """
    return (
        f"videotestsrc pattern=smpte is-live=true ! "
        "videoconvert ! videorate ! videoscale ! "
        f"video/x-raw,width={width},height={height},"
        f"framerate={fps}/1,format=I420 ! "
        f"x264enc tune=zerolatency speed-preset=ultrafast "
        f"bitrate={bitrate} key-int-max={fps} bframes=0 ! "
        "rtph264pay pt=96 config-interval=1 mtu=1400 ! "
        f"udpsink host={host} port={port} sync=false async=false"
    )


# ---------------------------------------------------------------------------

class StereoGstSender:

    def __init__(self, args):
        self.args     = args
        self.pipeline = None
        self.loop     = None
        self._running = False
        self._stats_start = time.time()

    def _choose_pipeline(self) -> str:
        a = self.args
        if a.test:
            print("[Sender] TEST MODU: videotestsrc SMPTE pattern")
            return build_test_pipeline(a.host, a.port, a.width, a.height, a.fps, a.bitrate)

        if a.mjpeg:
            print("[Sender] MJPEG modu")
            return build_mjpeg_pipeline(a.device, a.host, a.port,
                                         a.width, a.height, a.fps, a.quality)

        return build_h264_pipeline(a.device, a.host, a.port,
                                    a.width, a.height, a.fps,
                                    a.bitrate, a.latency)

    def on_bus_message(self, _bus, message):
        t = message.type
        if t == Gst.MessageType.ERROR:
            err, dbg = message.parse_error()
            print(f"[Sender] GST HATA: {err}")
            if dbg:
                print(f"           Detay: {dbg}")
            self.stop()
        elif t == Gst.MessageType.EOS:
            print("[Sender] Stream sona erdi")
            self.stop()
        elif t == Gst.MessageType.STATE_CHANGED:
            if message.src == self.pipeline:
                old, new, pending = message.parse_state_changed()
                if new == Gst.State.PLAYING:
                    print("[Sender] ✓ PLAYING durumunda")
        elif t == Gst.MessageType.WARNING:
            w, d = message.parse_warning()
            print(f"[Sender] uyarı: {w}")

    def start(self) -> bool:
        Gst.init(None)

        pipeline_str = self._choose_pipeline()
        print(f"\n[Sender] Pipeline:")
        # Satır satır yaz - uzun pipeline okunabilsin
        for part in pipeline_str.split("!"):
            print(f"    {part.strip()} !")
        print()

        try:
            self.pipeline = Gst.parse_launch(pipeline_str)
        except Exception as exc:
            print(f"[Sender] Pipeline parse hatası: {exc}")
            print()
            print("Kontrol et:")
            print("  gst-launch-1.0 " + pipeline_str)
            return False

        bus = self.pipeline.get_bus()
        bus.add_signal_watch()
        bus.connect("message", self.on_bus_message)

        ret = self.pipeline.set_state(Gst.State.PLAYING)
        if ret == Gst.StateChangeReturn.FAILURE:
            print("[Sender] HATA: PLAYING durumuna geçilemedi")
            print()
            print("Olası sebepler:")
            print(f"  - Webcam {self.args.device} bulunamıyor")
            print(f"  - x264enc kurulu değil (sudo apt install gstreamer1.0-plugins-ugly)")
            print(f"  - Çözünürlük {self.args.width}x{self.args.height} desteklenmiyor")
            print()
            print("Test için:")
            print(f"  python3 {sys.argv[0]} --host {self.args.host} --port {self.args.port} --test")
            self.pipeline.set_state(Gst.State.NULL)
            self.pipeline = None
            return False

        self.loop     = GLib.MainLoop()
        self._running = True

        a = self.args
        print(f"[Sender] ✓ BAŞLADI")
        print(f"  Hedef:      {a.host}:{a.port}")
        print(f"  Çözünürlük: {a.width}x{a.height} @ {a.fps}fps")
        print(f"  Bitrate:    {a.bitrate} kbps")
        print(f"  Kaynak:     {'TEST' if a.test else a.device}")
        print(f"\n  Durdurmak için Ctrl+C\n")

        return True

    def run(self):
        if self.loop:
            try:
                self.loop.run()
            except KeyboardInterrupt:
                pass

    def stop(self):
        if not self._running:
            return
        self._running = False

        if self.pipeline:
            self.pipeline.set_state(Gst.State.NULL)
            self.pipeline = None

        if self.loop and self.loop.is_running():
            self.loop.quit()

        elapsed = time.time() - self._stats_start
        print(f"\n[Sender] Durduruldu. Süre: {elapsed:.1f}s")


# ---------------------------------------------------------------------------
# Cihaz listele
# ---------------------------------------------------------------------------

def list_devices():
    import subprocess, re
    print("Mevcut video cihazları:")
    try:
        result = subprocess.run(
            ["v4l2-ctl", "--list-devices"],
            capture_output=True, text=True, timeout=3
        )
        print(result.stdout)
    except FileNotFoundError:
        print("  v4l2-ctl bulunamadı (sudo apt install v4l-utils)")
    except Exception as e:
        print(f"  Hata: {e}")

    # /dev/video* listele
    import glob
    devices = sorted(glob.glob("/dev/video*"))
    if devices:
        print("  /dev/video* cihazlar:", ", ".join(devices))


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Stereo webcam GStreamer H264 UDP sender",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Örnekler:
  # Tablet'e H264 stream gönder
  python3 stereo_webcam_gst_sender.py --host 192.168.1.55 --port 5010

  # Test modu (webcam olmadan)
  python3 stereo_webcam_gst_sender.py --host 192.168.1.55 --port 5010 --test

  # Video2 cihazı, 1080p
  python3 stereo_webcam_gst_sender.py --host 192.168.1.55 --device /dev/video2 --width 1920 --height 1080

  # MJPEG modu (daha basit, daha yüksek latency)
  python3 stereo_webcam_gst_sender.py --host 192.168.1.55 --mjpeg

  # Cihazları listele
  python3 stereo_webcam_gst_sender.py --list-devices
        """
    )

    parser.add_argument("--host",    required=False, default="",
                        help="Tablet/Quest IP adresi (zorunlu, --list-devices hariç)")
    parser.add_argument("--port",    type=int,  default=5010)
    parser.add_argument("--device",  default="/dev/video0")
    parser.add_argument("--width",   type=int,  default=1280)
    parser.add_argument("--height",  type=int,  default=720)
    parser.add_argument("--fps",     type=int,  default=30)
    parser.add_argument("--bitrate", type=int,  default=3000,  help="kbps (H264)")
    parser.add_argument("--latency", type=int,  default=0,     help="encoder latency ms")
    parser.add_argument("--quality", type=int,  default=75,    help="MJPEG kalite (0-100)")
    parser.add_argument("--test",    action="store_true",      help="videotestsrc kullan")
    parser.add_argument("--mjpeg",   action="store_true",      help="MJPEG encode")
    parser.add_argument("--list-devices", action="store_true")

    args = parser.parse_args()

    if args.list_devices:
        list_devices()
        return 0

    if not args.host:
        parser.error("--host gerekli (tablet IP adresi)")

    sender = StereoGstSender(args)

    if not sender.start():
        return 1

    signal.signal(signal.SIGINT,  lambda *_: sender.stop())
    signal.signal(signal.SIGTERM, lambda *_: sender.stop())

    sender.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
