using Godot;
using System;

/// <summary>
/// Quest 3 Stereo 3D Viewer
/// 
/// Mimari:
///   - 2x SubViewport (Sol/Sağ göz)
///   - 1x MeshInstance3D (quad) üzerine stereo shader
///   - NetworkReceiver'dan gelen texture her iki viewport'a uygulanır
///
/// Siyah ekran sorunları için kontrol listesi:
///   1. SubViewport boyutları doğru mu? (ekran_genişlik/2 x ekran_yükseklik)
///   2. MeshInstance3D camera'ya bakıyor mu?
///   3. NetworkReceiver bağlandı mı? (IsConnected property)
/// </summary>
public partial class Stereo3DViewer : Node3D
{
    [Export] public string StreamServerIP = "192.168.1.100";
    [Export] public int StreamServerPort = 5000;
    [Export] public bool UseExternalTexture = false; // Quest 3'te true yap

    private SubViewport _leftViewport;
    private SubViewport _rightViewport;
    private MeshInstance3D _stereoMesh;
    private NetworkReceiver _networkReceiver;
    private ImageTexture _streamTexture;

    // Stereo shader - OES veya normal texture destekler
    private static readonly string StereoShaderCode = """
        shader_type spatial;
        render_mode unshaded, cull_disabled;

        uniform sampler2D stream_texture : hint_default_black;
        uniform bool is_left_eye = true;

        void fragment() {
            vec2 uv = UV;
            // Sol göz sol yarı, sağ göz sağ yarı
            // (aynı kamera görüntüsü, ileride parallax eklenebilir)
            ALBEDO = texture(stream_texture, uv).rgb;
        }
    """;

    public override void _Ready()
    {
        SetupViewports();
        SetupStereoMesh();
        SetupNetworkReceiver();
        GD.Print("[Stereo3DViewer] Hazır. IP: ", StreamServerIP, ":", StreamServerPort);
    }

    private void SetupViewports()
    {
        var screenSize = DisplayServer.WindowGetSize();
        var eyeWidth = screenSize.X / 2;
        var eyeHeight = screenSize.Y;

        _leftViewport = GetNode<SubViewport>("LeftViewport");
        _rightViewport = GetNode<SubViewport>("RightViewport");

        _leftViewport.Size = new Vector2I(eyeWidth, eyeHeight);
        _rightViewport.Size = new Vector2I(eyeWidth, eyeHeight);

        // XR için viewport'ları etkinleştir
        _leftViewport.UseXR = false; // OpenXR kullanmıyorsak false
        _rightViewport.UseXR = false;

        GD.Print($"[Stereo3DViewer] Viewport boyutu: {eyeWidth}x{eyeHeight}");
    }

    private void SetupStereoMesh()
    {
        _stereoMesh = GetNode<MeshInstance3D>("StereoMesh");

        var shader = new Shader();
        shader.Code = StereoShaderCode;

        var material = new ShaderMaterial();
        material.Shader = shader;

        _stereoMesh.MaterialOverride = material;
    }

    private void SetupNetworkReceiver()
    {
        _networkReceiver = GetNode<NetworkReceiver>("NetworkReceiver");
        _networkReceiver.ServerIP = StreamServerIP;
        _networkReceiver.ServerPort = StreamServerPort;
        _networkReceiver.OnFrameReceived += OnNewFrame;
        _networkReceiver.StartReceiving();
    }

    private void OnNewFrame(Image frame)
    {
        // Her yeni kare geldiğinde texture'ı güncelle
        if (_streamTexture == null)
        {
            _streamTexture = ImageTexture.CreateFromImage(frame);
        }
        else
        {
            _streamTexture.Update(frame);
        }

        // Shader'a texture'ı ver
        if (_stereoMesh.MaterialOverride is ShaderMaterial mat)
        {
            mat.SetShaderParameter("stream_texture", _streamTexture);
        }
    }

    public override void _Process(double delta)
    {
        // Bağlantı durumunu ekrana yaz (debug)
        if (Engine.GetFramesDrawn() % 60 == 0)
        {
            bool connected = _networkReceiver?.IsConnected ?? false;
            GD.Print($"[Stereo3DViewer] Bağlı: {connected} | FPS: {Engine.GetFramesPerSecond():F0}");
        }
    }

    public override void _ExitTree()
    {
        _networkReceiver?.StopReceiving();
    }
}
