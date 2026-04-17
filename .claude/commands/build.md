# Build ve Deploy Komutları

## Ön Koşul Kontrol
```bash
godot --version 2>/dev/null || echo "Godot kurulu değil"
adb devices
java -version 2>&1 | head -1
```

## Godot APK Build
```bash
cd /home/bnfnc/Projects/Quest3/godot-pack
godot --headless --export-debug "Android" \
  android/build/outputs/apk/debug/Quest3Debug.apk 2>&1 | tail -20
```

## Tablet'e Yükle ve Başlat
```bash
adb install -r godot-pack/android/build/outputs/apk/debug/Quest3Debug.apk
adb shell am start -n com.godot.game/.GodotApp
sleep 3
adb logcat -c
adb logcat -v time 2>/dev/null | grep -E "ExtReceiver|VideoMesh|ExternalTexture|ERROR" &
```

## APK Var mı Kontrol
```bash
adb shell pm list packages | grep godot
ls -lh godot-pack/android/build/outputs/apk/debug/ 2>/dev/null || echo "APK yok"
```

## Uygulamayı Durdur
```bash
adb shell am force-stop com.godot.game
```

## Godot Export Template Kontrol
```bash
ls ~/.local/share/godot/export_templates/ 2>/dev/null || \
  echo "Export template yok - Godot Editor'den indir"
```
