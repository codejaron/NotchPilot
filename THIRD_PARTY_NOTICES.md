# Third-Party Notices

This file documents third-party code bundled in this repository and
third-party package dependencies required to build or run NotchPilot.

## LyricsKit

- Project: `MxIris-LyricsX-Project/LyricsKit`
- Upstream: <https://github.com/MxIris-LyricsX-Project/LyricsKit>
- Used revision: `9e52e0986b89df6d8815c823fac23b6a775c3b49`
- License: `MPL-2.0`

NotchPilot consumes LyricsKit as a Swift Package dependency; no LyricsKit
source files are vendored in this repository. The dependency supplies lyrics
search and parsing types used by the desktop lyrics feature.

LyricsKit is licensed under MPL 2.0. The MPL text is available from the
upstream `LICENSE` file and <https://mozilla.org/MPL/2.0/>. Source for the
exact dependency revision can be obtained from the upstream repository using
the revision above.

## Stats

- Project: `exelban/stats`
- Upstream: <https://github.com/exelban/stats>
- License: `MIT`

Portions of the system monitor plugin are adapted from Stats:

- `SystemMonitorSMCSensorBridge.decodedValue(dataType:bytes:)` — SMC data
  type decoding table (`ui8`/`ui16`/`ui32`/`sp1e`/`sp3c`/`sp4b`/`sp5a`/`sp69`/
  `sp78`/`sp87`/`sp96`/`spa5`/`spb4`/`spf0`/`flt `/`fpe2`) and the associated
  fixed-point divisors.
- `SystemMonitorBestEffortSampler` — the `/bin/ps -Aceo pid,pcpu,comm -r`
  and `/usr/bin/top -l 1 -o mem -stats pid,command,mem` invocations used to
  enumerate top CPU and memory processes, and their output parsing.

### MIT License

```text
MIT License

Copyright (c) 2019 Serhiy Mytrovtsiy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Kenney Interface Sounds

- Project: `Kenney's Interface Sounds`
- Upstream: <https://kenney.nl/assets/interface-sounds>
- License: `CC0-1.0` (Creative Commons Zero — public domain dedication)

NotchPilot bundles a small subset of Kenney's Interface Sounds under
`Sources/NotchPilotKit/Resources/Sounds/builtin/sounds/` to provide an
out-of-the-box audio feedback experience. The full pack and license terms
are available from the upstream URL above.

CC0 does not require attribution, but Kenney explicitly invites credit, and
NotchPilot is grateful for the work.

### Creative Commons CC0 1.0 Universal Summary

```text
The person who associated a work with this deed has dedicated the work to the
public domain by waiving all of their rights to the work worldwide under
copyright law, including all related and neighboring rights, to the extent
allowed by law.

You can copy, modify, distribute and perform the work, even for commercial
purposes, all without asking permission.

Full text: https://creativecommons.org/publicdomain/zero/1.0/legalcode
```

## OpenPeon CESP Standard

- Project: `PeonPing/openpeon`
- Upstream: <https://github.com/PeonPing/openpeon>
- Specification: <https://openpeon.com/spec>
- License: `MIT`

NotchPilot implements the OpenPeon CESP v1.0 sound pack specification so users
can install third-party packs from the OpenPeon registry without modification.
No OpenPeon source code is vendored; only the `openpeon.json` manifest format
is consumed.

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

The bundled framework was built locally from the upstream source tree above
and is included for runtime use by the media playback plugin.

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
