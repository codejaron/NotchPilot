# Third-Party Notices

## LyricsKit

- Project: `MxIris-LyricsX-Project/LyricsKit`
- Upstream: <https://github.com/MxIris-LyricsX-Project/LyricsKit>
- Used revision: `9e52e0986b89df6d8815c823fac23b6a775c3b49`
- Related project: `MxIris-LyricsX-Project/LyricsX`
- Related upstream: <https://github.com/MxIris-LyricsX-Project/LyricsX>
- License: `MPL-2.0`

NotchPilot consumes LyricsKit as a Swift Package dependency. The NotchPilot
sources in this repository do not include copied LyricsX source files; the
dependency supplies lyrics search and parsing types used by the desktop lyrics
feature.

LyricsKit states that it is part of LyricsX and licensed under MPL 2.0. The
MPL text is available from the upstream `LICENSE` file and
<https://mozilla.org/MPL/2.0/>. Source for the exact dependency revision can be
obtained from the upstream repository using the revision above.

## MediaRemoteAdapter

- Project: `ungive/mediaremote-adapter`
- Upstream: <https://github.com/ungive/mediaremote-adapter>
- Vendored from upstream commit: `7b7993b0499967daebfce351a5ecc9ec833c70d1`
- License: `BSD-3-Clause`

NotchPilot bundles the following upstream-derived files under
`Sources/NotchPilotKit/Resources/MediaRemoteAdapter/`:

- `mediaremote-adapter.pl`
- `MediaRemoteAdapter.framework`
- `LICENSE`

The bundled framework in this repository was built locally from the upstream
source tree above. It is included for runtime use by the media playback plugin
and is not sourced from `TheBoredTeam/boring.notch`.

### BSD 3-Clause License

```text
BSD 3-Clause License

Copyright (c) 2025, Jonas van den Berg and contributors

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```
