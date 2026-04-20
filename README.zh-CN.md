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

- 🪟 **可展开刘海面板**，附带紧凑的 sneak 预览
- 🐙 **Claude Code 集成** —— 基于 hook 接管工具调用审批，在刘海里直接同意 / 拒绝 / 记住规则，不用切回终端
- 🤖 **Codex Desktop 集成** —— 实时监听会话、在刘海弹出审批请求，支持会话内规则记忆，让 vibe coding 顺畅不断档
- 🎵 **媒体控制** —— 刘海内直接预览正在播放与基础播放控制
- 🎤 **桌面歌词** —— 悬浮歌词窗口，支持在线搜索、时间轴偏移微调、按曲目忽略
- 📊 **系统监控** —— CPU / 内存 / 网络 / 磁盘 / 电池 / 温度
- 🖥️ **多屏支持**，带菜单栏控制器

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
