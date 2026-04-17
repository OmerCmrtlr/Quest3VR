# Stream Test Komutları

## 30 Saniye Teşhis
```bash
echo "=GStreamer=" && gst-launch-1.0 --version | head -1
echo "=Kamera=" && ls /dev/video* 2>/dev/null || echo "YOK"
echo "=ADB=" && adb devices
echo "=Tablet ping=" && ping -c 2 192.168.2.154 | tail -2
```

## Test 1: GStreamer Kamerasız (En Önce)
```bash
gst-launch-1.0 videotestsrc pattern=smpte is-live=true ! \
  videoconvert ! videorate ! videoscale ! \
  video/x-raw,width=1280,height=720,framerate=30/1,format=I420 ! \
  x264enc tune=zerolatency speed-preset=ultrafast bitrate=2000 key-int-max=30 ! \
  rtph264pay pt=96 config-interval=1 mtu=1400 ! \
  udpsink host=192.168.2.154 port=5010 sync=false
```

## Test 2: Laptop Alıcı Sim (Tablet olmadan UDP test)
```bash
# Terminal 1 - Gönder
gst-launch-1.0 videotestsrc pattern=smpte is-live=true ! \
  videoconvert ! video/x-raw,width=640,height=480,framerate=10/1,format=I420 ! \
  x264enc tune=zerolatency speed-preset=ultrafast bitrate=500 ! \
  rtph264pay pt=96 config-interval=1 ! \
  udpsink host=127.0.0.1 port=5010 sync=false

# Terminal 2 - Al ve göster
gst-launch-1.0 udpsrc port=5010 \
  caps="application/x-rtp,media=video,encoding-name=H264,payload=96" ! \
  rtph264depay ! avdec_h264 ! videoconvert ! autovideosink
```

## Test 3: UDP Paket Gidiyor mu
```bash
sudo tcpdump -i any udp port 5010 -c 20 -q
```

## Test 4: ADB Logcat
```bash
adb logcat -c
adb logcat -v time 2>/dev/null | grep -E "\[ExtReceiver\]|\[VideoMesh\]|ExternalTexture|MediaCodec|ERROR"
```

## Test 5: Firewall (Manuel - sudo deny listede)
```bash
sudo ufw allow 5010/udp && sudo ufw reload
sudo ufw status | grep 5010
```

## GStreamer Kurulum (Eksikse)
```bash
sudo apt install -y \
  gstreamer1.0-tools gstreamer1.0-plugins-base \
  gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
  gstreamer1.0-plugins-ugly gstreamer1.0-libav \
  python3-gi python3-gst-1.0
```
