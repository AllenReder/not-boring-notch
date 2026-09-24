<h1 align="center">
  <br>
  <a href="https://github.com/AllenReder/not-boring-notch"><img src="assets/app-icon.png" alt="Not Boring Notch" width="140"></a>
  <br>
  Not Boring Notch
  <br>
</h1>

<p align="center">
  <em>为 macOS 深度重构、性能强劲的刘海伴侣。</em><br>
  <strong>基于 <a href="https://github.com/TheBoredTeam/boring.notch">TheBoredTeam/boring.notch</a> 分叉 · 由 Allen Yi 维护</strong>
</p>

<p align="center">
  <a href="README.md">English</a> | <a href="README_zh.md">简体中文</a>
</p>

<p align="center">
  <a href="https://github.com/AllenReder/not-boring-notch/actions/workflows/cicd.yml"><img src="https://github.com/AllenReder/not-boring-notch/actions/workflows/cicd.yml/badge.svg" alt="构建状态" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPL--3.0-blue.svg" alt="协议" /></a>
  <img src="https://img.shields.io/badge/macOS-14.0%2B-black?logo=apple" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Swift-5.0-orange?logo=swift" alt="Swift 5" />
</p>

---

欢迎使用 **Not Boring Notch**，让你的 MacBook 刘海不再单调，成为屏幕上的视觉焦点与效率利器！

告别沉闷静态的黑色小方块：在 Not Boring Notch 的加持下，刘海化身为你专属的灵动控制中心——拥有原生 **macOS 26 流体玻璃（Liquid Glass）光学折射**渲染、动感频谱可视化、实时歌词、日历深度集成、支持 AirDrop 的文件暂存置物架、灵动岛风格系统 HUD，以及全新的自定义提醒通道。

<p align="center">
  <img src="assets/demo.gif" alt="演示动图" width="85%" />
</p>

---

## ✨ 核心特性

- 💎 **流体玻璃质感 (Liquid Glass Surface)**：基于原生 CoreAnimation GPU 光线折射着色器开发，拥有亚像素级色散效果与零模糊的高保真清澈透亮感。
- 🔔 **自定义提醒通道 (Custom Reminder Channel)**：允许命令行脚本、自动化钩子和各类 AI Agent 通过本地极速 HTTP 端口（`127.0.0.1:45999`）向刘海发送通知。支持灵动岛平滑拉伸展开、超长文本跑马灯循环滚动、相同 `id` 原地刷新任务状态（拒绝刷屏），展开即可查看富文本正文与操作按钮。详见 [docs/reminder-channel.md](docs/reminder-channel.md)。
- 🎵 **强大的媒体中心 (Media Powerhouse)**：深度集成 Apple Music、Spotify 与 YouTube Music。支持逐字实时歌词、高帧率动态音频频谱仪，以及取自封面配色的氛围光晕。
- 📆 **日历与系统提醒 (Calendar & Reminders)**：完整的月历视图、即将开始的日程，以及可直接在刘海内勾选完成的系统待办事项。
- 📚 **文件置物架 (File Shelf)**：拖拽文件至刘海即可临时置顶暂存，支持空格快速预览（Quick Look），可随时拖出至任意位置或通过 AirDrop 快速分享。
- 🎚️ **灵动系统 HUD (System HUDs)**：用精致的灵动岛动画全面替代音量、亮度、键盘背光与电池充放电提示。
- 🪞 **刘海镜子与萌趣表情 (Notch Mirror & Face)**：一键唤起前置摄像头快速整理仪容，闭合状态下还有生动有趣的灵巧表情动画。

---

### 🔔 快速上手：向刘海发送自定义通知

只要 Not Boring Notch 正在运行，任何终端命令或脚本只需一行 `curl` 即可推送通知：

```bash
# 读取沙盒自动生成的本地安全令牌
TOKEN=$(cat "$HOME/Library/Containers/com.allenreder.notboringnotch/Data/Library/Application Support/NotBoringNotch/reminder-channel.json" | grep -o '"token" *: *"[^"]*"' | cut -d'"' -f4)

# 发送一条构建完成通知
curl -X POST http://127.0.0.1:45999/reminder \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"icon":{"kind":"sf_symbol","value":"hammer.fill"},"title":"构建完成","subtitle":"12s"}'
```

更详细的结构化参数说明（图标定制、动作按钮、粘性通知、队列模型），请参阅 [自定义提醒通道接入指南](docs/reminder-channel.md)。

---

## 🚀 安装指南

**系统要求：**
- macOS **14 Sonoma** 或更高版本（硬件级流体玻璃折射效果需要 macOS 26+）
- 支持 Apple Silicon (M系列芯片) 及 Intel Mac

### 从 GitHub Releases 下载预编译版本

1. 前往 [**Releases 页面**](https://github.com/AllenReder/not-boring-notch/releases/latest) 下载最新的 `.dmg` 安装包；
2. 打开 `.dmg` 磁盘映像，将 **Not Boring Notch** 拖入你的 `/Applications`（应用程序）文件夹；
3. **首次启动 Gatekeeper 提示处理：**  
   作为开源社区构建版本，首次启动若系统提示“无法打开，因为无法验证开发者”，请在终端（Terminal）中运行一次以下命令解除隔离：
   ```bash
   xattr -dr com.apple.quarantine "/Applications/Not Boring Notch.app"
   ```
4. 打开应用，尽情体验！

---

## 🛠️ 从源码编译

### 环境准备

- macOS 15.0 或更高版本
- Xcode 16.0 或更高版本

### 编译步骤

1. 克隆本仓库：
   ```bash
   git clone https://github.com/AllenReder/not-boring-notch.git
   cd not-boring-notch
   ```

2. 用 Xcode 打开工程：
   ```bash
   open NotBoringNotch.xcodeproj
   ```

3. 按快捷键 `Cmd + R` 即可编译并在本地运行。

---

## 💖 致谢与开源传承

本项目基于 [GNU 通用公共许可证 v3.0 (GPL-3.0)](LICENSE) 开源。我们衷心感谢上游项目及社区奠定的坚实基础：

- **[TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch)** – 最初由 Harsh Vardhan Goswami 及贡献者创建的开源灵感之作。
- **[MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter)** – 高性能 macOS Now Playing 媒体播放监听源。
- **[NotchDrop](https://github.com/Lakr233/NotchDrop)** – 启迪了刘海拖拽置物架的交互灵感。
- **[SkyLightWindow](https://github.com/Lakr233/SkyLightWindow)** – macOS SkyLight 底层窗口管理实现。
