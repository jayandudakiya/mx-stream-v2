OrcaBox
Copyright (C) 2026 The OrcaBox Authors

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License version 3.0 (GPL-3.0) as published
by the Free Software Foundation, together with the additional terms under GPLv3
Section 7 recorded in the LICENSE file. See LICENSE for the full text.

────────────────────────────────────────────────────────────────────────────
Origin and upstream attribution
────────────────────────────────────────────────────────────────────────────

OrcaBox is an independent, UNOFFICIAL fork. It is not the Zangetsu project, and
it is not endorsed, certified or supported by Zangetsu's author.

OrcaBox is derived from:

Zangetsu
  https://github.com/Spyou/Zangetsu
  Copyright (C) 2026 Krishna Vishwakarma (https://github.com/Spyou)
  License: GPL-3.0, with additional terms under GPLv3 Section 7

This credit is retained because the LICENSE requires it. Under those additional
terms, any conveyed copy or modified version must keep a clearly visible
statement crediting the original Zangetsu project and its author, including a
link to the original source repository (Term C), and must be marked in a
reasonably prominent way as a modified, unofficial or forked version distinct
from the original (Term B). The same terms grant no right to use the Zangetsu
name, logo, icon or branding for this fork (Term A) — hence the rename to
OrcaBox, which carries its own name, icon and identity throughout.

────────────────────────────────────────────────────────────────────────────
Third-party components
────────────────────────────────────────────────────────────────────────────

CloudStream (recloudstream)
  https://github.com/recloudstream/cloudstream
  License: GPL-3.0
  OrcaBox bundles the CloudStream `library` artifact and includes app-internal
  compatibility classes under the `com.lagradost.cloudstream3` namespace so that
  CloudStream `.cs3` extensions load and run against it. Because CloudStream is
  licensed under GPL-3.0 (copyleft), OrcaBox as a combined work is likewise
  licensed under GPL-3.0.

Aniyomi / Tachiyomi
  https://github.com/aniyomiorg/aniyomi
  https://github.com/tachiyomiorg/tachiyomi
  License: Apache-2.0
  Portions of the Android extension-loading code (files under
  android/app/src/main/kotlin/com/orcabox/app/aniyomi/) are derived from
  Aniyomi/Tachiyomi and retain their original Apache-2.0 headers. The full
  Apache License 2.0 text is included as LICENSE-Apache-2.0.txt.

Other dependencies (Flutter/Dart packages and Android libraries) are used under
their respective open-source licenses; refer to each package for details.

────────────────────────────────────────────────────────────────────────────
Keeping this file current
────────────────────────────────────────────────────────────────────────────

Any pull request that adds a new third-party dependency, incorporates code
derived from another project, or bundles another project's assets must update
this file in the same PR — see CONTRIBUTING.md. This file is treated as the
authoritative record of what's bundled and under what terms; if it's out of
date, that's considered a bug, not a formality.

────────────────────────────────────────────────────────────────────────────
Reporting a concern
────────────────────────────────────────────────────────────────────────────

If you believe this project incorporates third-party code, assets, or content
without proper attribution or in violation of its license, please open an issue
on the OrcaBox repository so it can be corrected or removed.
