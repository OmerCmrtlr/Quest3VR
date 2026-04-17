using Godot;
using System;
using System.Threading;
using System.Threading.Tasks;

/// <summary>
/// UDP üzerinden MJPEG/JPEG stream alır.
/// laptop_stream_server.py ile uyumlu protokol:
///   [4 byte: frame boyutu][N byte: JPEG data]
/// </summary>
public partial class NetworkReceiver : Node
{
    public string ServerIP { get; set; } = "192.168.1.100";
    public int ServerPort { get; set; } = 5000;
    public bool IsConnected { get; private set; } = false;

    public event Action<Image> OnFrameReceived;

    private PacketPeerUDP _udp;
    private CancellationTokenSource _cts;
    private bool _receiving = false;

    public void StartReceiving()
    {
        if (_receiving) return;
        _receiving = true;

        _udp = new PacketPeerUDP();
        var err = _udp.Bind(ServerPort);

        if (err != Error.Ok)
        {
            GD.PrintErr($"[NetworkReceiver] UDP bind hatası: {err}");
            return;
        }

        GD.Print($"[NetworkReceiver] UDP dinleniyor port {ServerPort}");
        IsConnected = true;
    }

    public override void _Process(double delta)
    {
        if (!_receiving || _udp == null) return;

        // Gelen paketleri işle (game loop'ta, thread'siz)
        while (_udp.GetAvailablePacketCount() > 0)
        {
            var data = _udp.GetPacket();
            TryDecodeFrame(data);
        }
    }

    private void TryDecodeFrame(byte[] data)
    {
        try
        {
            var image = new Image();
            var err = image.LoadJpgFromBuffer(data);

            if (err == Error.Ok)
            {
                IsConnected = true;
                CallDeferred(nameof(EmitFrame), image);
            }
            else
            {
                GD.PrintErr($"[NetworkReceiver] JPEG decode hatası: {err}");
            }
        }
        catch (Exception e)
        {
            GD.PrintErr($"[NetworkReceiver] Frame hata: {e.Message}");
        }
    }

    private void EmitFrame(Image image)
    {
        OnFrameReceived?.Invoke(image);
    }

    public void StopReceiving()
    {
        _receiving = false;
        IsConnected = false;
        _udp?.Close();
        _udp = null;
        GD.Print("[NetworkReceiver] Durduruldu.");
    }
}
