# ADB Logcat Komutları

## Bağlantı Kontrol
```bash
adb devices
adb get-state 2>/dev/null || echo "Tablet bağlı değil"
```

## Proje Logları
```bash
adb logcat -c && \
adb logcat -v time 2>/dev/null | grep -E "\[ExtReceiver\]|\[VideoMesh\]|\[Stereo\]|ExternalTexture"
```

## Tüm Hatalar
```bash
adb logcat *:E -v time 2>/dev/null | grep -v "^---"
```

## MediaCodec Logları
```bash
adb logcat -s MediaCodec:V OMXClient:V -v time
```

## FPS İzle
```bash
adb logcat -v time 2>/dev/null | grep -E "FPS|fps_updated|frame"
```

## Uygulama Başlat + Log
```bash
adb shell am force-stop com.godot.game
adb logcat -c
adb shell am start -n com.godot.game/.GodotApp
adb logcat -v time 2>/dev/null | grep -E "ExtReceiver|VideoMesh|ExternalTexture|ERROR|FATAL"
```
