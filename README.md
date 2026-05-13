<div align="center">

# NotchPilot

**A macOS notch companion that turns the camera cutout into a live surface.**

**把 MacBook 刘海变成可扩展的实时交互区域。**

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014%2B-lightgrey.svg)](#)
[![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)](#)

[English](README.md) · [简体中文](README.zh-CN.md)

</div>

---

## ✨ Features

- 🪟 **Expandable notch panel** — compact previews, left/right view switching, and notch padding customization.
- 🔔 **Notification center** — system and app notifications displayed directly under the notch.
- 🐙 **Claude Code & Devin** — handle CLI tool approvals (approve/deny/remember rules) from the notch without switching back to the terminal.
- 🤖 **Codex Desktop integration** — live session monitoring, current terminal command display, and in-notch approval prompts.
- 🎵 **Media & Desktop lyrics** — notch playback controls and a floating lyrics window with online search and time offsets.
- 📊 **System monitoring** — CPU, memory, network traffic, disk, battery, and temperature.

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
