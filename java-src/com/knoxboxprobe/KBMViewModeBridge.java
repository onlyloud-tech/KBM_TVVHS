package com.knoxboxprobe;

import java.lang.reflect.Field;
import me.zed_0xff.zombie_buddy.Exposer;

/** Optional Viewpoint integration; never changes the player's camera. */
@Exposer.LuaClass(name = "KBMViewModeBridge")
public final class KBMViewModeBridge {
    private KBMViewModeBridge() {}

    public static boolean isViewpointActive() {
        try {
            Field enabled = Class.forName("viewpoint.core.View").getField("enabled");
            return enabled.getBoolean(null);
        } catch (ReflectiveOperationException | LinkageError unavailable) {
            return false;
        }
    }
}
