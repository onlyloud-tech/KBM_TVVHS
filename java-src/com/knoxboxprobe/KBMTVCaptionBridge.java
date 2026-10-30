// Copyright (c) 2026 Grymlock. All rights reserved.
// SPDX-License-Identifier: LicenseRef-KnoxBox-Original-Content
// See LICENSES/KnoxBox-License.md and LICENSES/Java/KnoxBox-Bridges.md.
package com.knoxboxprobe;

import me.zed_0xff.zombie_buddy.Exposer;
import zombie.chat.ChatElement;
import zombie.iso.objects.IsoWaveSignal;

/** Clears only the floating text on a specific television. */
@Exposer.LuaClass(name = "KBMTVCaptionBridge")
public final class KBMTVCaptionBridge {
    private KBMTVCaptionBridge() {
    }

    public static boolean clear(IsoWaveSignal television) {
        if (television == null) return false;
        ChatElement chat = television.getChatElement();
        if (chat == null) return false;
        for (int player = 0; player < 4; player++) chat.clear(player);
        return true;
    }
}
