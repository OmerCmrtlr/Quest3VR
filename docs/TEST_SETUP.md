# Test Kurulum Kılavuzu

## Ağ
- Laptop: 192.168.2.207 (Ubuntu 22, gönderici)
- Tablet: 192.168.2.154 (Huawei Matepad 11, alıcı)
- Port: 5010 UDP

## Aşama 1 - Web Arayüz (APK Gerekmez, İlk Test)

Terminal 1:
cd /home/bnfnc/Projects/Quest3 && npm run signal

Terminal 2:
cd /home/bnfnc/Projects/Quest3 && npm run dev

Laptop tarayıcı (Host):
http://localhost:5173/?mode=host

Tablet tarayıcı (Viewer):
http://192.168.2.207:5173/?mode=viewer&session=QUEST3

✓ Bu çalışıyorsa: WiFi, WebRTC, stereo render doğru.

## Aşama 2 - GStreamer UDP Test

Firewall (manuel):
sudo ufw allow 5010/udp && sudo ufw reload

Test stream (kamerasız):
python3 /home/bnfnc/Projects/Quest3/godot-pack/python/stereo_webcam_gst_sender.py \
  --host 192.168.2.154 --port 5010 --test

Laptop'ta UDP kontrol:
sudo tcpdump -i any udp port 5010 -c 10 -q

✓ Bu çalışıyorsa: GStreamer, UDP, network path doğru.

## Aşama 3 - Godot APK (Son Adım)

ADB bağlantı:
adb devices

APK build + yükle:
cd /home/bnfnc/Projects/Quest3/godot-pack
godot --headless --export-debug "Android" android/build/outputs/apk/debug/Quest3.apk
adb install -r android/build/outputs/apk/debug/Quest3.apk
adb shell am start -n com.godot.game/.GodotApp

Log izle:
adb logcat -v time | grep -E "ExtReceiver|VideoMesh|ExternalTexture|ERROR"

## Aşama 4 - Quest3 Geçişi
1. Quest3 WiFi'ye bağla (aynı ağ)
2. Quest3 IP: adb shell ip addr | grep wlan
3. Web arayüzünde Tablet IP alanını Quest3 IP yap
4. APK yükle: adb install -r Quest3.apk
