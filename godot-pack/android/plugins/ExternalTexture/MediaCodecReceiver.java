package com.godot.game;

import android.graphics.SurfaceTexture;
import android.media.MediaCodec;
import android.media.MediaFormat;
import android.util.Log;
import android.view.Surface;

import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.SocketTimeoutException;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;

public class MediaCodecReceiver {

    private static final String TAG = "MediaCodecReceiver";
    private static final int MAX_PACKET = 65536;
    private static final int RTP_HEADER_MIN = 12;
    private static final int CODEC_TIMEOUT_US = 10000;

    private int mPort = 5010;
    private int mWidth = 1280;
    private int mHeight = 720;
    private SurfaceTexture mTargetSurfaceTexture = null;

    private MediaCodec mDecoder = null;
    private DatagramSocket mSocket = null;
    private Thread mReceiveThread = null;
    private volatile boolean mRunning = false;

    // FU-A reassembly
    private final List<byte[]> mFuBuffer = new ArrayList<>();
    private boolean mInFuA = false;
    private byte mFuNalType = 0;
    private byte mFuNalRefIdc = 0;

    public void setPort(int port) {
        mPort = port;
    }

    public void setResolution(int width, int height) {
        mWidth = width;
        mHeight = height;
    }

    public void setTargetSurfaceTexture(Object surfaceTexture) {
        mTargetSurfaceTexture = (SurfaceTexture) surfaceTexture;
    }

    public boolean startReceiving() {
        if (mRunning) return true;

        if (mTargetSurfaceTexture == null) {
            Log.e(TAG, "SurfaceTexture null, başlatılamıyor");
            return false;
        }

        try {
            Surface surface = new Surface(mTargetSurfaceTexture);

            mDecoder = MediaCodec.createDecoderByType("video/avc");
            MediaFormat fmt = MediaFormat.createVideoFormat("video/avc", mWidth, mHeight);
            fmt.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, MAX_PACKET * 4);
            mDecoder.configure(fmt, surface, null, 0);
            mDecoder.start();

            mSocket = new DatagramSocket(mPort);
            mSocket.setSoTimeout(1000);

            mRunning = true;
            mReceiveThread = new Thread(this::receiveLoop, "MediaCodecReceiver");
            mReceiveThread.setDaemon(true);
            mReceiveThread.start();

            Log.d(TAG, "Başlatıldı port=" + mPort + " " + mWidth + "x" + mHeight);
            return true;

        } catch (IOException e) {
            Log.e(TAG, "Başlatma hatası: " + e.getMessage());
            releaseResources();
            return false;
        }
    }

    public void stopReceiving() {
        mRunning = false;
        if (mReceiveThread != null) {
            try { mReceiveThread.join(2000); } catch (InterruptedException ignored) {}
            mReceiveThread = null;
        }
        releaseResources();
        Log.d(TAG, "Durduruldu");
    }

    public boolean isReceiving() {
        return mRunning;
    }

    private void receiveLoop() {
        byte[] buf = new byte[MAX_PACKET];
        DatagramPacket pkt = new DatagramPacket(buf, buf.length);

        while (mRunning) {
            try {
                mSocket.receive(pkt);
                processRtpPacket(buf, pkt.getLength());
            } catch (SocketTimeoutException ignored) {
            } catch (Exception e) {
                if (mRunning) Log.e(TAG, "Receive hata: " + e.getMessage());
            }
        }
    }

    private void processRtpPacket(byte[] data, int len) {
        if (len < RTP_HEADER_MIN + 1) return;

        // RTP header parse
        int payloadOffset = RTP_HEADER_MIN;
        int cc = data[0] & 0x0F;
        payloadOffset += cc * 4;
        boolean hasExtension = (data[0] & 0x10) != 0;
        if (hasExtension) {
            if (payloadOffset + 4 > len) return;
            int extLen = ((data[payloadOffset + 2] & 0xFF) << 8) | (data[payloadOffset + 3] & 0xFF);
            payloadOffset += 4 + extLen * 4;
        }
        if (payloadOffset >= len) return;

        byte nalHeader = data[payloadOffset];
        int nalType = nalHeader & 0x1F;
        byte nalRefIdc = (byte)((nalHeader >> 5) & 0x03);

        if (nalType >= 1 && nalType <= 23) {
            // Single NAL unit
            submitNalToDecoder(data, payloadOffset, len - payloadOffset);

        } else if (nalType == 28) {
            // FU-A
            if (payloadOffset + 2 > len) return;
            byte fuHeader = data[payloadOffset + 1];
            boolean isStart = (fuHeader & 0x80) != 0;
            boolean isEnd   = (fuHeader & 0x40) != 0;
            byte fuNalType  = (byte)(fuHeader & 0x1F);

            if (isStart) {
                mFuBuffer.clear();
                mInFuA = true;
                mFuNalType = fuNalType;
                mFuNalRefIdc = nalRefIdc;

                // Reconstruct NAL header
                byte reconstructed = (byte)((nalRefIdc << 5) | fuNalType);
                int chunkLen = len - payloadOffset - 1;
                byte[] chunk = new byte[chunkLen];
                chunk[0] = reconstructed;
                System.arraycopy(data, payloadOffset + 2, chunk, 1, chunkLen - 1);
                mFuBuffer.add(chunk);
            } else if (mInFuA) {
                int chunkLen = len - payloadOffset - 2;
                if (chunkLen > 0) {
                    byte[] chunk = new byte[chunkLen];
                    System.arraycopy(data, payloadOffset + 2, chunk, 0, chunkLen);
                    mFuBuffer.add(chunk);
                }
            }

            if (isEnd && mInFuA) {
                mInFuA = false;
                int total = 0;
                for (byte[] c : mFuBuffer) total += c.length;
                byte[] nal = new byte[total];
                int pos = 0;
                for (byte[] c : mFuBuffer) {
                    System.arraycopy(c, 0, nal, pos, c.length);
                    pos += c.length;
                }
                mFuBuffer.clear();
                submitNalToDecoder(nal, 0, nal.length);
            }

        } else if (nalType == 24) {
            // STAP-A
            int offset = payloadOffset + 1;
            while (offset + 2 <= len) {
                int size = ((data[offset] & 0xFF) << 8) | (data[offset + 1] & 0xFF);
                offset += 2;
                if (offset + size > len) break;
                submitNalToDecoder(data, offset, size);
                offset += size;
            }
        }
    }

    private void submitNalToDecoder(byte[] data, int offset, int length) {
        if (mDecoder == null || !mRunning || length <= 0) return;

        try {
            int idx = mDecoder.dequeueInputBuffer(CODEC_TIMEOUT_US);
            if (idx < 0) return;

            ByteBuffer inputBuf = mDecoder.getInputBuffer(idx);
            if (inputBuf == null) return;
            inputBuf.clear();

            // Annex-B start code
            inputBuf.put((byte)0x00);
            inputBuf.put((byte)0x00);
            inputBuf.put((byte)0x00);
            inputBuf.put((byte)0x01);
            inputBuf.put(data, offset, length);

            long ptsUs = System.nanoTime() / 1000;
            mDecoder.queueInputBuffer(idx, 0, inputBuf.position(), ptsUs, 0);

            // Output drain
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            int outIdx = mDecoder.dequeueOutputBuffer(info, CODEC_TIMEOUT_US);
            if (outIdx >= 0) {
                mDecoder.releaseOutputBuffer(outIdx, true); // render=true → SurfaceTexture'a yazar
            }

        } catch (Exception e) {
            if (mRunning) Log.e(TAG, "submitNal hata: " + e.getMessage());
        }
    }

    private void releaseResources() {
        try {
            if (mDecoder != null) {
                mDecoder.stop();
                mDecoder.release();
                mDecoder = null;
            }
        } catch (Exception ignored) {}

        try {
            if (mSocket != null) {
                mSocket.close();
                mSocket = null;
            }
        } catch (Exception ignored) {}
    }
}
