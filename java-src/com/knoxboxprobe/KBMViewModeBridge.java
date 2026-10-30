// Copyright (c) 2026 Grymlock. All rights reserved.
// SPDX-License-Identifier: LicenseRef-KnoxBox-Original-Content
// See LICENSES/KnoxBox-License.md and LICENSES/Java/KnoxBox-Bridges.md.
package com.knoxboxprobe;

import java.lang.reflect.Field;
import me.zed_0xff.zombie_buddy.Exposer;

/** Optional Viewpoint integration; never changes the player's camera. */
@Exposer.LuaClass(name = "KBMViewModeBridge")
public final class KBMViewModeBridge {
    private static volatile Field enabledField;
    private static volatile long retryAfterNanos;
    private KBMViewModeBridge() {}

    public static boolean isViewpointActive() {
        try {
            Field enabled = enabledField;
            if (enabled == null) {
                if (System.nanoTime() < retryAfterNanos) return false;
                enabled = Class.forName("viewpoint.core.View").getField("enabled");
                enabledField = enabled;
            }
            return enabled.getBoolean(null);
        } catch (ReflectiveOperationException | LinkageError unavailable) {
            enabledField = null;
            // Viewpoint is optional. Avoid an exception per frame while absent,
            // but retry so late initialization can still recover.
            retryAfterNanos = System.nanoTime() + 5_000_000_000L;
            return false;
        }
    }
}
