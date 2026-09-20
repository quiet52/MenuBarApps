<p align="center">
  <img src="assets/app_icon.png" width="128" height="128" alt="MenuBarApps Icon">
</p>

<h1 align="center">MenuBarApps (菜单栏应用管家)</h1>

<p align="center">
  <strong>一款专为解决 macOS 屏幕右上角图标拥挤、刘海屏遮挡问题打造的原生超轻量应用管理工具。</strong><br>
  <em>A lightweight native macOS menu bar & running application manager.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2013%2B-blue?style=flat-square&logo=apple" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9%20%7C%206.0-orange?style=flat-square&logo=swift" alt="Swift">
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20(Universal)-success?style=flat-square" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="MIT License">
</p>

<p align="center">
  <a href="#-中文文档">中文文档</a> •
  <a href="#-english-documentation">English Documentation</a>
</p>

---

## 🇨🇳 中文文档

### 💡 为什么需要 MenuBarApps？

在 macOS 上，随着安装的菜单栏辅助工具（如剪贴板、网盘同步、系统监控、各类代理等）增多，尤其是在配备**“刘海屏”**的 MacBook 上，屏幕右上角的状态栏空间极易被撑满。这会导致排在后面的应用被硬生生遮挡或挤出屏幕，用户**既不知道哪些程序在后台常驻运行，也无法右键退出它们**。

此外，很多常驻小工具（如 Maccy、Stats 等）运行一段时间后常会出现内存膨胀（吃掉几百兆物理内存），而传统方式只能手动退出再重新找出来打开。

**MenuBarApps** 就是为了彻底解决这一痛点而生的纯粹工具。

---

### ✨ 核心功能特性

* ⚡ **极简常驻，数字角标**：在菜单栏仅占用单图标位，实时小字显示当前运行的后台辅助应用总数（如 ` 5`）。
* ⌨️ **全局快捷键一键唤出**：默认支持 `Option + Shift + A` (`⌥⇧A`)，即便菜单栏图标被挤出视野，也可随时在屏幕居中呼出浮窗。
* 🔍 **智能分类与快速搜索**：
  * 自动区分 **「菜单栏应用」**（无 Dock 图标的后台工具）与 **「窗口应用」**（微信、Chrome、终端等常规应用）。
  * 顶部内置即时搜索框，敲几个字母瞬间定位。
* 📊 **实时物理内存 (RSS) 监控**：
  * 基于 macOS 底层 `libproc` 接口，零 CPU 开销秒级显示每个进程真实的物理内存占用。
  * 智能颜色预警（绿色常规 / 橙色超 200MB / 红色超 500MB），一眼揪出“内存刺客”。
* 🔄 **一键重启（瞬间释放内存）**：
  * 在行内或右键菜单中提供 **`[🔄 重启]`** 动作。
  * 自动终止原进程并在后台静默重新拉起，瞬间清空缓存碎片，把几百兆内存彻底还给系统。
* 🚀 **动态交互状态响应**：
  * 点击“打开”：瞬间显示 `已唤起 ✓`。
  * 点击“重启”：即刻出现旋转 Loading 动画。
  * 点击“退出”：整行应用立即半透明淡出，告别“不知道点没点上”的困惑。
* 🕒 **最近退出历史与恢复**：记录通过本工具退出的应用，随时点击“启动”一键复原。

---

### 📥 下载与安装

1. 从 [Releases 页面](../../releases) 下载最新的 `MenuBarApps-v1.1.zip`；
2. 解压后将 `MenuBarApps.app` 拖移至系统 **“访达 -> 应用程序 (Applications)”**；
3. **首次打开**：按住 `Control` 键点击应用图标，在弹出的右键菜单中选择 **“打开”**，然后点击 **“仍要打开”** 即可。

> **💡 开机自启建议**：在 macOS **“系统设置 -> 通用 -> 登录项”** 中，将 `MenuBarApps` 添加为开机自启，享受开机即用的纯净体验。

---

### 🛠️ 源码构建

本项目采用纯原生 Swift / SwiftUI 编写，零第三方依赖：

```bash
# 1. 克隆仓库
git clone https://github.com/quiet52/MenuBarApps.git
cd MenuBarApps

# 2. 一键编译并打包
./build.sh
```
打包成功后，可在项目目录下生成 `MenuBarApps.app` 及分发用的 `.zip` 压缩包。

---

## 🇺🇸 English Documentation

### 💡 Why MenuBarApps?

On macOS—especially on newer MacBooks with a **camera notch**—the top-right menu bar easily runs out of horizontal space as you install more background utilities (clipboard managers, cloud drives, system monitors, etc.). Once space is exhausted, icons are pushed off-screen or hidden behind the notch, leaving you with **no easy way to see what's running or quit them**.

Additionally, many background helper utilities experience memory bloat over extended periods (e.g., hoarding hundreds of megabytes of cached images).

**MenuBarApps** is a clean, ultra-lightweight, native macOS utility designed to regain control over all your background and regular apps with zero hassle.

---

### ✨ Key Features

* ⚡ **Minimalist Tray Indicator**: Occupies just a single slot on your menu bar with a live numeric count (e.g., ` 5`).
* ⌨️ **Global Shortcut Activation**: Press `Option + Shift + A` (`⌥⇧A`) anytime, anywhere to summon the manager panel, even if your menu bar icon is hidden.
* 🔍 **Smart Classification & Instant Filter**:
  * Cleanly separates **Menu Bar Utilities** (accessory apps without dock icons) and **Window Apps** (Chrome, WeChat, Terminal, etc.).
  * Instant search bar to filter by app name or process PID.
* 📊 **Real-time Memory (RSS) Footprint**:
  * Powered by the native `libproc` Mach kernel APIs with near-zero CPU and battery usage.
  * Color-coded memory alerts (Normal / Orange > 200MB / Red > 500MB) to identify memory-heavy apps at a glance.
* 🔄 **One-Click Restart (Instant Memory Flush)**:
  * Click the `[🔄]` button to terminate the app and silently relaunch it in the background, instantly freeing up memory leaks without manual steps.
* 🚀 **Clear Action Feedback**:
  * "Open": immediately confirms with `Activated ✓`.
  * "Restart": triggers a smooth rotating spinner.
  * "Quit": instantaneously dims the row to 45% opacity with clear status changes.
* 🕒 **Recently Quit History**: Keep track of apps you've closed and relaunch them with one click.

---

### 📥 Download & Installation

1. Download the latest `MenuBarApps-v1.1.zip` from [Releases](../../releases);
2. Unzip and drag `MenuBarApps.app` into your `/Applications` folder;
3. **First-time launch**: Right-click (or Control-click) `MenuBarApps.app` in Finder, select **Open**, and click **Open Anyway**.

---

### 🛠️ Build from Source

Built entirely with native Swift and SwiftUI without any external dependencies:

```bash
# Clone the repository
git clone https://github.com/quiet52/MenuBarApps.git
cd MenuBarApps

# Compile and package into .app
./build.sh
```

---

## 📄 License

This project is licensed under the [MIT License](LICENSE) - see the LICENSE file for details.
