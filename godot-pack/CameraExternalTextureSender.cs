using Godot;
using System;
using System.IO;
using System.IO.MemoryMappedFiles;

public partial class CameraExternalTextureSender : Node
{
    [Export] public int CameraIndex = 0;
    [Export] public int Width = 1280;
    [Export] public int Height = 720;
    [Export] public int TargetFps = 30;
    [Export] public bool AutoStart = true;
    [Export] public bool EnableDebugLog = false;

    private const uint SHM_MAGIC = 0xCAFEF00D;
    private const int HEADER_SIZE = 12; // magic + frame_id + ts_ms

    private CameraTexture? _cameraTexture;
    private CameraFeed? _cameraFeed;

    private MemoryMappedFile? _mmf;
    private MemoryMappedViewAccessor? _accessor;

    private byte[]? _bgrBuffer;
    private string _shmPath = string.Empty;
    private long _shmSize;

    private uint _frameId;
    private bool _running;

    private float _frameTimer;
    private float _frameInterval;

    public override void _Ready()
    {
        CameraServer.SetMonitoringFeeds(true);
        if (AutoStart)
            StartCapture();
    }

    public void StartCapture()
    {
        if (_running)
            return;

        _frameInterval = 1f / Mathf.Max(1, TargetFps);
        _frameTimer = 0f;

        _bgrBuffer = new byte[Width * Height * 3];
        _shmSize = HEADER_SIZE + _bgrBuffer.Length;

        string baseDir = Directory.Exists("/dev/shm") ? "/dev/shm" : "/tmp";
        _shmPath = Path.Combine(baseDir, $"godot_ext_frame_{Width}x{Height}");

        var feeds = CameraServer.Feeds();
        if (feeds == null || feeds.Count == 0)
        {
            GD.PrintErr("[ExtSender] Kamera feed bulunamadı. Project Settings > Camera Feed > Enable");
            return;
        }

        int idx = Mathf.Clamp(CameraIndex, 0, feeds.Count - 1);
        _cameraFeed = feeds[idx];

        try
        {
            if (!_cameraFeed.FeedIsActive)
                _cameraFeed.FeedIsActive = true;
        }
        catch { }

        _cameraTexture = new CameraTexture
        {
            CameraFeedId = _cameraFeed.GetId(),
            CameraIsActive = true,
        };

        try
        {
            _mmf = MemoryMappedFile.CreateFromFile(
                _shmPath,
                FileMode.Create,
                null,
                _shmSize,
                MemoryMappedFileAccess.ReadWrite
            );
            _accessor = _mmf.CreateViewAccessor(0, _shmSize, MemoryMappedFileAccess.ReadWrite);

            _accessor.Write(0, SHM_MAGIC);
            _accessor.Write(4, 0u);
            _accessor.Write(8, (uint)(System.Environment.TickCount & 0x7FFFFFFF));

            _running = true;
            GD.Print($"[ExtSender] Başladı. SHM: {_shmPath} ({Width}x{Height})");
        }
        catch (Exception e)
        {
            GD.PrintErr("[ExtSender] SHM oluşturma hatası: " + e.Message);
        }
    }

    public override void _Process(double delta)
    {
        if (!_running || _accessor == null || _cameraTexture == null || _bgrBuffer == null)
            return;

        _frameTimer += (float)delta;
        if (_frameTimer < _frameInterval)
            return;
        _frameTimer = 0f;

        Image? frame = null;
        try
        {
            frame = _cameraTexture.GetImage();
        }
        catch
        {
            return;
        }

        if (frame == null)
            return;

        if (frame.GetWidth() != Width || frame.GetHeight() != Height)
            frame.Resize(Width, Height, Image.Interpolation.Bilinear);

        if (frame.GetFormat() != Image.Format.Rgb8)
            frame.Convert(Image.Format.Rgb8);

        byte[] rgb = frame.GetData();
        if (rgb == null || rgb.Length != Width * Height * 3)
            return;

        int pixelCount = Width * Height;
        for (int i = 0; i < pixelCount; i++)
        {
            int offset = i * 3;
            _bgrBuffer[offset] = rgb[offset + 2];
            _bgrBuffer[offset + 1] = rgb[offset + 1];
            _bgrBuffer[offset + 2] = rgb[offset];
        }

        _frameId++;
        uint ts = (uint)(System.Environment.TickCount & 0x7FFFFFFF);

        _accessor.Write(0, SHM_MAGIC);
        _accessor.Write(4, _frameId);
        _accessor.Write(8, ts);
        _accessor.WriteArray(HEADER_SIZE, _bgrBuffer, 0, _bgrBuffer.Length);

        if (EnableDebugLog && _frameId % 120 == 0)
            GD.Print($"[ExtSender] Frame #{_frameId}");
    }

    public void StopCapture()
    {
        if (!_running)
            return;

        _running = false;

        try
        {
            if (_cameraFeed != null)
                _cameraFeed.FeedIsActive = false;
        }
        catch { }

        _cameraTexture = null;

        _accessor?.Dispose();
        _accessor = null;

        _mmf?.Dispose();
        _mmf = null;

        try
        {
            if (!string.IsNullOrEmpty(_shmPath) && File.Exists(_shmPath))
                File.Delete(_shmPath);
        }
        catch { }

        GD.Print("[ExtSender] Durduruldu.");
    }

    public override void _ExitTree()
    {
        StopCapture();
    }

    public bool IsRunning => _running;
    public uint FrameId => _frameId;
    public string ShmPath => _shmPath;
}
