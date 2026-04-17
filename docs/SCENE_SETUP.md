# StereoViewScene.tscn Yapısı

Bu dosya Godot Editor'de oluşturulmalıdır.
Aşağıdaki node hiyerarşisini kur:

```
StereoViewScene (Node3D)          ← Stereo3DViewer.cs attach et
├── Camera3D                       ← Position: (0, 0, 2)
├── LeftViewport (SubViewport)     ← Size: (960, 1080) örn.
├── RightViewport (SubViewport)    ← Size: (960, 1080) örn.
├── StereoMesh (MeshInstance3D)   ← QuadMesh, scale (3.2, 1.8, 1)
│   └── [Material: shader ile]
└── NetworkReceiver (Node)         ← NetworkReceiver.cs attach et
```

## Node Ayarları

### SubViewport (sol ve sağ, aynı ayarlar)
- Render Target Mode: Always
- Update Mode: Always
- Size: ekran_x/2, ekran_y

### MeshInstance3D
- Mesh: QuadMesh
- Position: (0, 0, 0)
- Scale: (3.2, 1.8, 1) — 16:9 oran

### Camera3D
- Position: (0, 0, 2)
- FOV: 90 (Quest 3 için ayarla)

## Editor'de Sahne Oluşturma Adımları
1. Yeni sahne → Node3D seç → "StereoViewScene" olarak kaydet
2. Node3D'ye Stereo3DViewer.cs script'i ekle
3. Child node'ları yukarıdaki hiyerarşide ekle
4. Export değişkenlerini Inspector'da ayarla (IP, Port)
5. scenes/StereoViewScene.tscn olarak kaydet
