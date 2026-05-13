<div align="center">

# NotchPilot

**把 MacBook 刘海变成可扩展的实时交互区域。**

**A macOS notch companion that turns the camera cutout into a live surface.**

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014%2B-lightgrey.svg)](#)
[![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)](#)

[English](README.md) · [简体中文](README.zh-CN.md)

</div>

---

## ✨ 功能特性

- 🪟 **刘海交互面板** —— 支持紧凑预览与展开显示，支持多面板左右切换以及边距/黑边样式自定义。
- 🔔 **通知中心** —— 直接在刘海下方接管并展示系统的通知消息。
- 🐙 **Claude Code & Devin** —— 在刘海里直接接管工具审批（同意/拒绝/记住规则），无需再切回终端。
- 🤖 **Codex Desktop 集成** —— 实时显示终端命令与会话状态，支持弹出审批请求。
- 🎵 **媒体与桌面歌词** —— 刘海内嵌播放控制；提供独立的悬浮歌词窗口，支持在线搜索与时间轴微调。
- 📊 **系统监控** —— 面板直观显示 CPU、内存、实时网络、磁盘、电池及温度。

## 🚀 快速开始

NotchPilot 是一个 Swift Package，同时带 Xcode app target。

```sh
swift build
swift test
```

本地开发时打开 `NotchPilot.xcodeproj`，运行 `NotchPilot` scheme 即可。

**环境要求：** macOS 14+、Swift 6.2、Xcode 16+。

## 📄 许可证

NotchPilot 使用 **GNU General Public License v3.0 only**（`GPL-3.0-only`）。
允许商业使用，但本项目及其衍生作品在再分发时必须遵守 GPL 的源代码披露与
Copyleft 要求。

完整许可证文本见 [LICENSE](LICENSE)。

## 📦 第三方声明

仓库内打包的第三方代码与依赖记录在 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
