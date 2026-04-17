# Godot Build Paketi (Quest3 / Tablet / Laptop)

Bu klasör, **Godot tarafı** için gereken dosyaları içerir:

- `Stereo3DViewer.cs` → stereo görüntüleyici (local kamera + network stream)
- `StereoViewScene.tscn` → örnek sahne
- `CameraExternalTextureSender.cs` → external texture (SHM) yazıcı
- `addons/gstreamer/ReceiverDisplay.gd` → GStreamerReceiver texture köprüsü
- `python/stereo_webcam_gst_sender.py` → laptop webcam UDP sender
- `python/ports_config.py` → merkezi port ayarları

> Not: `addons/gstreamer` binary dosyaları bu pakette yoktur. Mevcut çalışan Godot projenizdeki **tam** `addons/gstreamer/` klasörünü kopyalamanız gerekir.

---

## 1) Godot projeye kopyala

Yeni/var olan Godot projesine şu şekilde kopyalayın:

- `Stereo3DViewer.cs` -> `res://Stereo3DViewer.cs`
- `CameraExternalTextureSender.cs` -> `res://CameraExternalTextureSender.cs`
- `StereoViewScene.tscn` -> `res://StereoViewScene.tscn`
- `addons/gstreamer/ReceiverDisplay.gd` -> `res://addons/gstreamer/ReceiverDisplay.gd`

Ayrıca çalışan bir projeden:

- `res://addons/gstreamer/*` (tam klasör, `.gdextension`, `.so`, vb.)

---

## 2) Godot Project Settings

- `Project Settings -> Camera Feed -> Enable = ON`
- Main Scene: `res://StereoViewScene.tscn`

Android/Quest export için:
- `Project -> Export -> Android`
- INTERNET izni açık olmalı (network stream için)

---

## 3) Modlar

### A) Local webcam test (Laptop)

`StereoViewScene.tscn` node inspector:
- `UseNetworkStreamSource = false`
- `SameCameraStereoMode = true`
- `StartOnReady = true`

F5/F6 ile çalıştır.

### B) WiFi stream (Laptop -> Tablet/Quest)

Receiver (Tablet/Quest Godot):
- `UseNetworkStreamSource = true`
- `NetworkFeedRectPath = NetworkFeedSource`
- `NetworkReceiverNodePath = GStreamerReceiver`
- `GStreamerReceiver.port = 5010`

Sender (Laptop):

```bash
python3 python/stereo_webcam_gst_sender.py --device /dev/video0 --host <TABLET_OR_QUEST_IP> --port 5010
```

---

## 4) External Texture (SHM)

`CameraExternalTextureSender.cs` bir node'a takılır:
- `AutoStart = true`
- `CameraIndex = 0`
- `Width=1280, Height=720`

Çalışınca `/dev/shm/godot_ext_frame_1280x720` dosyasına frame yazar.
Bu dosya Python AI pipeline tarafından okunabilir.

---

## 5) Ubuntu 22 hızlı kontrol

```bash
v4l2-ctl --list-devices
gst-launch-1.0 v4l2src device=/dev/video0 ! videoconvert ! autovideosink
```

Eğer görüntü yoksa farklı device (`/dev/video2` vb.) deneyin.

---

## 6) Bu repo hakkında

Kökteki React/Vite uygulaması web testi içindir.
**Godot build alacaksanız bu klasördeki dosyaları Godot projesine taşıyarak ilerleyin.**
