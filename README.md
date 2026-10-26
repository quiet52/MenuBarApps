<p align="center">
  <img src="assets/app_icon.png" width="128" height="128" alt="MenuBarApps Icon">
</p>

<h1 align="center">MenuBarApps (菜单栏应用与磁盘管家)</h1>

<p align="center">
  <strong>一款专为解决 macOS 屏幕右上角图标拥挤、内存膨胀与无用缓存堆积打造的原生超轻量管家。</strong><br>
  <em>A lightweight native macOS menu bar, running app & disk cache cleaner.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2013%2B-blue?style=flat-square&logo=apple" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9%20%7C%206.0-orange?style=flat-square&logo=swift" alt="Swift">
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20(arm64)-success?style=flat-square" alt="Apple Silicon (arm64)">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="MIT License">
</p>

<p align="center">
  <a href="#-中文文档">中文文档</a> •
  <a href="#-english-documentation">English Documentation</a>
</p>

---

## 🇨🇳 中文文档

### 💡 为什么需要 MenuBarApps？

在 macOS 上，随着安装的菜单栏辅助工具增多（尤其在**刘海屏 MacBook** 上），屏幕右上角状态栏极易被撑满，导致后面的应用被遮挡或挤出屏幕，用户**既不知道哪些程序在后台常驻运行，也无法右键退出它们**。

此外，长期使用的 Mac 往往在后台堆积了大量无用缓存（Chrome 媒体缓存几 G、Homebrew 安装包几百兆、项目编译构建件几十 G），而传统磁盘工具只按大小排序，用户不敢轻易下手。

**MenuBarApps** 将 **「后台应用管理」** 与 **「智能白名单磁盘清理」** 合二为一，用极简的单图标与快捷键，同时搞定**物理内存监控、进程调度与磁盘瘦身**。

---

### ✨ 核心功能特性

#### 1. 📱 应用与常驻服务管理 (App & Service Management)
* ⚡ **极简常驻，数字角标**：在菜单栏仅占用单图标位，实时小字显示当前运行的菜单栏（辅助）应用数量（如 ` 5`）；面板关闭时不做任何轮询，几乎零开销。
* 🔁 **开机自动启动**：右键菜单栏图标或在面板「⋯」菜单中一键开启。
* ⌨️ **全局快捷键一键唤出**：默认 `⌥⇧A`，可改为 `⌃⌥A` / `⌃⌥M` / `⌃⌥Space`；即便菜单栏图标被刘海挤出视野，也会在屏幕右上角弹出悬浮面板。
* 🔍 **智能分类、搜索与排序**：清晰划分 **「菜单栏」**、**「窗口应用」** 与 **「终端/AI」**，支持按名称 / PID / 命令行搜索，可按内存从高到低排序。
* 🤖 **终端 / AI 常驻服务监控 (CLI & AI Agents)**：无需 `.app` 外壳，自动通过内核接口捕获终端运行的本地模型与智能体（**Ollama、Claude Code、Codex、Gemini CLI、Kimi Code、Pi Agent、Aider** 等）以及 Redis / PostgreSQL / MySQL 等常驻服务；同一服务的子进程自动合并为一行，支持一键终止（`ollama serve` 还支持一键重启）。
* 📊 **与活动监视器一致的内存统计**：采用 `phys_footprint` 口径，并把 Chrome、VS Code 等多进程应用的 Helper 进程一并计入，辅以三色预警（常规 / 橙色>500MB / 红色>1.5GB）。
* 🔄 **一键重启（释放内存）**：等待应用真正退出后再静默重新打开；若应用因「是否保存」等原因未退出，会自动取消并提示，不会只关不开。
* 🚀 **动态点击状态响应**：打开显示 `已唤起 ✓`，重启显示转圈菊花，退出立即置灰淡出。

#### 2. 🧹 磁盘缓存扫雷与清理 (Disk Cleaner)
* 🎯 **纯白名单扫描**：只扫描可由软件自动重建的缓存，不触碰个人文件与系统目录：
  * **🌐 浏览器多媒体缓存**：Chrome / Safari / Edge 离线图片与视频流缓存（常占 2GB~5GB）；
  * **🍺 包管理器安装包残留**：Homebrew 下载的 `.tar.gz` 离线包、Python pip 缓存、npm 缓存；
  * **🔨 开发者编译构建中间件**：Xcode `DerivedData`、Swift 项目 `.build`、Python `__pycache__`（开发目录下最多 5 层）；
* ⚖️ **默认只勾选无代价的项目**：DerivedData、项目 `.build`、Playwright 内核等清理后需要重新编译 / 下载的项会标出「清理代价」，默认不勾选；
* ✋ **两步确认**：清理前显示将删除的项数与总大小，确认后才会执行；
* 🛡️ **安全网关**：每一个待删除路径都要通过 `CleanerSafetyValidator` 校验，缓存根目录只清空内容、保留目录本身；
* 🔍 **透明下钻与访达联动 (Detail Drill-down & Finder)**：点击任意项目右侧 `›` 即可无缝进入明细面板，查看绝对路径、清理影响说明以及体积最大的具体子文件/子目录；支持一键在访达中定位并打开，亦可在此单独清理该项。

---

### 📥 下载与安装

1. 从 [Releases 页面](../../releases) 下载最新的 `MenuBarApps-v1.4.0.zip`；
2. 解压后将 `MenuBarApps.app` 拖移至系统 **“访达 -> 应用程序 (Applications)”**；
3. **首次打开**：按住 `Control` 键点击应用图标，选择 **“打开”**，然后点击 **“仍要打开”** 即可。

---

### 🛠️ 源码构建

```bash
# 1. 克隆仓库
git clone https://github.com/quiet52/MenuBarApps.git
cd MenuBarApps

# 2. 一键编译并打包
./build.sh
```

---

## 🇺🇸 English Documentation

### 💡 Why MenuBarApps?

On macOS (especially on MacBooks with camera notches), the menu bar easily runs out of space, hiding background apps off-screen. Meanwhile, developers run memory-hungry local AI agents and daemons without visibility, and suffer from silent disk hogs (multi-gigabyte browser caches, stale package installers, Xcode DerivedData, `.build` folders).

**MenuBarApps** integrates **Active App & CLI Agent Management** with a **Safe Whitelist Disk Cleaner** in a single, lightweight menu bar popover.

---

### ✨ Key Features

#### 1. 📱 App & Service Management
* ⚡ **Live Status Item**: Minimalist icon showing the number of running menu bar (accessory) apps. No polling while the panel is closed.
* 🔁 **Launch at Login**: Toggle from the status item's right-click menu or the panel's `⋯` menu.
* ⌨️ **Global Shortcut**: `⌥⇧A` by default, switchable to `⌃⌥A` / `⌃⌥M` / `⌃⌥Space`.
* 🔍 **Smart Grouping**: Separates menu bar accessory apps, standard GUI window apps, and **Terminal/AI Services**.
* 🤖 **Terminal & AI Agent Services**: Detects CLI models, TUI assistants (**Ollama, Claude Code, Codex, Gemini CLI, Kimi Code, Pi Agent, Aider**, etc.) and dev daemons; child processes are grouped into one row. One-click termination (restart for `ollama serve`).
* 📊 **Activity Monitor–consistent Memory**: `phys_footprint`, including helper processes of multi-process apps; sortable by memory.
* 🔄 **Reliable Restart**: Waits until the app has actually exited before relaunching; cancels with a notice if the app refuses to quit.
* 🚀 **Clear Action Feedback**: Visual indicators for opening, restarting spinner, and dimming on quit.

#### 2. 🧹 Safe Disk Cleaner
* 🎯 **Strict Whitelist Scanning**: Only detects caches that apps regenerate automatically:
  * Browser media/image caches (Google Chrome, Safari, Edge, Firefox)
  * Package managers offline archives (Homebrew `.tar.gz`, pip, npm, Yarn, CocoaPods)
  * Developer build directories (Xcode `DerivedData`, Swift `.build`, `__pycache__`)
* ⚖️ **Cost-aware Defaults & Confirmation**: Items that cost a rebuild or re-download (DerivedData, `.build`, Playwright) are labelled and unselected by default; every clean requires a second confirmation.
* 🛡️ **Safety Gate**: Every path is checked by `CleanerSafetyValidator`; cache roots are emptied, never removed.
* 🔍 **Transparent Drill-down & Finder Integration**: Click `›` on any item to view its absolute path, what cleaning it means, and the largest files/subfolders; open directly in Finder or clean individually.

---

### 📥 Download & Installation

1. Download `MenuBarApps-v1.4.0.zip` from [Releases](../../releases);
2. Unzip and drag `MenuBarApps.app` to your `/Applications` folder;
3. **First launch**: Right-click (or Control-click) `MenuBarApps.app`, select **Open**, and click **Open Anyway**.

---

### 🛠️ Build from Source

```bash
# Clone the repository
git clone https://github.com/quiet52/MenuBarApps.git
cd MenuBarApps

# Build and package
./build.sh
```

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).

