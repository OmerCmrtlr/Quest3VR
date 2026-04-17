# Quest3 Stereo Sistem Referansı

## Veri Akışı
Laptop USB Webcam
  → GStreamer x264enc
  → UDP RTP port 5010
  → 192.168.2.154 (Tablet)
  → MediaCodecReceiver.java (decode)
  → SurfaceTexture (ExternalTexturePlugin.java)
  → OpenGL ES GL_TEXTURE_EXTERNAL_OES
  → ExternalTextureReceiver.gd
  → VideoMeshStereo.gd
  → Sol Mesh (shift -UV) | Sağ Mesh (shift +UV)
  → Ekranda pseudo-stereo 3D

## ExternalTexture Nasıl Çalışır
Android GL_TEXTURE_EXTERNAL_OES:
- SurfaceTexture oluştur → MediaCodec output surface olarak ver
- MediaCodec decode eder → frame SurfaceTexture'a düşer
- onFrameAvailable callback → mFrameAvailable = true
- Godot render thread'de updateTexImage() çağır
- OpenGL texture ID Godot'a ver → ExternalTexture.set_external_buffer_id(gl_id)
- CPU kopyası YOK → sıfır gecikme

## Godot Plugin Sistemi (Godot 4 Android)
1. .gdap dosyası → plugin'i tanımlar
2. Java class → GodotPlugin extend eder
3. @UsedByGodot annotation → GDScript'ten çağrılabilir metodlar
4. Engine.get_singleton("PluginAdı") → GDScript'ten erişim

## Kritik Godot 4 Plugin API
```java
// Doğru Godot 4 plugin yapısı:
public class ExternalTexturePlugin extends GodotPlugin {
    public ExternalTexturePlugin(Godot godot) { super(godot); }
    
    @Override
    public String getPluginName() { return "ExternalTexturePlugin"; }
    
    @UsedByGodot
    public int createExternalTexture() { ... }
    
    @UsedByGodot  
    public boolean updateTexture(int slot) { ... }
}
```

## Shader (VideoMeshStereo.gd içinde)
spatial shader, unshaded, cull_disabled
uniform sampler2D video_texture
Sol göz: UV shift -stereo_shift_uv
Sağ göz: UV shift +stereo_shift_uv
Zoom: UV scale zoom_uv

## Sık Hatalar
HATA: siyah ekran → plugin register değil, .gdap yanlış
HATA: ExternalTexturePlugin bulunamadı → GodotPlugin extend edilmemiş
HATA: test modu → Android değil PC, normal
HATA: MediaCodec başlatılamadı → port kapalı veya format uyumsuz
HATA: GL texture id 0 → createTexture() GL thread dışında çağrıldı

## Port/IP Referans
5010: UDP video (H264 RTP)  → tablet
8787: WebSocket sinyal      → web test
5173: Vite dev server       → web test
Laptop: 192.168.2.207
Tablet: 192.168.2.154
