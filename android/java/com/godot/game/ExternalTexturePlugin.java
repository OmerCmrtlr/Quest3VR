package com.godot.game;

import android.graphics.SurfaceTexture;
import android.opengl.GLES11Ext;
import android.opengl.GLES20;
import android.util.Log;

/**
 * ExternalTexturePlugin
 * =====================
 * Quest 3 için SurfaceTexture tabanlı ExternalTexture yöneticisi.
 * Godot'un GDExtension/Android Plugin sistemi ile entegre çalışır.
 *
 * Kullanım (Godot C# tarafından çağrılır):
 *   int texId = ExternalTexturePlugin.createTexture();
 *   ExternalTexturePlugin.bindSurface(texId);
 *   // Her frame: ExternalTexturePlugin.updateTexImage();
 */
public class ExternalTexturePlugin implements SurfaceTexture.OnFrameAvailableListener {

    private static final String TAG = "ExternalTexture";

    private int mTextureId = -1;
    private SurfaceTexture mSurfaceTexture;
    private boolean mFrameAvailable = false;

    // Singleton (Godot plugin sistemi için)
    private static ExternalTexturePlugin sInstance;

    public static ExternalTexturePlugin getInstance() {
        if (sInstance == null) {
            sInstance = new ExternalTexturePlugin();
        }
        return sInstance;
    }

    /**
     * OES External Texture oluştur.
     * OpenGL context içinde çağrılmalı (Godot render thread).
     */
    public int createTexture() {
        int[] textures = new int[1];
        GLES20.glGenTextures(1, textures, 0);
        mTextureId = textures[0];

        // OES texture binding
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, mTextureId);
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
                GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR);
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
                GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR);
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
                GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE);
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
                GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE);

        mSurfaceTexture = new SurfaceTexture(mTextureId);
        mSurfaceTexture.setOnFrameAvailableListener(this);

        Log.d(TAG, "Texture oluşturuldu: " + mTextureId);
        return mTextureId;
    }

    /**
     * SurfaceTexture'ı döndürür (kamera/stream kaynağına bağlamak için).
     */
    public SurfaceTexture getSurfaceTexture() {
        return mSurfaceTexture;
    }

    /**
     * Yeni frame varsa texture'ı güncelle.
     * Godot render thread'inde her frame çağrılmalı.
     */
    public boolean updateTexImage() {
        synchronized (this) {
            if (mFrameAvailable && mSurfaceTexture != null) {
                mSurfaceTexture.updateTexImage();
                mFrameAvailable = false;
                return true;
            }
        }
        return false;
    }

    @Override
    public void onFrameAvailable(SurfaceTexture surfaceTexture) {
        synchronized (this) {
            mFrameAvailable = true;
        }
    }

    public int getTextureId() {
        return mTextureId;
    }

    /**
     * Kaynakları serbest bırak.
     */
    public void release() {
        if (mSurfaceTexture != null) {
            mSurfaceTexture.release();
            mSurfaceTexture = null;
        }
        if (mTextureId != -1) {
            GLES20.glDeleteTextures(1, new int[]{mTextureId}, 0);
            mTextureId = -1;
        }
        Log.d(TAG, "Kaynaklar serbest bırakıldı.");
    }
}
