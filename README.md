# NotchPilot

NotchPilot is a macOS notch companion app. It turns the MacBook notch area into
an expandable surface for live activity, AI agent sessions, media playback,
desktop lyrics, and system monitoring.

## Features

- Expandable notch panel with compact sneak previews.
- Plugin-based surfaces for system status, Claude, Codex, and media playback.
- Claude hook integration and Codex Desktop session monitoring.
- Media playback controls, now-playing previews, and desktop lyrics.
- CPU, memory, network, disk, battery, and temperature summaries.
- Multi-screen presentation support and a menu bar controller.

## Build

NotchPilot is a Swift Package with an Xcode app target.

```sh
swift build
swift test
```

For local app development, open `NotchPilot.xcodeproj` and run the
`NotchPilot` scheme.

## License

NotchPilot is licensed under the GNU General Public License v3.0 only
(`GPL-3.0-only`). Commercial use is allowed under the GPL, but redistribution
of this project or derivative works must comply with the GPL's source code and
copyleft requirements.

See [`LICENSE`](LICENSE) for the full license text.

## Third-Party Notices

Bundled third-party code and package dependencies are documented in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
