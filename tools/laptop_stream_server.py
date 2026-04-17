#!/usr/bin/env python3
"""
laptop_stream_server.py
=======================
USB kamerayı UDP üzerinden WiFi'ye yayınlar.
Godot NetworkReceiver ile uyumlu protokol: ham JPEG byte gönderir.

Kullanım:
    python3 laptop_stream_server.py --device /dev/video0 --host 0.0.0.0 --port 5000

Tablet/telefon IP'sini --target ile belirt:
    python3 laptop_stream_server.py --target 192.168.1.105 --port 5000
"""

import argparse
import socket
import sys
import time

try:
    import cv2
except ImportError:
    print("HATA: opencv-python kurulu değil.")
    print("Kur: pip3 install opencv-python")
    sys.exit(1)


def stream(device: int, target_ip: str, port: int, fps: int, quality: int):
    cap = cv2.VideoCapture(device)

    if not cap.isOpened():
        print(f"HATA: Kamera açılamadı: /dev/video{device}")
        print("Kameraları listele: v4l2-ctl --list-devices")
        sys.exit(1)

    cap.set(cv2.CAP_PROP_FPS, fps)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    frame_interval = 1.0 / fps
    frame_count = 0

    print(f"[Stream] Başladı → {target_ip}:{port} | FPS:{fps} | Kalite:{quality}")
    print("[Stream] Durdurmak için Ctrl+C")

    try:
        while True:
            t0 = time.time()
            ret, frame = cap.read()

            if not ret:
                print("UYARI: Frame alınamadı, yeniden deneniyor...")
                time.sleep(0.1)
                continue

            # JPEG encode
            encode_params = [cv2.IMWRITE_JPEG_QUALITY, quality]
            _, jpeg_data = cv2.imencode('.jpg', frame, encode_params)
            data = jpeg_data.tobytes()

            # UDP gönder (65507 byte limit — büyük frame'leri böl)
            MAX_UDP = 60000
            if len(data) <= MAX_UDP:
                sock.sendto(data, (target_ip, port))
            else:
                # Kaliteyi düşür ve tekrar dene
                encode_params = [cv2.IMWRITE_JPEG_QUALITY, 50]
                _, jpeg_data = cv2.imencode('.jpg', frame, encode_params)
                sock.sendto(jpeg_data.tobytes(), (target_ip, port))

            frame_count += 1
            if frame_count % 30 == 0:
                print(f"[Stream] {frame_count} frame | {len(data)/1024:.1f}KB")

            # FPS sınırla
            elapsed = time.time() - t0
            sleep_time = frame_interval - elapsed
            if sleep_time > 0:
                time.sleep(sleep_time)

    except KeyboardInterrupt:
        print("\n[Stream] Durduruldu.")
    finally:
        cap.release()
        sock.close()


def main():
    parser = argparse.ArgumentParser(description="USB Kamera → UDP Stream")
    parser.add_argument("--device", type=int, default=0, help="Kamera index (varsayılan: 0)")
    parser.add_argument("--target", type=str, default="192.168.1.105",
                        help="Hedef IP (tablet/telefon)")
    parser.add_argument("--port", type=int, default=5000)
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--quality", type=int, default=75,
                        help="JPEG kalitesi 1-100 (düşük = daha az gecikme)")
    args = parser.parse_args()

    print(f"Kamera: /dev/video{args.device}")
    print(f"Hedef: {args.target}:{args.port}")
    stream(args.device, args.target, args.port, args.fps, args.quality)


if __name__ == "__main__":
    main()
