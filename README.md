<div align="center">

# 🎛️ NotchPilot

**A macOS notch companion that turns the camera cutout into a live surface.**

**把 MacBook 刘海变成可扩展的实时交互区域。**

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014%2B-lightgrey.svg)](#)
[![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)](#)

[English](README.md) · [简体中文](README.zh-CN.md)

</div>

---

## ✨ Features

- 🪟 **Expandable notch panel** with compact sneak previews
- 🐙 **Claude Code** — hook-based tool-use approvals surfaced in the notch; approve / deny / remember without leaving your editor
- 🤖 **Codex Desktop** — live session monitoring, in-notch approval prompts, and session-scoped rules to keep vibe coding flowing
- 🎵 **Media control** — now-playing previews and playback controls in the notch
- 🎤 **Desktop lyrics** — floating lyrics window with online search, time-offset adjustment, and per-track ignore list
- 📊 **System monitoring** — CPU, memory, network, disk, battery, temperature
- 🖥️ **Multi-screen** support with a menu bar controller

## 🚀 Getting Started

NotchPilot is a Swift Package with an Xcode app target.

```sh
swift build
swift test
```

For local app development, open `NotchPilot.xcodeproj` and run the `NotchPilot`
scheme.

**Requirements:** macOS 14+, Swift 6.2, Xcode 16+.

## 📄 License

NotchPilot is licensed under the **GNU General Public License v3.0 only**
(`GPL-3.0-only`). Commercial use is allowed under the GPL, but redistribution
of this project or derivative works must comply with the GPL's source code and
copyleft requirements.

See [LICENSE](LICENSE) for the full license text.

## 📦 Third-Party Notices

Bundled third-party code and package dependencies are documented in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
