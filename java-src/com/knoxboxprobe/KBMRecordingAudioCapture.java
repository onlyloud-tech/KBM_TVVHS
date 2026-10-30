// Copyright (c) 2026 Grymlock. All rights reserved.
// SPDX-License-Identifier: LicenseRef-KnoxBox-Original-Content
// See LICENSES/KnoxBox-License.md and LICENSES/Java/KnoxBox-Bridges.md.
package com.knoxboxprobe;

import java.io.BufferedOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Arrays;
import java.util.concurrent.TimeUnit;
import javax.sound.sampled.AudioFormat;
import javax.sound.sampled.AudioFileFormat;
import javax.sound.sampled.AudioInputStream;
import javax.sound.sampled.AudioSystem;

/** Windows-only same-session capture of PZ output and an opted-in default mic. */
final class KBMRecordingAudioCapture {
    private static final int RATE = 44100;
    private static final long MAX_RECORDING_MS = 600_000L;
    private static final int MIX_FRAMES = 4096;
    private static final AudioFormat STEREO = new AudioFormat(RATE, 16, 2, true, false);
    private static final AudioFormat MONO = new AudioFormat(RATE, 16, 1, true, false);
    private final Path directory;
    private final String id;
    private final Process process;
    private final Path game;
    private final Path mic;
    private final Path mixed;
    private final boolean microphoneEnabled;

    private KBMRecordingAudioCapture(Path directory, String id, Process process,
            boolean microphoneEnabled) {
        this.directory = directory;
        this.id = id;
        this.process = process;
        game = directory.resolve(id + ".game.wav");
        mic = directory.resolve(id + ".mic.wav");
        mixed = directory.resolve(id + ".wav");
        this.microphoneEnabled = microphoneEnabled;
    }

    static KBMRecordingAudioCapture start(Path directory, String id,
            boolean microphoneEnabled) throws Exception {
        if (!System.getProperty("os.name", "").toLowerCase().contains("windows"))
            throw new IllegalStateException("audio capture requires Windows");
        Path helper = directory.resolve("KBMAudioCapture.exe");
        try (InputStream source = KBMRecordingAudioCapture.class.getResourceAsStream(
                "KBMAudioCapture.exe")) {
            if (source == null) throw new IllegalStateException("audio capture helper missing");
            Files.copy(source, helper, StandardCopyOption.REPLACE_EXISTING);
        }
        Path game = directory.resolve(id + ".game.wav");
        Path mic = directory.resolve(id + ".mic.wav");
        ProcessBuilder builder = microphoneEnabled
            ? new ProcessBuilder(helper.toString(),
                Long.toString(ProcessHandle.current().pid()), "includetree",
                game.toString(), "600", mic.toString())
            : new ProcessBuilder(helper.toString(),
                Long.toString(ProcessHandle.current().pid()), "includetree",
                game.toString(), "600");
        builder.redirectErrorStream(true);
        builder.redirectOutput(directory.resolve(id + ".capture.log").toFile());
        return new KBMRecordingAudioCapture(directory, id, builder.start(), microphoneEnabled);
    }

    void stop() {
        if (!process.isAlive()) return;
        try {
            process.getOutputStream().write('\n');
            process.getOutputStream().flush();
        } catch (Exception ignored) {}
    }

    boolean finish(long targetMs) throws Exception {
        stop();
        if (!process.waitFor(5, TimeUnit.SECONDS)) {
            process.destroy();
            if (!process.waitFor(1, TimeUnit.SECONDS)) process.destroyForcibly();
            throw new IllegalStateException("audio capture helper did not stop");
        }
        if (process.exitValue() != 0 || !Files.isRegularFile(game))
            throw new IllegalStateException("game audio capture failed; see " + id + ".capture.log");
        boolean hasAudio = mix(game, microphoneEnabled ? mic : null, mixed, targetMs);
        Files.deleteIfExists(game);
        Files.deleteIfExists(mic);
        return hasAudio;
    }

    static boolean mix(Path game, Path mic, Path output, long targetMs) throws Exception {
        if (targetMs <= 0 || targetMs > MAX_RECORDING_MS)
            throw new IllegalArgumentException("invalid recording length");
        int frames = Math.toIntExact(targetMs * RATE / 1000);
        byte[] gameBytes = new byte[MIX_FRAMES * 4];
        byte[] micBytes = new byte[MIX_FRAMES * 2];
        byte[] outputBytes = new byte[MIX_FRAMES * 4];
        boolean hasAudio = false;
        Path partial = output.resolveSibling(output.getFileName() + ".part");
        try (AudioInputStream gameStream = openPcm(game, STEREO)) {
            AudioInputStream micStream = null;
            if (mic != null && Files.isRegularFile(mic)) {
                try { micStream = openPcm(mic, MONO); }
                catch (Exception failure) {
                    System.out.println("[KBM][Camera] microphone capture unusable; "
                        + "using game audio only: " + failure.getMessage());
                }
            } else if (mic == null) {
                System.out.println("[KBM][Camera] microphone disabled; using game audio only");
            } else {
                System.out.println("[KBM][Camera] microphone unavailable; using game audio only");
            }
            try (OutputStream stream = new BufferedOutputStream(Files.newOutputStream(partial))) {
                writeWavHeader(stream, frames);
                for (int offset = 0; offset < frames; offset += MIX_FRAMES) {
                    int count = Math.min(MIX_FRAMES, frames - offset);
                    readOrSilence(gameStream, gameBytes, count * 4);
                    readOrSilence(micStream, micBytes, count * 2);
                    for (int frame = 0; frame < count; frame++) {
                        int micValue = sample(micBytes, frame * 2);
                        for (int channel = 0; channel < 2; channel++) {
                            int index = frame * 4 + channel * 2;
                            int value = Math.max(-32768, Math.min(32767,
                                sample(gameBytes, index) + Math.round(micValue * 0.7f)));
                            if (value != 0) hasAudio = true;
                            outputBytes[index] = (byte) value;
                            outputBytes[index + 1] = (byte) (value >>> 8);
                        }
                    }
                    stream.write(outputBytes, 0, count * 4);
                }
            } finally {
                if (micStream != null) micStream.close();
            }
        } catch (Exception failure) {
            Files.deleteIfExists(partial);
            throw failure;
        }
        if (!hasAudio) {
            Files.deleteIfExists(partial);
            System.out.println("[KBM][Camera] no audio signal captured; saving video without audio");
            return false;
        }
        Files.move(partial, output, StandardCopyOption.REPLACE_EXISTING);
        return true;
    }

    private static AudioInputStream openPcm(Path file, AudioFormat expected) throws Exception {
        AudioInputStream stream = AudioSystem.getAudioInputStream(file.toFile());
        try {
            AudioFormat actual = stream.getFormat();
            if (actual.getSampleRate() != expected.getSampleRate() ||
                actual.getChannels() != expected.getChannels() ||
                actual.getSampleSizeInBits() != 16 || actual.isBigEndian() ||
                actual.getEncoding() != AudioFormat.Encoding.PCM_SIGNED)
                throw new IllegalStateException("unexpected capture WAV format: " + actual);
            return stream;
        } catch (Exception failure) {
            stream.close();
            throw failure;
        }
    }

    private static void readOrSilence(AudioInputStream stream, byte[] target, int bytes)
            throws Exception {
        int offset = 0;
        if (stream != null) {
            while (offset < bytes) {
                int count = stream.read(target, offset, bytes - offset);
                if (count < 0) break;
                if (count == 0) continue;
                offset += count;
            }
        }
        Arrays.fill(target, offset, bytes, (byte) 0);
    }

    private static void writeWavHeader(OutputStream stream, int frames) throws Exception {
        int dataBytes = Math.multiplyExact(frames, 4);
        ByteBuffer header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN);
        header.put(new byte[] { 'R', 'I', 'F', 'F' }).putInt(dataBytes + 36);
        header.put(new byte[] { 'W', 'A', 'V', 'E', 'f', 'm', 't', ' ' });
        header.putInt(16).putShort((short) 1).putShort((short) 2);
        header.putInt(RATE).putInt(RATE * 4).putShort((short) 4).putShort((short) 16);
        header.put(new byte[] { 'd', 'a', 't', 'a' }).putInt(dataBytes);
        stream.write(header.array());
    }

    private static int sample(byte[] bytes, int offset) {
        return (short) ((bytes[offset] & 255) | (bytes[offset + 1] << 8));
    }
}
