// Copyright (c) 2026 Grymlock. All rights reserved.
// SPDX-License-Identifier: LicenseRef-KnoxBox-Original-Content
// See LICENSES/KnoxBox-License.md and LICENSES/Java/KnoxBox-Bridges.md.
package com.knoxboxprobe;

import java.nio.ByteBuffer;
import java.awt.image.BufferedImage;
import java.io.File;
import java.lang.reflect.Field;
import java.util.Arrays;
import java.util.concurrent.atomic.AtomicBoolean;
import org.lwjgl.opengl.GL11;
import org.jcodec.api.FrameGrab;
import org.jcodec.common.io.NIOUtils;
import org.jcodec.common.io.SeekableByteChannel;
import org.jcodec.common.model.Picture;
import org.jcodec.scale.AWTUtil;
import me.zed_0xff.zombie_buddy.Exposer;
import zombie.core.opengl.RenderThread;
import zombie.core.textures.Texture;
import zombie.core.textures.TextureID;
import zombie.core.utils.WrappedBuffer;

/** Decode movie frames and upload them to KnoxBox television textures. */
@Exposer.LuaClass(name = "KBMMovieScreenBridge")
public final class KBMMovieScreenBridge {
    private static final String CAMCORDER3_HAND_MODEL = "KBM.KBM_Camcorder3_Hand";

    private static Object camcorder3Script() throws ReflectiveOperationException {
        Class<?> managerClass = Class.forName("zombie.scripting.ScriptManager");
        Object manager = managerClass.getField("instance").get(null);
        return managerClass.getMethod("getModelScript", String.class)
            .invoke(manager, CAMCORDER3_HAND_MODEL);
    }

    public static float getCamcorder3Scale() {
        try {
            Object script = camcorder3Script();
            return script == null ? Float.NaN : script.getClass().getField("scale").getFloat(script);
        } catch (ReflectiveOperationException failure) {
            System.out.println("[KBM][Camcorder3Scale] Read failed: " + failure);
            return Float.NaN;
        }
    }

    public static boolean setCamcorder3Scale(float scale) {
        if (!Float.isFinite(scale) || scale < 0.1f || scale > 2.0f) return false;
        try {
            Object script = camcorder3Script();
            if (script == null) return false;
            script.getClass().getField("scale").setFloat(script, scale);
            return true;
        } catch (ReflectiveOperationException failure) {
            System.out.println("[KBM][Camcorder3Scale] Write failed: " + failure);
            return false;
        }
    }

    private static final int SIZE = 512;
    private static final int SCREEN_HEIGHT = 384;
    private static final String MODEL_SCRIPT = "KBM.ScreenTV";
    private static final String LEGACY_MODEL_SCRIPT = "KBMViewpointProbe.ScreenTV";
    private static final String PLAYING_MODEL_SCRIPT = "KBM.ScreenTVPlaying";
    private static final String LEGACY_PLAYING_MODEL_SCRIPT = "KBMViewpointProbe.ScreenTVPlaying";
    private static volatile String tvDisplayModel = MODEL_SCRIPT;
    private static volatile boolean enabled;
    private static long frameNanos = 1_000_000_000L / 12;
    private static long nextFrameNanos;
    private static volatile long audioClockMs = -1;
    private static volatile long lastAudioAdvanceNanos;
    private static boolean usingAudioClock;
    private static File selectedVideo;
    private static SeekableByteChannel channel;
    private static FrameGrab grab;
    private static int[] sourcePixels;
    private static int[] framePixels;
    // Render-thread-owned upload storage; preserve frame copies until their callbacks finish.
    private static ByteBuffer tvUploadBuffer;
    private static ByteBuffer legacyTvUploadBuffer;
    private static byte[] cabinetPixels;
    private static int cabinetTextureId = -1;
    private static int cabinetWidth;
    private static int cabinetHeight;
    private static byte[] legacyCabinetPixels;
    private static int legacyCabinetTextureId = -1;
    private static int legacyCabinetWidth;
    private static int legacyCabinetHeight;
    private static int frameNumber;
    private static volatile int displayedFrame;
    private static volatile int latestRequestedFrame;
    private static boolean doomMirror;
    private static boolean nesMirror;
    private static volatile String gameBoyModelScript;
    private static long lastGameBoyUploadNanos;
    private static int gameBoyFrameSequence;
    private static byte[] gameBoyOriginalAtlas;
    private static int[] gameBoyLastUploadedFrame;
    private static int gameBoyLastUploadedDiagnostic = -1;
    // Compressed model textures need block-aligned subimage rectangles.
    private static final boolean GAME_BOY_REGION_UPLOAD_ENABLED = true;
    private static int gameBoyRegionW, gameBoyRegionH;
    private static int gameBoyTextureId = -1;
    private static String gameBoyTextureScript;
    private static boolean gameBoyRegionVerified;
    private static boolean gameBoyRegionRejected;
    private static String gameBoyRegionFailure = "";
    private static String gameBoyLastUploadDetails = "waiting for first upload";
    private static int gameBoyLastBindError;
    private static volatile int latestGameBoyRequest;
    private static final AtomicBoolean gameBoyUploadPending = new AtomicBoolean();
    private static ByteBuffer gameBoyUploadBuffer;
    private static volatile String gameBoyStatus = "idle";
    private static volatile int gameBoyDiagnosticMode;
    private static long lastGameBoyStatusLogNanos;
    private static long lastDoomFrame = -1;
    private static long lastNesUploadNanos;
    private static int nesFrameSequence;
    private static Field doomPixelsField;
    private static double fps = 12;
    private static boolean finished;
    private static String status = "idle";

    private KBMMovieScreenBridge() {}

    public static void setEnabled(boolean on) {
        enabled = on;
        status = on ? "waiting for MP4" : "off";
        nextFrameNanos = 0;
    }

    public static String getStatus() { return status; }
    public static String getGameBoyStatus() { return gameBoyStatus; }
    /** 0=normal, 1=whole atlas magenta, 2=expected LCD rectangle green. */
    public static void setGameBoyDiagnosticMode(int mode) {
        gameBoyDiagnosticMode = Math.max(0, Math.min(2, mode));
    }
    /** Choose the TV type playing this movie; model textures are shared by type. */
    public static void setTvDisplay(String modelScript) {
        if (MODEL_SCRIPT.equals(modelScript) || LEGACY_MODEL_SCRIPT.equals(modelScript)
                || PLAYING_MODEL_SCRIPT.equals(modelScript)
                || LEGACY_PLAYING_MODEL_SCRIPT.equals(modelScript)) {
            tvDisplayModel = modelScript;
        }
    }
    public static int getCurrentFrame() { return frameNumber; }
    /** Internal frame tap; callers copy before dispatching to the render context. */
    static int[] currentFramePixels() { return framePixels; }
    public static int getDisplayedFrame() { return displayedFrame; }
    public static double getFps() { return fps; }
    public static void setAudioClockMs(long positionMs) {
        if (positionMs >= 0 && positionMs != audioClockMs)
            lastAudioAdvanceNanos = System.nanoTime();
        audioClockMs = positionMs;
    }
    public static boolean isPlaying() { return enabled; }
    public static boolean isFinished() { return finished; }

    /** Mirrors the already-running Doom session; it never starts an emulator. */
    public static void setDoomMirror(boolean on) {
        if (on) {
            stop();
            doomMirror = true;
            enabled = true;
            status = "waiting for Doom frame";
        } else if (doomMirror) {
            doomMirror = false;
            lastDoomFrame = -1;
            stop();
        }
    }

    /** Mirrors the existing NES session without starting another emulator. */
    public static void setNesMirror(boolean on) {
        if (on) {
            stop();
            nesMirror = true;
            enabled = true;
            status = "waiting for NES frame";
        } else if (nesMirror) {
            stop();
        }
    }

    /** Independently mirrors the current Game Boy into its held model. */
    public static void setGameBoyMirror(String modelScript, boolean on) {
        if (!on) {
            gameBoyModelScript = null;
            latestGameBoyRequest++;
            lastGameBoyUploadNanos = 0;
            RenderThread.invokeOnRenderContext(KBMMovieScreenBridge::restoreGameBoyTexture);
            gameBoyStatus = "stopped";
            return;
        }
        if (modelScript == null || !modelScript.matches(
                "KBM\\.KBM_GameBoy_(Classic|Green|Grey|Red|Yellow|Blue|Pink|Clear)")) {
            gameBoyStatus = "invalid Game Boy model";
            return;
        }
        if (!modelScript.equals(gameBoyModelScript)) {
            gameBoyModelScript = modelScript;
            latestGameBoyRequest++;
            RenderThread.invokeOnRenderContext(KBMMovieScreenBridge::restoreGameBoyTexture);
            lastGameBoyUploadNanos = 0;
        }
        gameBoyStatus = "waiting for Game Boy frame";
    }

    public static void pause() { enabled = false; status = "paused"; }
    public static void resume() {
        if (selectedVideo != null && !finished) { enabled = true; nextFrameNanos = 0; status = "playing"; }
    }
    /** Jump within the current tape; its audio is restarted by the Lua bridge. */
    public static boolean seekSeconds(int delta) {
        if (selectedVideo == null || finished || delta == 0) return false;
        try {
            if (grab == null) openVideo();
            double target = Math.max(0, (frameNumber <= 0 ? 0 : (frameNumber - 1) / fps) + delta);
            grab.seekToSecondPrecise(target);
            frameNumber = Math.max(0, (int) Math.floor(target * fps));
            displayedFrame = frameNumber;
            latestRequestedFrame = frameNumber;
            audioClockMs = -1;
            usingAudioClock = false;
            nextFrameNanos = 0;
            status = "seeked to " + (int) target + "s";
            return true;
        } catch (Throwable e) {
            status = "seek failed: " + e.getMessage();
            return false;
        }
    }
    public static void stop() {
        doomMirror = false;
        nesMirror = false;
        lastDoomFrame = -1;
        lastNesUploadNanos = 0;
        nesFrameSequence = 0;
        enabled = false;
        finished = false;
        audioClockMs = -1;
        usingAudioClock = false;
        closeVideo();
        selectedVideo = null;
        tvDisplayModel = MODEL_SCRIPT;
        status = "stopped";
        blankScreen();
    }

    /** Resolve only media/video content from a currently active movie pack. */
    public static boolean playFromMod(String modId, String fileName) {
        try {
            if (modId == null || !modId.matches("[A-Za-z0-9_.-]{1,128}"))
                throw new IllegalArgumentException("invalid movie mod ID");
            Class<?> fsClass = Class.forName("zombie.ZomboidFileSystem");
            Object fs = fsClass.getField("instance").get(null);
            String modDir = (String) fsClass.getMethod("getModDir", String.class).invoke(fs, modId);
            if (modDir == null) throw new IllegalStateException("movie mod is not active: " + modId);
            Object info = fsClass.getMethod("getModInfoForDir", String.class).invoke(fs, modDir);
            String[] roots = {modInfoPath(info, "getVersionDir"), modInfoPath(info, "getCommonDir"), modDir};
            File movie = null;
            for (String root : roots) {
                if (root == null) continue;
                File base = new File(root, "media/video").getCanonicalFile();
                File candidate = new File(base, fileName).getCanonicalFile();
                if (!candidate.getPath().startsWith(base.getPath() + File.separator))
                    throw new SecurityException("movie path escapes media/video");
                if (candidate.isFile()) { movie = candidate; break; }
            }
            if (movie == null) throw new IllegalStateException("movie not found in active mod");
            selectVideo(movie);
            return true;
        } catch (Throwable e) {
            status = "movie load failed: " + e.getMessage();
            return false;
        }
    }

    private static String modInfoPath(Object info, String method) throws Exception {
        if (info == null) return null;
        Object value = info.getClass().getMethod(method).invoke(info);
        return value == null ? null : String.valueOf(value);
    }

    private static void selectVideo(File video) {
        closeVideo();
        doomMirror = false;
        nesMirror = false;
        selectedVideo = video;
        enabled = true;
        finished = false;
        nextFrameNanos = 0;
        audioClockMs = -1;
        usingAudioClock = false;
        frameNumber = 0;
        displayedFrame = 0;
        latestRequestedFrame = 0;
        status = "selected " + video.getName();
    }

    /** Private test: play a tape from the active save, never an arbitrary path. */
    public static boolean playRecording(String recordingId) {
        if (recordingId == null || !recordingId.matches("rec_[0-9]{13}_[0-9a-f]{8}")) {
            status = "invalid recording ID";
            return false;
        }
        try {
            Class<?> fsClass = Class.forName("zombie.ZomboidFileSystem");
            Object fs = fsClass.getField("instance").get(null);
            String path = (String) fsClass.getMethod("getFileNameInCurrentSave", String.class)
                .invoke(fs, "KnoxBoxRecordings/" + recordingId + ".mp4");
            File recording = new File(path).getCanonicalFile();
            if (!recording.isFile()) throw new IllegalStateException("recording missing in current save");
            selectVideo(recording);
            status = "selected recording " + recordingId;
            return true;
        } catch (Throwable e) {
            status = "recording load failed: " + e.getMessage();
            return false;
        }
    }

    public static void playProbeClip() {
        closeVideo();
        selectedVideo = null;
        enabled = true;
        finished = false;
        nextFrameNanos = 0;
        status = "selected probe clip";
    }

    public static void tick() {
        long now = System.nanoTime();
        if (gameBoyModelScript != null) {
            try { tickGameBoy(now); }
            catch (Throwable e) { gameBoyStatus = e.getClass().getSimpleName() + ": " + e.getMessage(); }
            if (now - lastGameBoyStatusLogNanos >= 5_000_000_000L) {
                lastGameBoyStatusLogNanos = now;
                System.out.println("[KBM][GB3D] " + gameBoyStatus);
            }
        }
        if (!enabled) return;
        try {
            if (doomMirror) {
                tickDoom();
                return;
            }
            if (nesMirror) {
                tickNes(now);
                return;
            }
            if (grab == null) openVideo();
            boolean clockActive = audioClockMs >= 0
                && now - lastAudioAdvanceNanos < 1_000_000_000L;
            if (clockActive) {
                int target = Math.max(1, (int) Math.floor(audioClockMs * fps / 1000.0) + 1);
                if (target <= frameNumber) return;
                // Decode and discard a bounded number of late frames. This
                // is cheaper than a precise random seek on the Spawn files.
                int skip = Math.min(target - frameNumber - 1, 12);
                for (int i = 0; i < skip; i++) {
                    if (grab.getNativeFrame() == null) {
                        enabled = false;
                        finished = true;
                        status = "finished";
                        closeVideo();
                        return;
                    }
                    frameNumber++;
                }
            } else {
                if (usingAudioClock) nextFrameNanos = 0;
                if (nextFrameNanos == 0) nextFrameNanos = now;
                if (now < nextFrameNanos) return;
                nextFrameNanos += frameNanos;
            }
            usingAudioClock = clockActive;
            Picture picture = grab.getNativeFrame();
            if (picture == null) {
                enabled = false;
                finished = true;
                status = "finished";
                closeVideo();
                return;
            }
            BufferedImage image = AWTUtil.toBufferedImage(picture);
            int sourceW = image.getWidth();
            int sourceH = image.getHeight();
            if (sourceW <= 0 || sourceH <= 0) throw new IllegalStateException("empty MP4 frame");
            long sourcePixelCount = (long) sourceW * sourceH;
            if (sourcePixelCount > Integer.MAX_VALUE) throw new IllegalStateException("MP4 frame too large");
            if (sourcePixels == null || sourcePixels.length < sourcePixelCount)
                sourcePixels = new int[(int) sourcePixelCount];
            sourcePixels = image.getRGB(0, 0, sourceW, sourceH, sourcePixels, 0, sourceW);
            queueSourceFrame(sourcePixels, sourceW, sourceH, ++frameNumber);
        } catch (Throwable e) {
            status = e.getClass().getSimpleName() + ": " + e.getMessage();
            enabled = false;
            closeVideo();
        }
    }

    private static void tickDoom() throws Exception {
        Class<?> doom = Class.forName("com.kbmbasic.KBMDoom");
        long current = ((Number) doom.getMethod("getFrameCount").invoke(null)).longValue();
        if (current < 0 || current == lastDoomFrame) return;
        int width = ((Number) doom.getMethod("getWidth").invoke(null)).intValue();
        int height = ((Number) doom.getMethod("getHeight").invoke(null)).intValue();
        if (width <= 0 || height <= 0 || (long) width * height > 1_000_000) return;
        if (doomPixelsField == null) {
            doomPixelsField = doom.getDeclaredField("pixelBuffer");
            doomPixelsField.setAccessible(true);
        }
        int[] pixels = (int[]) doomPixelsField.get(null);
        if (pixels == null || pixels.length < width * height) return;
        lastDoomFrame = current;
        queueSourceFrame(pixels, width, height, (int) Math.min(current, Integer.MAX_VALUE));
    }

    private static void tickNes(long now) throws Exception {
        // The emulator runs at 60 Hz; the world TV needs only one latest
        // frame per Viewpoint render, capped here to avoid redundant uploads.
        if (lastNesUploadNanos != 0 && now - lastNesUploadNanos < 33_000_000L) return;
        Class<?> nes = Class.forName("com.kbmbasic.KBMNes");
        int width = ((Number) nes.getMethod("getWidth").invoke(null)).intValue();
        int height = ((Number) nes.getMethod("getHeight").invoke(null)).intValue();
        if (width <= 0 || height <= 0 || (long) width * height > 1_000_000) return;
        int[] pixels = (int[]) nes.getMethod("getPixels").invoke(null);
        if (pixels == null || pixels.length < width * height) return;
        lastNesUploadNanos = now;
        queueSourceFrame(pixels, width, height, ++nesFrameSequence);
    }

    private static void tickGameBoy(long now) throws Exception {
        if (lastGameBoyUploadNanos != 0 && now - lastGameBoyUploadNanos < 66_000_000L) return;
        if (!gameBoyUploadPending.compareAndSet(false, true)) return;
        try {
        Class<?> gb = Class.forName("com.knoxboxgb.KBMGameBoy");
        if (!Boolean.TRUE.equals(gb.getMethod("isRomLoaded").invoke(null))) { gameBoyUploadPending.set(false); return; }
        int width = ((Number) gb.getMethod("getWidth").invoke(null)).intValue();
        int height = ((Number) gb.getMethod("getHeight").invoke(null)).intValue();
        if (width <= 0 || height <= 0 || (long) width * height > 1_000_000) { gameBoyUploadPending.set(false); return; }
        int[] pixels = (int[]) gb.getMethod("getPixels").invoke(null);
        if (pixels == null || pixels.length < width * height) { gameBoyUploadPending.set(false); return; }
        int[] frame = Arrays.copyOf(pixels, width * height);
        String script = gameBoyModelScript;
        int sequence = ++gameBoyFrameSequence;
        latestGameBoyRequest = sequence;
        lastGameBoyUploadNanos = now;
        RenderThread.invokeOnRenderContext(() -> {
            try {
                if (script.equals(gameBoyModelScript) && sequence == latestGameBoyRequest)
                    uploadGameBoy(frame, width, height, script, sequence);
            } catch (Throwable e) {
                gameBoyStatus = e.getClass().getSimpleName() + ": " + e.getMessage();
            } finally { gameBoyUploadPending.set(false); }
        });
        } catch (Exception | Error e) {
            gameBoyUploadPending.set(false);
            throw e;
        }
    }

    private static void uploadGameBoy(int[] frame, int sourceW, int sourceH,
                                      String script, int sequence) {
        long start = System.nanoTime();
        Texture texture = modelTexture(script);
        if (texture == null) { gameBoyStatus = "model texture not loaded: " + script; return; }
        int width = texture.getWidthHW(), height = texture.getHeightHW();
        if (width <= 0 || height <= 0 || width != height || width > 4096) {
            gameBoyStatus = "unsupported Game Boy atlas: " + width + "x" + height;
            return;
        }
        // PZ may load a lower-resolution copy of the 1024-pixel atlas.
        // Convert the LCD bounds to that copy's actual pixel coordinates.
        final int left = Math.round(92f * width / 1024f);
        final int top = Math.round(116f * height / 1024f);
        final int right = Math.round(339f * width / 1024f);
        final int bottom = Math.round(285f * height / 1024f);
        final int drawW = right - left, drawH = bottom - top;
        if (drawW <= 0 || drawH <= 0) {
            gameBoyStatus = "Game Boy LCD too small: " + width + "x" + height;
            return;
        }
        // PZ's FBX model loader reverses the mesh V coordinate relative to
        // the PNG atlas. On this held model the visible LCD samples the
        // texture's top-origin rows, not height - bottom. The full-atlas
        // diagnostic confirmed the texture target; a green fill at the old
        // bottom-origin rows never appeared on the LCD.
        final int atlasY = top;
        if (gameBoyOriginalAtlas == null
                || gameBoyTextureId != texture.getID()
                || !script.equals(gameBoyTextureScript)
                || gameBoyRegionW != drawW || gameBoyRegionH != drawH) {
            restoreGameBoyTexture();
            WrappedBuffer readback = texture.getData();
            try {
                ByteBuffer source = readback.getBuffer();
                source.rewind();
                // Save the shell for restoration and for padding around the LCD.
                gameBoyOriginalAtlas = new byte[width * height * 4];
                source.get(gameBoyOriginalAtlas);
            } finally { readback.dispose(); }
            gameBoyTextureId = texture.getID();
            gameBoyTextureScript = script;
            gameBoyRegionW = drawW;
            gameBoyRegionH = drawH;
            gameBoyRegionVerified = false;
            gameBoyRegionRejected = false;
            gameBoyRegionFailure = "";
            gameBoyLastUploadDetails = "waiting for first upload";
            gameBoyLastBindError = 0;
        }
        int diagnostic = gameBoyDiagnosticMode;
        if (gameBoyLastUploadedFrame != null
                && gameBoyLastUploadedDiagnostic == diagnostic
                && Arrays.equals(frame, gameBoyLastUploadedFrame)) {
            gameBoyStatus = "frame " + sequence + ", texture " + texture.getID()
                + ", sourceHash " + Arrays.hashCode(frame)
                + ", unchanged; skipped atlas upload; last: " + gameBoyLastUploadDetails;
            return;
        }
        if (GAME_BOY_REGION_UPLOAD_ENABLED && diagnostic == 0
                && gameBoyLastUploadedDiagnostic <= 0 && !gameBoyRegionRejected) {
            // Only the LCD changes. Bind the model's TextureID unconditionally:
            // Texture.bind() can skip GL binding based on PZ's cached ID,
            // which is not reliable across Viewpoint's render passes.
            // S3TC subimages require 4x4 alignment. At 1024 this expands
            // 247x169 to 248x172 without scaling the LCD or changing its UVs.
            // The extra pixels come from the original cabinet atlas.
            int uploadLeft = left & ~3;
            int uploadTop = atlasY & ~3;
            int uploadRight = Math.min(width, (right + 3) & ~3);
            int uploadBottom = Math.min(height, (bottom + 3) & ~3);
            int uploadW = uploadRight - uploadLeft;
            int uploadH = uploadBottom - uploadTop;
            int regionBytes = uploadW * uploadH * 4;
            if (gameBoyUploadBuffer == null || gameBoyUploadBuffer.capacity() < regionBytes)
                gameBoyUploadBuffer = ByteBuffer.allocateDirect(regionBytes);
            ByteBuffer lcd = gameBoyUploadBuffer;
            lcd.clear();
            for (int y = uploadTop; y < uploadBottom; y++) {
                lcd.put(gameBoyOriginalAtlas, (y * width + uploadLeft) * 4, uploadW * 4);
            }
            for (int y = 0; y < drawH; y++) {
                int sourceY = y * sourceH / drawH;
                for (int x = 0; x < drawW; x++) {
                    int argb = frame[sourceY * sourceW + x * sourceW / drawW];
                    int index = ((atlasY + y - uploadTop) * uploadW + left + x - uploadLeft) * 4;
                    lcd.put(index, (byte) (argb >>> 16));
                    lcd.put(index + 1, (byte) (argb >>> 8));
                    lcd.put(index + 2, (byte) argb);
                    lcd.put(index + 3, (byte) 255);
                }
            }
            lcd.flip();
            TextureID textureId = texture.getTextureId();
            if (textureId != null) {
                int unpackAlignment = GL11.glGetInteger(GL11.GL_UNPACK_ALIGNMENT);
                int unpackRowLength = GL11.glGetInteger(GL11.GL_UNPACK_ROW_LENGTH);
                int unpackSkipRows = GL11.glGetInteger(GL11.GL_UNPACK_SKIP_ROWS);
                int unpackSkipPixels = GL11.glGetInteger(GL11.GL_UNPACK_SKIP_PIXELS);
                GL11.glPixelStorei(GL11.GL_UNPACK_ALIGNMENT, 1);
                GL11.glPixelStorei(GL11.GL_UNPACK_ROW_LENGTH, 0);
                GL11.glPixelStorei(GL11.GL_UNPACK_SKIP_ROWS, 0);
                GL11.glPixelStorei(GL11.GL_UNPACK_SKIP_PIXELS, 0);
                GL11.glGetError();
                int bindError;
                int boundTexture;
                int unpackBuffer;
                int levelWidth;
                int levelHeight;
                int internalFormat;
                int queryError;
                int uploadError;
                try {
                    textureId.bindalways();
                    bindError = GL11.glGetError();
                    gameBoyLastBindError = bindError;
                    boundTexture = GL11.glGetInteger(GL11.GL_TEXTURE_BINDING_2D);
                    unpackBuffer = GL11.glGetInteger(GL11.GL_PIXEL_UNPACK_BUFFER_BINDING);
                    levelWidth = GL11.glGetTexLevelParameteri(GL11.GL_TEXTURE_2D, 0, GL11.GL_TEXTURE_WIDTH);
                    levelHeight = GL11.glGetTexLevelParameteri(GL11.GL_TEXTURE_2D, 0, GL11.GL_TEXTURE_HEIGHT);
                    internalFormat = GL11.glGetTexLevelParameteri(GL11.GL_TEXTURE_2D, 0, GL11.GL_TEXTURE_INTERNAL_FORMAT);
                    queryError = GL11.glGetError();
                    GL11.glTexSubImage2D(GL11.GL_TEXTURE_2D, 0, uploadLeft, uploadTop,
                            uploadW, uploadH, GL11.GL_RGBA, GL11.GL_UNSIGNED_BYTE, lcd);
                    uploadError = GL11.glGetError();
                } finally {
                    GL11.glPixelStorei(GL11.GL_UNPACK_ALIGNMENT, unpackAlignment);
                    GL11.glPixelStorei(GL11.GL_UNPACK_ROW_LENGTH, unpackRowLength);
                    GL11.glPixelStorei(GL11.GL_UNPACK_SKIP_ROWS, unpackSkipRows);
                    GL11.glPixelStorei(GL11.GL_UNPACK_SKIP_PIXELS, unpackSkipPixels);
                }
                String details = "bind GL " + bindError + ", upload GL " + uploadError
                    + ", bound " + boundTexture + "/" + texture.getID()
                    + ", PBO " + unpackBuffer + ", level " + levelWidth + "x" + levelHeight
                    + " format 0x" + Integer.toHexString(internalFormat) + " query GL " + queryError
                    + ", region " + uploadLeft + "/" + uploadTop + "/" + uploadW + "/" + uploadH
                    + ", bytes " + lcd.remaining();
                if (bindError != 0 || queryError != 0 || uploadError != 0 || boundTexture != texture.getID()) {
                    gameBoyRegionRejected = true;
                    gameBoyRegionFailure = details
                        + " (unpack " + unpackAlignment + "/" + unpackRowLength
                        + "/" + unpackSkipRows + "/" + unpackSkipPixels + ")";
                    System.out.println("[KBM][GB3D] aligned region rejected: " + gameBoyRegionFailure);
                }
                if (!gameBoyRegionRejected && !gameBoyRegionVerified) {
                    // Compression is lossy: exact readback equality would reject
                    // valid uploads. GL acceptance is logged here; appearance is
                    // checked in game. No synchronous per-frame GPU readback.
                    gameBoyRegionVerified = true;
                    System.out.println("[KBM][GB3D] aligned region accepted: " + details);
                }
            } else {
                gameBoyRegionRejected = true;
                gameBoyRegionFailure = "missing TextureID";
            }
            if (!gameBoyRegionRejected) {
                gameBoyLastUploadedFrame = frame;
                gameBoyLastUploadedDiagnostic = diagnostic;
                gameBoyLastUploadDetails = "aligned region " + uploadW + "x" + uploadH
                    + ", upload " + ((System.nanoTime() - start) / 1_000_000.0) + " ms, GL 0";
                gameBoyStatus = "frame " + sequence + ", texture " + texture.getID()
                    + " (" + texture.getName() + ")"
                    + ", LCD " + drawW + "x" + drawH + " in " + width + "x" + height
                    + ", sourceHash " + Arrays.hashCode(frame)
                    + ", " + gameBoyLastUploadDetails;
                return;
            }
        }
        int byteCount = width * height * 4;
        if (gameBoyUploadBuffer == null || gameBoyUploadBuffer.capacity() < byteCount)
            gameBoyUploadBuffer = ByteBuffer.allocateDirect(byteCount);
        ByteBuffer output = gameBoyUploadBuffer;
        output.clear();
        output.put(gameBoyOriginalAtlas);
        for (int y = 0; y < drawH; y++) {
            int sourceY = y * sourceH / drawH;
            for (int x = 0; x < drawW; x++) {
                int argb = frame[sourceY * sourceW + x * sourceW / drawW];
                int index = ((atlasY + y) * width + left + x) * 4;
                output.put(index, (byte) (argb >>> 16));
                output.put(index + 1, (byte) (argb >>> 8));
                output.put(index + 2, (byte) argb);
                output.put(index + 3, (byte) 255);
            }
        }
        if (diagnostic != 0) {
            int x0 = diagnostic == 1 ? 0 : left;
            int y0 = diagnostic == 1 ? 0 : atlasY;
            int x1 = diagnostic == 1 ? width : left + drawW;
            int y1 = diagnostic == 1 ? height : atlasY + drawH;
            for (int y = y0; y < y1; y++) {
                for (int x = x0; x < x1; x++) {
                    int index = (y * width + x) * 4;
                    output.put(index, (byte) (diagnostic == 1 ? 255 : 0));
                    output.put(index + 1, (byte) (diagnostic == 2 ? 255 : 0));
                    output.put(index + 2, (byte) (diagnostic == 1 ? 255 : 0));
                    output.put(index + 3, (byte) 255);
                }
            }
        }
        output.flip();
        long prepared = System.nanoTime();
        int previousError = GL11.glGetError();
        long transferStart = System.nanoTime();
        texture.setData(output);
        long transferred = System.nanoTime();
        int glError = GL11.glGetError();
        if (glError == 0) {
            gameBoyLastUploadedFrame = frame;
            gameBoyLastUploadedDiagnostic = diagnostic;
        }
        gameBoyLastUploadDetails = "full atlas, prepare " + ((prepared - start) / 1_000_000.0)
            + " ms, transfer " + ((transferred - transferStart) / 1_000_000.0)
            + " ms, GL " + glError
            + (gameBoyRegionRejected ? ", region rejected: " + gameBoyRegionFailure : "");
        gameBoyStatus = "frame " + sequence + ", texture " + texture.getID()
            + " (" + texture.getName() + ")"
            + ", atlas " + width + "x" + height
            + ", sourceHash " + Arrays.hashCode(frame)
            + ", diagnostic " + diagnostic
            + (gameBoyRegionRejected ? ", region rejected: " + gameBoyRegionFailure : "")
            + ", prepare " + ((prepared - start) / 1_000_000.0)
            + " ms, transfer " + ((transferred - transferStart) / 1_000_000.0)
            + " ms, GL error before/after " + previousError + "/" + glError;
    }

    private static void restoreGameBoyTexture() {
        if (gameBoyOriginalAtlas == null
                || gameBoyTextureScript == null) return;
        Texture texture = modelTexture(gameBoyTextureScript);
        if (texture != null && texture.getID() == gameBoyTextureId) {
            ByteBuffer original = gameBoyUploadBuffer;
            byte[] saved = gameBoyOriginalAtlas;
            if (original == null || original.capacity() < saved.length)
                original = ByteBuffer.allocateDirect(saved.length);
            original.clear();
            original.put(saved).flip();
            texture.setData(original);
        }
        gameBoyOriginalAtlas = null;
        gameBoyLastUploadedFrame = null;
        gameBoyLastUploadedDiagnostic = -1;
        gameBoyLastUploadDetails = "waiting for first upload";
        gameBoyTextureId = -1;
        gameBoyTextureScript = null;
        gameBoyRegionW = gameBoyRegionH = 0;
        gameBoyRegionVerified = false;
        gameBoyRegionRejected = false;
        gameBoyRegionFailure = "";
        gameBoyLastBindError = 0;
    }

    private static void queueSourceFrame(int[] source, int sourceW, int sourceH, int number) {
            if (framePixels == null) framePixels = new int[SIZE * SCREEN_HEIGHT];
            Arrays.fill(framePixels, 0xff000000);
            double scale = Math.min((double) SIZE / sourceW, (double) SCREEN_HEIGHT / sourceH);
            int drawW = Math.max(1, Math.min(SIZE, (int) Math.round(sourceW * scale)));
            int drawH = Math.max(1, Math.min(SCREEN_HEIGHT, (int) Math.round(sourceH * scale)));
            int left = (SIZE - drawW) / 2;
            int top = (SCREEN_HEIGHT - drawH) / 2;
            for (int y = 0; y < drawH; y++) {
                int sourceY = Math.min(sourceH - 1, y * sourceH / drawH);
                for (int x = 0; x < drawW; x++) {
                    int sourceX = Math.min(sourceW - 1, x * sourceW / drawW);
                    framePixels[(top + y) * SIZE + left + x] = 0xff000000 | source[sourceY * sourceW + sourceX];
                }
            }
            int[] pixels = framePixels.clone();
            latestRequestedFrame = number;
            RenderThread.invokeOnRenderContext(() -> {
                if (number == latestRequestedFrame) upload(pixels, number);
            });
    }

    private static void openVideo() throws Exception {
        File video = selectedVideo;
        if (video == null) throw new IllegalStateException("No movie selected");
        if (!video.isFile()) throw new IllegalStateException("probe MP4 missing: " + video);
        channel = NIOUtils.readableChannel(video);
        grab = FrameGrab.createFrameGrab(channel);
        int total = grab.getVideoTrack().getMeta().getTotalFrames();
        double duration = grab.getVideoTrack().getMeta().getTotalDuration();
        fps = total > 0 && duration > 0 ? total / duration : 12;
        frameNanos = (long) (1_000_000_000.0 / Math.max(1, Math.min(60, fps)));
        frameNumber = 0;
    }

    private static void closeVideo() {
        grab = null;
        if (channel != null) try { channel.close(); } catch (Exception ignored) {}
        channel = null;
    }

    private static void blankScreen() {
        int[] black = new int[SIZE * SCREEN_HEIGHT];
        Arrays.fill(black, 0xff000000);
        latestRequestedFrame = 0;
        RenderThread.invokeOnRenderContext(() -> upload(black, 0));
    }

    private static void upload(int[] frame, int number) {
        String selectedModel = tvDisplayModel;
        boolean clear = number == 0;
        Texture texture = clear || MODEL_SCRIPT.equals(selectedModel) ? modelTexture() : null;
        Texture legacyTexture = clear || LEGACY_MODEL_SCRIPT.equals(selectedModel)
            ? modelTexture(LEGACY_MODEL_SCRIPT) : null;
        Texture playingTexture = clear || PLAYING_MODEL_SCRIPT.equals(selectedModel)
            ? modelTexture(PLAYING_MODEL_SCRIPT) : null;
        Texture legacyPlayingTexture = clear || LEGACY_PLAYING_MODEL_SCRIPT.equals(selectedModel)
            ? modelTexture(LEGACY_PLAYING_MODEL_SCRIPT) : null;
        if (texture == null && legacyTexture == null
                && playingTexture == null && legacyPlayingTexture == null) {
            status = "TV model textures not loaded";
            return;
        }
        if (texture != null) uploadTexture(texture, frame, number, false);
        if (legacyTexture != null && (texture == null || legacyTexture.getID() != texture.getID())) {
            uploadTexture(legacyTexture, frame, number, true);
        }
        if (playingTexture != null) uploadTexture(playingTexture, frame, number, false);
        if (legacyPlayingTexture != null && (playingTexture == null
                || legacyPlayingTexture.getID() != playingTexture.getID())) {
            uploadTexture(legacyPlayingTexture, frame, number, true);
        }
        displayedFrame = number;
    }

    private static void uploadTexture(Texture texture, int[] frame, int number,
            boolean legacy) {
        int width = texture.getWidthHW();
        int height = texture.getHeightHW();
        if (width < 16 || width > 4096 || height < 16 || height > 4096) {
            status = "unexpected TV texture size: " + width + "x" + height;
            return;
        }
        int cabinetRows = (height + 3) / 4;
        byte[] cabinet = legacy ? legacyCabinetPixels : cabinetPixels;
        int cachedId = legacy ? legacyCabinetTextureId : cabinetTextureId;
        int cachedWidth = legacy ? legacyCabinetWidth : cabinetWidth;
        int cachedHeight = legacy ? legacyCabinetHeight : cabinetHeight;
        if (cabinet == null || cachedId != texture.getID()
                || cachedWidth != width || cachedHeight != height) {
            WrappedBuffer readback = texture.getData();
            try {
                ByteBuffer source = readback.getBuffer();
                source.rewind();
                cabinet = new byte[cabinetRows * width * 4];
                source.get(cabinet);
            } finally {
                readback.dispose();
            }
            if (legacy) {
                legacyCabinetPixels = cabinet;
                legacyCabinetTextureId = texture.getID();
                legacyCabinetWidth = width;
                legacyCabinetHeight = height;
            } else {
                cabinetPixels = cabinet;
                cabinetTextureId = texture.getID();
                cabinetWidth = width;
                cabinetHeight = height;
            }
        }
        int byteCount = width * height * 4;
        ByteBuffer pixels = legacy ? legacyTvUploadBuffer : tvUploadBuffer;
        if (pixels == null || pixels.capacity() != byteCount) {
            pixels = ByteBuffer.allocateDirect(byteCount);
            if (legacy) legacyTvUploadBuffer = pixels; else tvUploadBuffer = pixels;
        }
        pixels.clear();
        pixels.put(cabinet);
        for (int y = cabinetRows; y < height; y++) {
            int sourceY = y * SIZE / height;
            for (int x = 0; x < width; x++) {
                int sourceX = x * SIZE / width;
                // The bottom quarter of GL texture data is the cabinet;
                // preserve its exact original pixels and replace only video.
                int argb = frame[(sourceY - (SIZE - SCREEN_HEIGHT)) * SIZE + sourceX];
                int r = (argb >>> 16) & 255;
                int g = (argb >>> 8) & 255;
                int b = argb & 255;
                // The private Viewpoint pack recognizes the same alpha marker
                // as the projector. Keep the cabinet and idle screen opaque.
                int alpha = number > 0 ? 253 : 255;
                pixels.put((byte) r).put((byte) g).put((byte) b).put((byte) alpha);
            }
        }
        pixels.flip();
        texture.setData(pixels);
        if (!legacy && (number == 1 || number % 120 == 0)) {
            status = (doomMirror ? "Doom frame " : nesMirror ? "NES frame " : "MP4 frame ")
                + number
                + ", GL texture " + texture.getID() + ", " + width + "x" + height;
        }
    }

    private static Texture modelTexture() {
        return modelTexture(MODEL_SCRIPT);
    }

    private static Texture modelTexture(String modelScript) {
        try {
            // PZ's model loader can use texture flags that create a separate
            // Texture from getSharedTexture(path). Upload to the model's own
            // Texture so the world TV actually receives each video frame.
            Class<?> scripts = Class.forName("zombie.scripting.ScriptManager");
            Object scriptManager = scripts.getField("instance").get(null);
            Object script = scripts.getMethod("getModelScript", String.class)
                .invoke(scriptManager, modelScript);
            if (script == null) return null;
            Class<?> modelScripts = Class.forName("zombie.scripting.objects.ModelScript");
            Class<?> models = Class.forName("zombie.core.skinnedmodel.ModelManager");
            Object modelManager = models.getField("instance").get(null);
            Object model = models.getMethod("tryGetLoadedModel", modelScripts, boolean.class)
                .invoke(modelManager, script, false);
            if (model != null) {
                return (Texture) model.getClass().getField("tex").get(model);
            }
            return null;
        } catch (ReflectiveOperationException e) {
            status = "TV model lookup failed: " + e.getMessage();
            return null;
        }
    }
}
