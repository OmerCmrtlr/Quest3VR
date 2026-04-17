package com.godot.game;

import android.graphics.SurfaceTexture;
import android.opengl.GLES11Ext;
import android.opengl.GLES20;
import android.util.Log;
import android.util.SparseArray;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.Arrays;
import java.util.List;

public class ExternalTexturePlugin extends GodotPlugin {

    private static final String TAG = "ExternalTexture";

    private final SparseArray<SlotData> mSlots = new SparseArray<>();
    private int mNextSlot = 0;
    private int mDefaultWidth = 1280;
    private int mDefaultHeight = 720;

    private static class SlotData implements SurfaceTexture.OnFrameAvailableListener {
        int glTexId = -1;
        SurfaceTexture surfaceTexture;
        volatile boolean frameAvailable = false;
        MediaCodecReceiver receiver;

        @Override
        public void onFrameAvailable(SurfaceTexture st) {
            frameAvailable = true;
        }
    }

    public ExternalTexturePlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "ExternalTexturePlugin";
    }

    // -------------------------------------------------------
    // GDScript'ten çağrılan metodlar
    // -------------------------------------------------------

    @UsedByGodot
    public void setDefaultBufferSize(int width, int height) {
        mDefaultWidth = width;
        mDefaultHeight = height;
        Log.d(TAG, "Buffer size: " + width + "x" + height);
    }

    @UsedByGodot
    public void set_default_buffer_size(int width, int height) {
        setDefaultBufferSize(width, height);
    }

    @UsedByGodot
    public int createExternalTexture() {
        int[] texIds = new int[1];
        GLES20.glGenTextures(1, texIds, 0);
        int texId = texIds[0];

        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texId);
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR);
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR);
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE);
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE);

        SlotData slot = new SlotData();
        slot.glTexId = texId;
        slot.surfaceTexture = new SurfaceTexture(texId);
        slot.surfaceTexture.setDefaultBufferSize(mDefaultWidth, mDefaultHeight);
        slot.surfaceTexture.setOnFrameAvailableListener(slot);

        int slotId = mNextSlot++;
        mSlots.put(slotId, slot);

        Log.d(TAG, "createExternalTexture slot=" + slotId + " glId=" + texId);
        return slotId;
    }

    @UsedByGodot
    public int create_external_texture() {
        return createExternalTexture();
    }

    @UsedByGodot
    public boolean startReceiverForTexture(int slot, int port, int width, int height) {
        SlotData data = mSlots.get(slot);
        if (data == null) {
            Log.e(TAG, "startReceiverForTexture: slot yok: " + slot);
            return false;
        }

        try {
            android.view.Surface surface = new android.view.Surface(data.surfaceTexture);
            MediaCodecReceiver recv = new MediaCodecReceiver();
            recv.setPort(port);
            recv.setResolution(width, height);
            recv.setTargetSurfaceTexture(data.surfaceTexture);
            data.receiver = recv;
            boolean ok = recv.startReceiving();
            Log.d(TAG, "startReceiverForTexture slot=" + slot + " ok=" + ok);
            return ok;
        } catch (Exception e) {
            Log.e(TAG, "startReceiverForTexture hata: " + e.getMessage());
            return false;
        }
    }

    @UsedByGodot
    public boolean start_receiver_for_texture(int slot, int port, int width, int height) {
        return startReceiverForTexture(slot, port, width, height);
    }

    @UsedByGodot
    public boolean updateTexture(int slot) {
        SlotData data = mSlots.get(slot);
        if (data == null) return false;

        if (data.frameAvailable && data.surfaceTexture != null) {
            try {
                data.surfaceTexture.updateTexImage();
                data.frameAvailable = false;
                return true;
            } catch (Exception e) {
                Log.e(TAG, "updateTexImage hata: " + e.getMessage());
            }
        }
        return false;
    }

    @UsedByGodot
    public boolean update_texture(int slot) {
        return updateTexture(slot);
    }

    @UsedByGodot
    public int getGlTextureId(int slot) {
        SlotData data = mSlots.get(slot);
        if (data == null) return -1;
        return data.glTexId;
    }

    @UsedByGodot
    public int get_gl_texture_id(int slot) {
        return getGlTextureId(slot);
    }

    @UsedByGodot
    public void destroyExternalTexture(int slot) {
        SlotData data = mSlots.get(slot);
        if (data == null) return;

        if (data.receiver != null) {
            data.receiver.stopReceiving();
            data.receiver = null;
        }

        if (data.surfaceTexture != null) {
            data.surfaceTexture.release();
            data.surfaceTexture = null;
        }

        if (data.glTexId >= 0) {
            GLES20.glDeleteTextures(1, new int[]{data.glTexId}, 0);
            data.glTexId = -1;
        }

        mSlots.remove(slot);
        Log.d(TAG, "destroyExternalTexture slot=" + slot);
    }

    @UsedByGodot
    public void destroy_external_texture(int slot) {
        destroyExternalTexture(slot);
    }

    @UsedByGodot
    public Object getSurfaceForTexture(int slot) {
        SlotData data = mSlots.get(slot);
        if (data == null) return null;
        return data.surfaceTexture;
    }

    @UsedByGodot
    public Object get_surface_for_texture(int slot) {
        return getSurfaceForTexture(slot);
    }

    @Override
    public void onMainDestroy() {
        for (int i = 0; i < mSlots.size(); i++) {
            int key = mSlots.keyAt(i);
            destroyExternalTexture(key);
        }
        super.onMainDestroy();
    }
}
