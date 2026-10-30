// Copyright (c) 2026 Grymlock. All rights reserved.
// SPDX-License-Identifier: LicenseRef-KnoxBox-Original-Content
// See LICENSES/KnoxBox-License.md and LICENSES/Java/KnoxBox-Bridges.md.
package com.knoxboxprobe;

import java.awt.image.BufferedImage;
import java.io.File;
import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.UUID;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.TimeUnit;
import me.zed_0xff.zombie_buddy.Exposer;
import org.jcodec.api.awt.AWTSequenceEncoder;
import org.lwjgl.opengl.GL11;
import zombie.ZomboidFileSystem;
import zombie.core.Core;
import zombie.core.opengl.RenderThread;

/** First single-player proof of in-game, save-local movie capture. */
@Exposer.LuaClass(name = "KBMCameraRecorder")
public final class KBMCameraRecorder {
    private static final int WIDTH = 960;
    private static final int HEIGHT = 540;
    private static final int FPS = 12;
    private static final int MAX_SECONDS = 600;
    private static final long FRAME_NANOS = 1_000_000_000L / FPS;
    private static final ArrayBlockingQueue<BufferedImage> QUEUE = new ArrayBlockingQueue<>(8);

    private static volatile boolean recording;
    private static volatile boolean finalizing;
    private static volatile String status = "idle";
    private static volatile String error = "";
    private static volatile String recordingId = "";
    private static volatile String readyId = "";
    private static volatile int captured;
    private static volatile int encoded;
    private static volatile int dropped;
    private static volatile boolean capturedAudio;
    private static volatile long startedNanos;
    private static long nextFrameNanos;
    private static ByteBuffer readback;
    private static int readbackWidth;
    private static int readbackHeight;
    private static KBMRecordingAudioCapture audioCapture;

    private KBMCameraRecorder() {}

    public static synchronized boolean start() {
        if (recording || finalizing) return fail("recording or finalization already active");
        try {
            recordingId = "rec_" + System.currentTimeMillis() + "_"
                + UUID.randomUUID().toString().substring(0, 8);
            Path movie = recordingPath(recordingId);
            Files.createDirectories(movie.getParent());
            audioCapture = KBMRecordingAudioCapture.start(movie.getParent(), recordingId,
                Core.getInstance().getOptionVoiceEnable());
            QUEUE.clear();
            readyId = "";
            error = "";
            captured = 0;
            encoded = 0;
            dropped = 0;
            capturedAudio = false;
            startedNanos = System.nanoTime();
            nextFrameNanos = startedNanos;
            recording = true;
            status = "recording";
            Thread worker = new Thread(() -> encode(movie), "KBM-camera-encoder");
            worker.setDaemon(true);
            worker.start();
            return true;
        } catch (Throwable failure) {
            return fail(failure.getClass().getSimpleName() + ": " + failure.getMessage());
        }
    }

    public static void captureTick() {
        if (!recording) return;
        long now = System.nanoTime();
        if (now < nextFrameNanos) return;
        nextFrameNanos = now + FRAME_NANOS;
        if ((now - startedNanos) >= MAX_SECONDS * 1_000_000_000L) {
            stop();
            return;
        }
        try {
            final BufferedImage[] frame = new BufferedImage[1];
            RenderThread.invokeOnRenderContext(() -> frame[0] = grabFrame());
            if (frame[0] != null) {
                if (QUEUE.offer(frame[0])) captured++;
                else dropped++;
            }
        } catch (Throwable failure) {
            fail(failure.getClass().getSimpleName() + ": " + failure.getMessage());
            stop();
        }
    }

    private static BufferedImage grabFrame() {
        int screenWidth = Core.getInstance().getScreenWidth();
        int screenHeight = Core.getInstance().getScreenHeight();
        if (screenWidth < WIDTH || screenHeight < HEIGHT
            || (long) screenWidth * screenHeight > 16_777_216L) {
            throw new IllegalStateException("unsupported capture size " + screenWidth + "x" + screenHeight);
        }
        int bytes = Math.multiplyExact(Math.multiplyExact(screenWidth, screenHeight), 4);
        if (readback == null || readbackWidth != screenWidth || readbackHeight != screenHeight) {
            readback = ByteBuffer.allocateDirect(bytes);
            readbackWidth = screenWidth;
            readbackHeight = screenHeight;
        }
        readback.clear();
        int oldBuffer = GL11.glGetInteger(0x0C02); // GL_READ_BUFFER
        int oldAlignment = GL11.glGetInteger(0x0D05); // GL_PACK_ALIGNMENT
        try {
            GL11.glPixelStorei(0x0D05, 1);
            GL11.glReadBuffer(0x0404); // GL_FRONT, matching PZ's full screenshot path
            GL11.glReadPixels(0, 0, screenWidth, screenHeight,
                0x1908, 0x1401, readback); // GL_RGBA, GL_UNSIGNED_BYTE
        } finally {
            GL11.glReadBuffer(oldBuffer);
            GL11.glPixelStorei(0x0D05, oldAlignment);
        }
        double scale = Math.min(screenWidth / (double) WIDTH, screenHeight / (double) HEIGHT);
        int cropWidth = Math.min(screenWidth, (int) Math.round(WIDTH * scale));
        int cropHeight = Math.min(screenHeight, (int) Math.round(HEIGHT * scale));
        int cropX = (screenWidth - cropWidth) / 2;
        int cropY = (screenHeight - cropHeight) / 2;
        BufferedImage frame = new BufferedImage(WIDTH, HEIGHT, BufferedImage.TYPE_INT_RGB);
        int[] rgb = new int[WIDTH * HEIGHT];
        for (int y = 0; y < HEIGHT; y++) {
            int sourceY = screenHeight - 1 - (cropY + y * cropHeight / HEIGHT);
            for (int x = 0; x < WIDTH; x++) {
                int sourceX = cropX + x * cropWidth / WIDTH;
                int offset = (sourceY * screenWidth + sourceX) * 4;
                rgb[y * WIDTH + x] = ((readback.get(offset) & 255) << 16)
                    | ((readback.get(offset + 1) & 255) << 8)
                    | (readback.get(offset + 2) & 255);
            }
        }
        frame.setRGB(0, 0, WIDTH, HEIGHT, rgb, 0, WIDTH);
        return frame;
    }

    private static void encode(Path movie) {
        Path partial = movie.resolveSibling(movie.getFileName().toString() + ".part.mp4");
        try {
            AWTSequenceEncoder encoder = AWTSequenceEncoder.createSequenceEncoder(partial.toFile(), FPS);
            while (recording || !QUEUE.isEmpty()) {
                BufferedImage frame = QUEUE.poll(200, TimeUnit.MILLISECONDS);
                if (frame == null) continue;
                encoder.encodeImage(frame);
                encoded++;
            }
            if (encoded == 0) {
                Files.deleteIfExists(partial);
                fail("no frames were captured");
                return;
            }
            encoder.finish();
            Files.move(partial, movie, StandardCopyOption.REPLACE_EXISTING);
            if (audioCapture != null)
                capturedAudio = audioCapture.finish(Math.min(MAX_SECONDS * 1000L,
                    Math.max(1L, Math.round(encoded * 1000.0 / FPS))));
            readyId = recordingId;
            status = "ready";
        } catch (Throwable failure) {
            recording = false;
            fail(failure.getClass().getSimpleName() + ": " + failure.getMessage());
            try { Files.deleteIfExists(partial); } catch (Exception ignored) {}
        } finally {
            if (audioCapture != null) audioCapture.stop();
            audioCapture = null;
            finalizing = false;
        }
    }

    public static synchronized void stop() {
        if (!recording) return;
        recording = false;
        finalizing = true;
        status = "finalizing";
        if (audioCapture != null) audioCapture.stop();
    }

    private static Path recordingPath(String id) {
        if (id == null || !id.matches("rec_[0-9]{13}_[0-9a-f]{8}"))
            throw new IllegalArgumentException("invalid recording id");
        String path = ZomboidFileSystem.instance.getFileNameInCurrentSave(
            "KnoxBoxRecordings/" + id + ".mp4");
        if (path == null) throw new IllegalStateException("no active save directory");
        return new File(path).toPath().toAbsolutePath().normalize();
    }

    public static synchronized boolean consumeReady(String id) {
        if (id != null && id.equals(readyId) && !finalizing) {
            readyId = "";
            return true;
        }
        return false;
    }

    public static boolean isRecording() { return recording; }
    public static boolean isFinalizing() { return finalizing; }
    public static String getRecordingId() { return recordingId; }
    public static String getStatus() { return status; }
    public static String getError() { return error; }
    public static int getCapturedFrames() { return captured; }
    public static int getEncodedFrames() { return encoded; }
    public static int getDroppedFrames() { return dropped; }
    public static boolean hasCapturedAudio() { return capturedAudio; }
    public static String getBridgeVersion() { return "KBMCameraRecorder-2026-10-10-6-ten-minute-recording"; }

    private static boolean fail(String message) {
        error = message;
        status = "error";
        return false;
    }
}
