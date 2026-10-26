package org.lwjgl.opengl;

import java.nio.ByteBuffer;

/** Compile-only signature stub; never packaged in the probe jar. */
public final class GL11 {
    public static final int GL_TEXTURE_2D = 3553;
    public static final int GL_TEXTURE_BINDING_2D = 32873;
    public static final int GL_TEXTURE_WIDTH = 4096;
    public static final int GL_TEXTURE_HEIGHT = 4097;
    public static final int GL_TEXTURE_INTERNAL_FORMAT = 4099;
    public static final int GL_PIXEL_UNPACK_BUFFER_BINDING = 0x88EF;
    public static final int GL_RGBA = 6408;
    public static final int GL_UNSIGNED_BYTE = 5121;
    public static final int GL_UNPACK_ALIGNMENT = 3317;
    public static final int GL_UNPACK_ROW_LENGTH = 3314;
    public static final int GL_UNPACK_SKIP_ROWS = 3315;
    public static final int GL_UNPACK_SKIP_PIXELS = 3316;

    public static int glGetError() { throw new UnsupportedOperationException(); }
    public static int glGetInteger(int name) { throw new UnsupportedOperationException(); }
    public static int glGetTexLevelParameteri(int target, int level, int name) {
        throw new UnsupportedOperationException();
    }
    public static void glPixelStorei(int name, int value) { throw new UnsupportedOperationException(); }
    public static void glReadBuffer(int buffer) { throw new UnsupportedOperationException(); }
    public static void glReadPixels(int x, int y, int width, int height, int format, int type,
            ByteBuffer pixels) { throw new UnsupportedOperationException(); }
    public static void glTexSubImage2D(int target, int level, int xoffset, int yoffset,
            int width, int height, int format, int type, ByteBuffer pixels) {
        throw new UnsupportedOperationException();
    }
}
