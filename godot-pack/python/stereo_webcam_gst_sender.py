#!/usr/bin/env python3
"""
stereo_webcam_gst_sender.py - MJPEG modunda çalışır
Godot GDScript JPEG decode eder, H264 için MediaCodec plugin gerekir.
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
    print(f"[Sender] HATA: GStreamer Python bağlantısı yok: {exc}")
    sys.exit(1)


def build_mjpeg_pipeline(device: str, host: str, port: int,
                          width: int, height: int, fps: int, quality: int) -> str:
    return (
        f"v4l2src device={device} do-timestamp=true ! "
        "videoconvert ! videoscale ! videorate ! "
        f"video/x-raw,width={width},height={height},framerate={fps}/1 ! "
        f"jpegenc quality={quality} ! "
        "rtpjpegpay pt=26 mtu=60000 ! "
        f"udpsink host={host} port={port} sync=false async=false"
    )


def build_test_mjpeg_pipeline(host: str, port: int,
                               width: int, height: int, fps: int) -> str:
    return (
        f"videotestsrc pattern=smpte is-live=true ! "
        "videoconvert ! videorate ! videoscale ! "
        f"video/x-raw,width={width},height={height},framerate={fps}/1 ! "
        "jpegenc quality=75 ! "
        "rtpjpegpay pt=26 mtu=60000 ! "
        f"udpsink host={host} port={port} sync=false async=false"
    )


def build_h264_pipeline(device: str, host: str, port: int,
                         width: int, height: int, fps: int, bitrate: int) -> str:
    return (
        f"v4l2src device={device} do-timestamp=true io-mode=mmap ! "
        "videoconvert ! videoscale ! videorate ! "
        f"video/x-raw,width={width},height={height},framerate={fps}/1,format=I420 ! "
        f"x264enc tune=zerolatency speed-preset=ultrafast bitrate={bitrate} "
        f"key-int-max={fps} bframes=0 rc-lookahead=0 ! "
        "rtph264pay pt=96 config-interval=1 mtu=1400 ! "
        f"udpsink host={host} port={port} sync=false async=false"
    )


def build_test_h264_pipeline(host: str, port: int,
                              width: int, height: int, fps: int, bitrate: int) -> str:
    return (
        f"videotestsrc pattern=smpte is-live=true ! "
        "videoconvert ! videorate ! videoscale ! "
        f"video/x-raw,width={width},height={height},framerate={fps}/1,format=I420 ! "
        f"x264enc tune=zerolatency speed-preset=ultrafast bitrate={bitrate} "
        f"key-int-max={fps} bframes=0 ! "
        "rtph264pay pt=96 config-interval=1 mtu=1400 ! "
        f"udpsink host={host} port={port} sync=false async=false"
    )


class StereoGstSender:
    def __init__(self, args):
        self.args = args
        self.pipeline = None
        self.loop = None
        self._running = False
        self._stats_start = time.time()

    def _choose_pipeline(self) -> str:
        a = self.args
        # MJPEG modu (varsayılan - Godot GDScript ile uyumlu)
        if a.test and not a.h264:
            print("[Sender] TEST MODU: MJPEG (Godot uyumlu)")
            return build_test_mjpeg_pipeline(a.host, a.port, a.width, a.height, a.fps)

        if a.test and a.h264:
            print("[Sender] TEST MODU: H264 (MediaCodec plugin gerekir)")
            return build_test_h264_pipeline(a.host, a.port, a.width, a.height, a.fps, a.bitrate)

        if a.h264:
            print("[Sender] H264 modu (MediaCodec plugin gerekir)")
            return build_h264_pipeline(a.device, a.host, a.port,
                                        a.width, a.height, a.fps, a.bitrate)

        # Varsayılan: MJPEG
        print("[Sender] MJPEG modu (Godot GDScript uyumlu, plugin gerekmez)")
        return build_mjpeg_pipeline(a.device, a.host, a.port,
                                     a.width, a.height, a.fps, a.quality)

    def on_bus_message(self, _bus, message):
        t = message.type
        if t == Gst.MessageType.ERROR:
            err, dbg = message.parse_error()
            print(f"[Sender] HATA: {err}")
            if dbg:
                print(f"  Detay: {dbg}")
            self.stop()
        elif t == Gst.MessageType.EOS:
            print("[Sender] Stream sona erdi")
            self.stop()
        elif t == Gst.MessageType.STATE_CHANGED:
            if message.src == self.pipeline:
                _, new, _ = message.parse_state_changed()
                if new == Gst.State.PLAYING:
                    print("[Sender] ✓ PLAYING")
        elif t == Gst.MessageType.WARNING:
            w, _ = message.parse_warning()
            print(f"[Sender] Uyarı: {w}")

    def start(self) -> bool:
        Gst.init(None)
        pipeline_str = self._choose_pipeline()

        print(f"\n[Sender] Pipeline:")
        for part in pipeline_str.split("!"):
            print(f"  {part.strip()} !")
        print()

        try:
            self.pipeline = Gst.parse_launch(pipeline_str)
        except Exception as exc:
            print(f"[Sender] Pipeline hatası: {exc}")
            return False

        bus = self.pipeline.get_bus()
        bus.add_signal_watch()
        bus.connect("message", self.on_bus_message)

        ret = self.pipeline.set_state(Gst.State.PLAYING)
        if ret == Gst.StateChangeReturn.FAILURE:
            print("[Sender] PLAYING durumuna geçilemedi")
            print(f"  Webcam: {self.args.device}")
            print(f"  Test için: python3 {sys.argv[0]} --host {self.args.host} --test")
            self.pipeline.set_state(Gst.State.NULL)
            self.pipeline = None
            return False

        self.loop = GLib.MainLoop()
        self._running = True
        a = self.args
        codec = "H264" if a.h264 else "MJPEG"
        print(f"[Sender] ✓ BAŞLADI")
        print(f"  Hedef:  {a.host}:{a.port}")
        print(f"  Boyut:  {a.width}x{a.height} @ {a.fps}fps")
        print(f"  Codec:  {codec}")
        print(f"  Kaynak: {'TEST' if a.test else a.device}")
        print(f"\n  Durdurmak: Ctrl+C\n")
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


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Stereo webcam GStreamer sender (MJPEG varsayılan)"
    )
    parser.add_argument("--host", required=False, default="")
    parser.add_argument("--port", type=int, default=5010)
    parser.add_argument("--device", default="/dev/video0")
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=480)
    parser.add_argument("--fps", type=int, default=15)
    parser.add_argument("--quality", type=int, default=60, help="MJPEG kalite 1-100")
    parser.add_argument("--bitrate", type=int, default=2000, help="H264 kbps")
    parser.add_argument("--test", action="store_true", help="videotestsrc kullan")
    parser.add_argument("--h264", action="store_true", help="H264 kullan (MediaCodec gerekir)")
    parser.add_argument("--list-devices", action="store_true")
    args = parser.parse_args()

    if args.list_devices:
        import glob
        print("Video cihazları:", sorted(glob.glob("/dev/video*")))
        return 0

    if not args.host:
        parser.error("--host gerekli")

    sender = StereoGstSender(args)
    if not sender.start():
        return 1

    signal.signal(signal.SIGINT, lambda *_: sender.stop())
    signal.signal(signal.SIGTERM, lambda *_: sender.stop())
    sender.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
