# Quest3 Stereo Camera System

## PROJE AMACI
Robot kamerasından ExternalTexture ile sıfır gecikmeli görüntü alıp
Quest3/tablet'e WiFi üzerinden 3D stereo iletmek.
Bomba imha uzmanı VR'da robotu görerek bomba incelemesi yapar.

## AĞ
- Laptop: 192.168.2.207 (Ubuntu 22 TR, /home/bnfnc)
- Tablet: 192.168.2.154 (Huawei Matepad 11, USB debug açık)
- Port: 5010 UDP H264 RTP

## MİMARİ: TEK APK
Godot APK içinde Java plugin. Ayrı APK YOK.
Laptop → GStreamer → UDP → Godot APK → ExternalTexture → 3D Stereo Mesh

## DOSYA HARİTASI
Ana sahne:        godot-pack/Main.gd
Stereo renderer:  godot-pack/addons/external_texture/VideoMeshStereo.gd
Texture receiver: godot-pack/addons/external_texture/ExternalTextureReceiver.gd
Java plugin ana:  godot-pack/android/plugins/ExternalTexture/ExternalTexturePlugin.java
Java MediaCodec:  godot-pack/android/plugins/ExternalTexture/MediaCodecReceiver.java
Plugin tanım:     godot-pack/android/plugins/ExternalTexture/ExternalTexture.gdap
Gönderici:        godot-pack/python/stereo_webcam_gst_sender.py
Web test UI:      src/App.tsx
Sinyal sunucu:    server/signaling-server.mjs

## KRİTİK EKSİKLER (Siyah Ekran Sebebi)
1. ExternalTexturePlugin.java → godot-pack/android/plugins/ altına taşınacak ve Godot plugin API ile uyumlu hale getirilecek
2. MediaCodecReceiver.java → UDP RTP al + H264 decode + SurfaceTexture'a yaz → YAZILACAK
3. ExternalTexture.gdap → Godot plugin tanım → YAZILACAK
4. ExternalTextureReceiver.gd → plugin metodları eksik, düzeltilecek

## TEST STRATEJİSİ (SIRALAMA ÖNEMLİ)
1. Web arayüz → APK gerekmez, WiFi doğrula
2. GStreamer UDP test → paket gidiyor mu
3. ADB logcat → Godot logları
4. APK build → en son, kesin çalışınca

## KOMUTLAR
Web UI: cd /home/bnfnc/Projects/Quest3 && npm run signal & npm run dev
Sender test: python3 godot-pack/python/stereo_webcam_gst_sender.py --host 192.168.2.154 --port 5010 --test
ADB logcat: adb logcat -v time | grep -E "ExtReceiver|VideoMesh|ExternalTexture|ERROR"
APK yükle: adb install -r godot-pack/android/build/outputs/apk/debug/android_debug.apk

## .claude/settings.json NOTU
sudo komutları deny listesinde. Firewall için manuel çalıştır:
sudo ufw allow 5010/udp && sudo ufw reload

## TOKEN KURALLARI
- Sadece bu dosyayı oku, tüm dosyaları okuma
- Değişen dosyayı bul, sadece onu düzelt
- --test flag önce, gerçek kamera sonra
- Web UI önce, APK en son
