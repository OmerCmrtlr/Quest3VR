# Quest3 Stereo Camera System

## PROJE AMACI
Robot kamerasından görüntü alıp Quest3/tablet'e WiFi üzerinden 3D stereo iletmek.

## AĞ
- Laptop: 192.168.2.207 (Ubuntu 22 TR)
- Tablet: 192.168.2.154 (Huawei Matepad 11, USB debug açık)
- Port: 5010 UDP MJPEG RTP (PT=26)

## KRİTİK KARAR: MJPEG KULLAN, H264 DEĞİL
- Godot GDScript Image.load_jpg_from_buffer() ile JPEG decode eder
- H264 için MediaCodec Java plugin gerekir → karmaşık, AAR build gerekir
- MJPEG: plugin yok, AAR yok, PC'de de test edilir
- Çözünürlük: 640x480 @ 15fps (UDP MTU limiti için küçük tutuldu)

## MİMARİ: TEK APK, PLUGIN YOK
Laptop → GStreamer MJPEG → UDP RTP PT=26 → Godot UDP → JPEG decode → 3D Stereo

## DOSYA HARİTASI
Ana sahne:        godot-pack/Main.gd
Stereo renderer:  godot-pack/addons/external_texture/VideoMeshStereo.gd
UDP receiver:     godot-pack/addons/external_texture/ExternalTextureReceiver.gd
Gönderici:        godot-pack/python/stereo_webcam_gst_sender.py
Web test UI:      src/App.tsx

## KOMUTLAR
### Test stream (kamerasız, MJPEG):
python3 godot-pack/python/stereo_webcam_gst_sender.py \
  --host 192.168.2.154 --port 5010 --test

### Gerçek kamera MJPEG:
python3 godot-pack/python/stereo_webcam_gst_sender.py \
  --host 192.168.2.154 --port 5010 --device /dev/video0 \
  --width 640 --height 480 --fps 15 --quality 60

### ADB logcat:
adb logcat -v time | grep -E "ExtReceiver|VideoMesh|ERROR"

### Tablet'e APK yükle:
adb install -r godot-pack/android/build/build/outputs/apk/mono/debug/android_monoDebug-signed.apk

## BUILD NOTU
Godot headless export dotnet android hatası → GUI export gerekiyor
Mevcut APK: godot-pack/android/build/build/outputs/apk/mono/debug/android_monoDebug-signed.apk

## TOKEN KURALLARI
- Sadece bu dosyayı oku
- Değişen dosyayı bul, sadece onu düzelt
- MJPEG önce, H264 ileride
