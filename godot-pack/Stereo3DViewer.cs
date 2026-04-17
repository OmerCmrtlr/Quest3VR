using Godot;
using System;

public partial class Stereo3DViewer : Control
{
    [ExportGroup("Camera")]
    [Export] public int LeftCameraIndex = 0;
    [Export] public int RightCameraIndex = 1;
    [Export] public bool SameCameraStereoMode = true;
    [Export] public bool MirrorLeft = false;
    [Export] public bool MirrorRight = false;
    [Export] public bool StartOnReady = true;

    [ExportGroup("Pseudo Stereo")]
    [Export] public bool EnablePseudoStereoShift = true;
    [Export] public float PseudoStereoShiftPixels = 18f;
    [Export] public float PseudoStereoZoom = 1.03f;

    [ExportGroup("Network Stream (GStreamerReceiver Texture)")]
    [Export] public bool UseNetworkStreamSource = false;
    [Export] public NodePath NetworkFeedRectPath = new NodePath("NetworkFeedSource");
    [Export] public NodePath NetworkReceiverNodePath = new NodePath("GStreamerReceiver");
    [Export] public bool AutoControlNetworkReceiver = true;
    [Export] public int NetworkNoTextureWarnFrames = 60;
    [Export] public bool AutoFallbackToLocalCameraIfNetworkMissing = true;

    [ExportGroup("Debug")]
    [Export] public bool ShowDebugInfo = true;

    private TextureRect _leftRect;
    private TextureRect _rightRect;
    private Label _debugLabel;

    private CameraTexture _leftCamTex;
    private CameraTexture _rightCamTex;

    private TextureRect _networkFeedRect;
    private Node _networkReceiverNode;

    private Shader _pseudoShader;
    private ShaderMaterial _leftMat;
    private ShaderMaterial _rightMat;

    private bool _sessionActive;
    private bool _usingLocalFallbackFromNetwork;
    private int _networkNoTextureFrames;

    private int _fpsCount;
    private int _fpsDisplay;
    private float _fpsTimer;

    private const string PSEUDO_SHADER = @"
shader_type canvas_item;
uniform float shift_uv = 0.0;
uniform float zoom_uv = 1.0;

void fragment() {
    vec2 uv = (UV - vec2(0.5)) / max(zoom_uv, 0.0001) + vec2(0.5 + shift_uv, 0.5);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        COLOR = vec4(0.0, 0.0, 0.0, 1.0);
    } else {
        COLOR = texture(TEXTURE, uv);
    }
}
";

    public override void _Ready()
    {
        CameraServer.SetMonitoringFeeds(true);
        BuildUi();
        ResolveNetworkNodes();

        if (StartOnReady)
            StartSession();
    }

    private void BuildUi()
    {
        SetAnchorsAndOffsetsPreset(LayoutPreset.FullRect);

        _leftRect = new TextureRect
        {
            Name = "LeftView",
            StretchMode = TextureRect.StretchModeEnum.KeepAspectCentered,
            AnchorLeft = 0f,
            AnchorTop = 0f,
            AnchorRight = 0.5f,
            AnchorBottom = 1f,
            FlipH = MirrorLeft,
        };
        AddChild(_leftRect);

        _rightRect = new TextureRect
        {
            Name = "RightView",
            StretchMode = TextureRect.StretchModeEnum.KeepAspectCentered,
            AnchorLeft = 0.5f,
            AnchorTop = 0f,
            AnchorRight = 1f,
            AnchorBottom = 1f,
            FlipH = MirrorRight,
        };
        AddChild(_rightRect);

        var divider = new ColorRect
        {
            Name = "Divider",
            Color = new Color(0.1f, 0.1f, 0.1f, 1f),
            AnchorLeft = 0.5f,
            AnchorTop = 0f,
            AnchorRight = 0.5f,
            AnchorBottom = 1f,
            OffsetLeft = -1f,
            OffsetRight = 1f,
        };
        AddChild(divider);

        _debugLabel = new Label
        {
            Name = "DebugLabel",
            Visible = ShowDebugInfo,
            AnchorLeft = 0f,
            AnchorTop = 0f,
            OffsetLeft = 8f,
            OffsetTop = 8f,
            OffsetRight = 540f,
            OffsetBottom = 180f,
        };
        _debugLabel.AddThemeColorOverride("font_color", new Color(1f, 1f, 0f));
        _debugLabel.AddThemeColorOverride("font_shadow_color", new Color(0f, 0f, 0f, 0.85f));
        _debugLabel.AddThemeConstantOverride("shadow_offset_x", 1);
        _debugLabel.AddThemeConstantOverride("shadow_offset_y", 1);
        AddChild(_debugLabel);
    }

    private void ResolveNetworkNodes()
    {
        _networkFeedRect = GetNodeOrNull<TextureRect>(NetworkFeedRectPath);
        _networkReceiverNode = GetNodeOrNull<Node>(NetworkReceiverNodePath);
    }

    public void StartSession()
    {
        if (_sessionActive)
            return;

        _sessionActive = true;
        _usingLocalFallbackFromNetwork = false;
        _networkNoTextureFrames = 0;

        if (UseNetworkStreamSource)
        {
            ResolveNetworkNodes();
            if (AutoControlNetworkReceiver)
                StartNetworkReceiver();
            return;
        }

        ConnectCameras();
    }

    public void StopSession()
    {
        _sessionActive = false;

        if (UseNetworkStreamSource && AutoControlNetworkReceiver)
            StopNetworkReceiver();

        _leftCamTex = null;
        _rightCamTex = null;

        if (_leftRect != null)
            _leftRect.Texture = null;
        if (_rightRect != null)
            _rightRect.Texture = null;

        foreach (var feed in CameraServer.Feeds())
        {
            try { feed.FeedIsActive = false; } catch { }
        }
    }

    private void ConnectCameras()
    {
        var feeds = CameraServer.Feeds();
        int count = feeds.Count;

        if (count == 0)
        {
            GD.PrintErr("[Stereo3D] Kamera feed bulunamadı. Project Settings > Camera Feed > Enable kontrol et.");
            return;
        }

        int leftIdx = Mathf.Clamp(LeftCameraIndex, 0, count - 1);
        int rightIdx = Mathf.Clamp(RightCameraIndex, 0, count - 1);

        bool forceSingle = SameCameraStereoMode || count == 1;
        if (forceSingle)
            rightIdx = leftIdx;

        TryActivateFeed(feeds[leftIdx]);
        if (rightIdx != leftIdx)
            TryActivateFeed(feeds[rightIdx]);

        _leftCamTex = new CameraTexture
        {
            CameraFeedId = feeds[leftIdx].GetId(),
            CameraIsActive = true,
        };

        if (rightIdx == leftIdx)
        {
            _rightCamTex = _leftCamTex;
        }
        else
        {
            _rightCamTex = new CameraTexture
            {
                CameraFeedId = feeds[rightIdx].GetId(),
                CameraIsActive = true,
            };
        }

        if (_leftRect != null)
            _leftRect.Texture = _leftCamTex;
        if (_rightRect != null)
            _rightRect.Texture = _rightCamTex;

        LeftCameraIndex = leftIdx;
        RightCameraIndex = rightIdx;

        ApplyPseudoStereo();

        GD.Print($"[Stereo3D] Sol[{leftIdx}] Sağ[{rightIdx}] bağlandı");
    }

    private static bool TryActivateFeed(CameraFeed feed)
    {
        if (feed == null)
            return false;

        try
        {
            if (!feed.FeedIsActive)
                feed.FeedIsActive = true;
            return feed.FeedIsActive;
        }
        catch
        {
            return false;
        }
    }

    private void EnsurePseudoMaterials()
    {
        if (_pseudoShader == null)
            _pseudoShader = new Shader { Code = PSEUDO_SHADER };

        if (_leftMat == null)
            _leftMat = new ShaderMaterial { Shader = _pseudoShader };

        if (_rightMat == null)
            _rightMat = new ShaderMaterial { Shader = _pseudoShader };
    }

    private void ApplyPseudoStereo()
    {
        bool usePseudo = EnablePseudoStereoShift && (_leftCamTex == _rightCamTex || SameCameraStereoMode || UseNetworkStreamSource);
        if (!usePseudo)
        {
            if (_leftRect != null) _leftRect.Material = null;
            if (_rightRect != null) _rightRect.Material = null;
            return;
        }

        EnsurePseudoMaterials();

        float panelWidth = Mathf.Max(1f, _leftRect?.Size.X ?? 1f);
        float shiftUv = PseudoStereoShiftPixels / panelWidth;

        _leftMat.SetShaderParameter("shift_uv", -shiftUv);
        _leftMat.SetShaderParameter("zoom_uv", PseudoStereoZoom);

        _rightMat.SetShaderParameter("shift_uv", shiftUv);
        _rightMat.SetShaderParameter("zoom_uv", PseudoStereoZoom);

        if (_leftRect != null)
            _leftRect.Material = _leftMat;
        if (_rightRect != null)
            _rightRect.Material = _rightMat;
    }

    private void UpdateNetworkPipeline()
    {
        if (_networkFeedRect == null)
        {
            _networkNoTextureFrames++;
            return;
        }

        var tex = _networkFeedRect.Texture;
        if (tex == null)
        {
            _networkNoTextureFrames++;

            if (AutoFallbackToLocalCameraIfNetworkMissing && _networkNoTextureFrames >= Mathf.Max(1, NetworkNoTextureWarnFrames))
            {
                if (!_usingLocalFallbackFromNetwork)
                {
                    _usingLocalFallbackFromNetwork = true;
                    ConnectCameras();
                }
            }
            return;
        }

        _networkNoTextureFrames = 0;
        _usingLocalFallbackFromNetwork = false;

        if (_leftRect != null)
            _leftRect.Texture = tex;
        if (_rightRect != null)
            _rightRect.Texture = tex;

        ApplyPseudoStereo();
    }

    private void StartNetworkReceiver()
    {
        if (_networkReceiverNode == null)
            return;

        try
        {
            if (_networkReceiverNode.HasMethod("is_receiving") && _networkReceiverNode.HasMethod("start_receiving"))
            {
                bool active = (bool)_networkReceiverNode.Call("is_receiving");
                if (!active)
                    _networkReceiverNode.Call("start_receiving");
                return;
            }

            if (_networkReceiverNode.HasMethod("is_capturing") && _networkReceiverNode.HasMethod("start_capture"))
            {
                bool active = (bool)_networkReceiverNode.Call("is_capturing");
                if (!active)
                    _networkReceiverNode.Call("start_capture");
            }
        }
        catch (Exception e)
        {
            GD.PrintErr("[Stereo3D] Network receiver start hatası: " + e.Message);
        }
    }

    private void StopNetworkReceiver()
    {
        if (_networkReceiverNode == null)
            return;

        try
        {
            if (_networkReceiverNode.HasMethod("is_receiving") && _networkReceiverNode.HasMethod("stop_receiving"))
            {
                bool active = (bool)_networkReceiverNode.Call("is_receiving");
                if (active)
                    _networkReceiverNode.Call("stop_receiving");
                return;
            }

            if (_networkReceiverNode.HasMethod("is_capturing") && _networkReceiverNode.HasMethod("stop_capture"))
            {
                bool active = (bool)_networkReceiverNode.Call("is_capturing");
                if (active)
                    _networkReceiverNode.Call("stop_capture");
            }
        }
        catch (Exception e)
        {
            GD.PrintErr("[Stereo3D] Network receiver stop hatası: " + e.Message);
        }
    }

    public override void _Process(double delta)
    {
        _fpsCount++;
        _fpsTimer += (float)delta;
        if (_fpsTimer >= 1f)
        {
            _fpsDisplay = _fpsCount;
            _fpsCount = 0;
            _fpsTimer -= 1f;
        }

        if (!_sessionActive)
        {
            UpdateDebug("DURUM: Pasif");
            return;
        }

        if (UseNetworkStreamSource)
        {
            UpdateNetworkPipeline();
            string line = _usingLocalFallbackFromNetwork
                ? "Ağ yok -> Local kamera fallback"
                : (_networkNoTextureFrames > 0 ? "Ağ frame bekleniyor" : "Ağ stream aktif");
            UpdateDebug(line);
            return;
        }

        UpdateDebug("Local kamera aktif");
    }

    private void UpdateDebug(string stateLine)
    {
        if (_debugLabel == null || !_debugLabel.Visible)
            return;

        _debugLabel.Text =
            $"FPS: {_fpsDisplay}\n" +
            $"MODE: {(UseNetworkStreamSource ? "NETWORK" : "LOCAL")}\n" +
            $"SOL: {LeftCameraIndex} SAĞ: {RightCameraIndex}\n" +
            $"STEREO_SHIFT: {PseudoStereoShiftPixels:F0}px\n" +
            stateLine + "\n" +
            "[T]=swap  [M]=sol ayna  [N]=sağ ayna  [D]=debug";
    }

    public override void _Input(InputEvent @event)
    {
        if (@event is InputEventKey { Pressed: true, Echo: false } key)
        {
            switch (key.Keycode)
            {
                case Key.T:
                    if (!UseNetworkStreamSource)
                    {
                        (LeftCameraIndex, RightCameraIndex) = (RightCameraIndex, LeftCameraIndex);
                        ConnectCameras();
                    }
                    else
                    {
                        PseudoStereoShiftPixels = -PseudoStereoShiftPixels;
                        ApplyPseudoStereo();
                    }
                    break;
                case Key.M:
                    MirrorLeft = !MirrorLeft;
                    if (_leftRect != null) _leftRect.FlipH = MirrorLeft;
                    break;
                case Key.N:
                    MirrorRight = !MirrorRight;
                    if (_rightRect != null) _rightRect.FlipH = MirrorRight;
                    break;
                case Key.D:
                    ShowDebugInfo = !ShowDebugInfo;
                    if (_debugLabel != null) _debugLabel.Visible = ShowDebugInfo;
                    break;
            }
        }
    }

    public override void _ExitTree()
    {
        StopSession();
    }
}
