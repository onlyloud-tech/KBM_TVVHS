// Copyright (c) 2026 Grymlock.
// SPDX-License-Identifier: GPL-3.0-only
package com.knoxboxprobe;

import java.util.Collections;
import java.util.Map;
import java.util.WeakHashMap;
import me.zed_0xff.zombie_buddy.Exposer;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.iso.objects.IsoWaveSignal;

/** Native batteries/media, without native radio chatter or TV sound loops. */
@Exposer.LuaClass(name = "KBMCinemaProjectorBridge")
public final class KBMCinemaProjectorBridge {
    private static final Map<Object, Boolean> devices = Collections.synchronizedMap(new WeakHashMap<>());
    private KBMCinemaProjectorBridge() {}

    public static boolean quiet(IsoWaveSignal radio) {
        if (radio == null || radio.getDeviceData() == null) return false;
        if (devices.put(radio.getDeviceData(), Boolean.TRUE) == null) {
            radio.getDeviceData().cleanSoundsAndEmitter();
        }
        if (radio.getChatElement() != null) {
            for (int player = 0; player < 4; player++) radio.getChatElement().clear(player);
        }
        return true;
    }

    public static boolean isQuiet(Object device) {
        return devices.containsKey(device);
    }

    @Patch(className="zombie.radio.devices.DeviceData", methodName="updateEmitter")
    public static class QuietEmitter {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.This Object device) {
            return KBMCinemaProjectorBridge.isQuiet(device);
        }
    }

    @Patch(className="zombie.radio.devices.DeviceData", methodName="playSound")
    public static class QuietSound {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.This Object device) {
            return KBMCinemaProjectorBridge.isQuiet(device);
        }
    }
}
