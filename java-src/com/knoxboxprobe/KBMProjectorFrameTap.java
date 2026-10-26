// Copyright (c) 2026 Grymlock.
// SPDX-License-Identifier: GPL-3.0-only
package com.knoxboxprobe;

import java.lang.reflect.Field;
import java.nio.ByteBuffer;
import java.util.concurrent.atomic.AtomicBoolean;
import me.zed_0xff.zombie_buddy.Exposer;

/** Copies the active KnoxBox movie frame to the fixed screen. */
@Exposer.LuaClass(name = "KBMProjectorFrameTap")
public final class KBMProjectorFrameTap {
    private static final String SCREEN_MODEL = "KBMProjector.Screen";
    private static final String DRIVE_IN_SCREEN_MODEL = "KBMProjector.DriveInScreen";
    private static final String PREMIUM_SCREEN_MODEL = "KBM.PremiumScreen";
    private static final String VALUTECH_SCREEN_MODEL = "KBM.ValuTechScreen";
    private static final int FRAME_WIDTH = 512;
    private static final int FRAME_HEIGHT = 384;
    private static boolean active;
    private static String selectedModel;
    private static int lastFrame = -1;
    private static volatile int displayedFrame;
    private static int originalTextureId = -1;
    private static byte[] originalPixels;
    private static final AtomicBoolean uploadPending = new AtomicBoolean();
    private static int[] stagedFrame;
    private static ByteBuffer uploadBuffer;
    private static int[] xSamples;
    private static int[] ySamples;
    private static long fillNanos;
    private static long setDataNanos;
    private static int measuredUploads;
    private static String status = "idle";

    private KBMProjectorFrameTap() {}

    public static String getStatus() { return status; }
    /** Last frame successfully uploaded to this screen, rather than the cabinet texture. */
    public static int getDisplayedFrame() { return displayedFrame; }

    public static void setScreenModel(String model) {
        if (SCREEN_MODEL.equals(model) || DRIVE_IN_SCREEN_MODEL.equals(model)
                || PREMIUM_SCREEN_MODEL.equals(model) || VALUTECH_SCREEN_MODEL.equals(model)) selectedModel = model;
        else selectedModel = null;
    }

    public static void start() {
        active = true;
        lastFrame = -1;
        displayedFrame = 0;
        fillNanos = 0;
        setDataNanos = 0;
        measuredUploads = 0;
        status = "waiting for movie frame";
    }

    public static void stop() {
        active = false;
        lastFrame = -1;
        displayedFrame = 0;
        final String restoreModel = selectedModel;
        onRenderThread(() -> {
            try {
                Object texture = modelTexture(restoreModel);
                if (texture != null && number(texture, "getID") == originalTextureId
                        && originalPixels != null) {
                    if (uploadBuffer == null || uploadBuffer.capacity() != originalPixels.length)
                        uploadBuffer = ByteBuffer.allocateDirect(originalPixels.length);
                    uploadBuffer.clear();
                    uploadBuffer.put(originalPixels).flip();
                    setTextureData(texture, uploadBuffer);
                }
                status = "stopped";
            } catch (ReflectiveOperationException error) {
                status = "screen restore failed: " + error;
            }
        });
    }

    public static void update() {
        if (!active) return;
        try {
            Class<?> player = Class.forName("com.knoxboxprobe.KBMMovieScreenBridge");
            boolean playing = (Boolean) player.getMethod("isPlaying").invoke(null);
            if (!playing) return;
            int frame = (Integer) player.getMethod("getCurrentFrame").invoke(null);
            if (frame <= 0 || frame == lastFrame) return;
            Field field = player.getDeclaredField("framePixels");
            field.setAccessible(true);
            int[] pixels = (int[]) field.get(null);
            if (pixels == null || pixels.length != FRAME_WIDTH * FRAME_HEIGHT) return;
            if (!uploadPending.compareAndSet(false, true)) return;
            if (stagedFrame == null) stagedFrame = new int[pixels.length];
            System.arraycopy(pixels, 0, stagedFrame, 0, pixels.length);
            lastFrame = frame;
            onRenderThread(() -> {
                try { upload(stagedFrame, frame); }
                finally { uploadPending.set(false); }
            });
        } catch (ReflectiveOperationException | SecurityException error) {
            uploadPending.set(false);
            active = false;
            status = "frame tap failed: " + error;
        }
    }

    private static void upload(int[] frame, int frameNumber) {
        if (!active) return;
        try {
        Object texture = modelTexture();
        if (texture == null) { status = "screen model texture not loaded"; return; }
        int width = number(texture, "getWidthHW");
        int height = number(texture, "getHeightHW");
        if (width < 64 || height < 64 || width > 2048 || height > 2048) {
            status = "invalid screen texture " + width + "x" + height;
            return;
        }
        if (originalTextureId != number(texture, "getID")) {
            Object readback = texture.getClass().getMethod("getData").invoke(texture);
            try {
                ByteBuffer source = (ByteBuffer) readback.getClass().getMethod("getBuffer").invoke(readback);
                source.rewind();
                originalPixels = new byte[width * height * 4];
                source.get(originalPixels);
                originalTextureId = number(texture, "getID");
            } finally {
                readback.getClass().getMethod("dispose").invoke(readback);
            }
        }
        int bytes = width * height * 4;
        if (uploadBuffer == null || uploadBuffer.capacity() != bytes) {
            uploadBuffer = ByteBuffer.allocateDirect(bytes);
            xSamples = null;
            ySamples = null;
        }
        if (xSamples == null || xSamples.length != width) {
            xSamples = new int[width];
            for (int x = 0; x < width; x++) xSamples[x] = x * FRAME_WIDTH / width;
        }
        if (ySamples == null || ySamples.length != height) {
            ySamples = new int[height];
            for (int y = 0; y < height; y++) ySamples[y] = y * FRAME_HEIGHT / height;
        }
        long fillStart = System.nanoTime();
        uploadBuffer.clear();
        for (int y = 0; y < height; y++) {
            int sourceRow = ySamples[y] * FRAME_WIDTH;
            for (int x = 0; x < width; x++) {
                int argb = frame[sourceRow + xSamples[x]];
                uploadBuffer.putInt((argb << 8) | 253);
            }
        }
        uploadBuffer.flip();
        long setDataStart = System.nanoTime();
        setTextureData(texture, uploadBuffer);
        displayedFrame = frameNumber;
        fillNanos += setDataStart - fillStart;
        setDataNanos += System.nanoTime() - setDataStart;
        measuredUploads++;
        if (frameNumber == 1 || frameNumber % 120 == 0) {
            status = "projected frame " + frameNumber + " to texture " + number(texture, "getID");
            System.out.println("[KBMProjector] " + status + ", " + width + "x" + height
                + ", avg fill " + String.format("%.2f", fillNanos / 1_000_000.0 / measuredUploads)
                + " ms, avg setData " + String.format("%.2f", setDataNanos / 1_000_000.0 / measuredUploads)
                + " ms over " + measuredUploads + " uploads");
            fillNanos = 0;
            setDataNanos = 0;
            measuredUploads = 0;
        }
        } catch (ReflectiveOperationException | RuntimeException error) {
            status = "screen upload failed: " + error;
        }
    }

    private static int number(Object object, String method) throws ReflectiveOperationException {
        return ((Number) object.getClass().getMethod(method).invoke(object)).intValue();
    }

    private static void setTextureData(Object texture, ByteBuffer data)
            throws ReflectiveOperationException {
        texture.getClass().getMethod("setData", ByteBuffer.class).invoke(texture, data);
    }

    private static void onRenderThread(Runnable action) {
        try {
            Class<?> render = Class.forName("zombie.core.opengl.RenderThread");
            render.getMethod("invokeOnRenderContext", Runnable.class).invoke(null, action);
        } catch (ReflectiveOperationException error) {
            uploadPending.set(false);
            active = false;
            status = "render dispatch failed: " + error;
        }
    }

    private static Object modelTexture() {
        return modelTexture(selectedModel);
    }

    private static Object modelTexture(String modelFilter) {
        try {
            Class<?> scripts = Class.forName("zombie.scripting.ScriptManager");
            Object manager = scripts.getField("instance").get(null);
            Class<?> modelScript = Class.forName("zombie.scripting.objects.ModelScript");
            Class<?> models = Class.forName("zombie.core.skinnedmodel.ModelManager");
            Object modelManager = models.getField("instance").get(null);
            for (String modelName : new String[] {SCREEN_MODEL, DRIVE_IN_SCREEN_MODEL,
                    PREMIUM_SCREEN_MODEL, VALUTECH_SCREEN_MODEL}) {
                if (modelFilter != null && !modelFilter.equals(modelName)) continue;
                Object script = scripts.getMethod("getModelScript", String.class)
                    .invoke(manager, modelName);
                if (script == null) continue;
                Object model = models.getMethod("tryGetLoadedModel", modelScript, boolean.class)
                    .invoke(modelManager, script, false);
                if (model != null) return model.getClass().getField("tex").get(model);
            }
            return null;
        } catch (ReflectiveOperationException error) {
            status = "screen texture lookup failed: " + error;
            return null;
        }
    }
}
