# Java bridge license notices

Copyright (c) 2026 Grymlock.

This inventory records existing file-specific terms. It does not relicense earlier
releases, withdraw permissions already granted, or override third-party terms.

## KnoxBox original-content license

The following source files carry `LicenseRef-KnoxBox-Original-Content`, identifying
the existing [KnoxBox license](../KnoxBox-License.md):

- `KBMMovieScreenBridge.java`
- `KBMPremiumTVBridge.java`
- `KBMViewModeBridge.java`
- `KBMTVCaptionBridge.java`
- `KBMCameraRecorder.java`
- `KBMRecordingAudioCapture.java`

These notices also identify the corresponding compiled classes and nested classes
in `com.knoxboxprobe`. The custom license permits personal use, backups and private
modifications; redistribution and reuse in distributed projects require permission,
subject to applicable law and any controlling third-party obligations.

## Explicit GPL notices

The following files retain their existing `GPL-3.0-only` headers:

- `KBMProjectorFrameTap.java`
- `KBMCinemaProjectorBridge.java`

Their corresponding compiled classes and nested classes retain those terms.
The KnoxBox redistribution restrictions do not override the GPL. See
[GPL-3.0.txt](GPL-3.0.txt).

## Bundled components

JCodec remains subject to [its BSD license](JCodec-BSD-2-Clause.txt).
The embedded Windows audio helper and WIL retain the notices in `LICENSES/Audio`
and the corresponding `KBMAudioCapture-*` resources inside the jar. Those components
are not covered by the KnoxBox original-content restrictions.

The jar embeds copies of this inventory, the KnoxBox license, GPL text and JCodec
license under `META-INF/licenses/`. Existing third-party resources are preserved.
