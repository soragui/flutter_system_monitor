# 01 · 项目概述 — 为什么用 Flutter 写一个系统监控工具？

> **回答什么问题**：这个项目是什么？它解决了什么需求？为什么选择 Flutter 这个技术栈？
> **对应代码**：`README.md`, `pubspec.yaml`, `lib/main.dart`

---

## 1. 项目定义

SysMonitor 是一个 **Linux 桌面系统监控工具**，以轻量级常驻窗口的形式运行。

它展示四类系统指标：

| 指标 | 数据来源 | 刷新频率 |
|------|---------|---------|
| CPU 使用率 & 型号 | `/proc/stat`, `/proc/cpuinfo` | 每 3 秒 |
| 内存 (已用/总量/可用) | `/proc/meminfo` | 每 3 秒 |
| 磁盘挂载点使用率 | `df -h` 命令 | 每 3 秒 |
| 网络接口流量 | `/proc/net/dev` | 每 3 秒 |

> **关键约束**：这个项目只依赖 Dart 标准库和 3 个 Flutter 插件，不引入任何 C/C++ 原生扩展或第三方系统监控库。所有数据采集都通过对 `/proc` 文件系统的纯 Dart I/O 完成。

---

## 2. 用户场景

这个工具面向 Linux 桌面用户（开发者、运维人员），使用场景是：

1. **开机自启** → 程序启动，最小化到系统托盘
2. **日常使用中** → 鼠标悬停托盘图标，看到 "CPU45% MEM62%"
3. **想查看详情** → 点击托盘图标 / 右键菜单 "Dashboard" → 弹出完整监控面板
4. **关闭窗口** → 不是退出，而是最小化回托盘
5. **真正退出** → 右键托盘菜单 → "Exit"

这是一个典型的 **常驻后台 + 按需打开** 的桌面应用模式。

---

## 3. 为什么选择 Flutter？

在 Linux 桌面生态中，GTK (C) 和 Qt (C++) 是传统选择。本项目选择 Flutter (Dart)，基于以下理由：

### 3.1 跨平台潜力

```dart
// 同一份代码，不同平台
// flutter run -d linux     → Linux 原生窗口
// flutter run -d windows   → Windows 原生窗口 (未来)
// flutter run -d macos     → macOS 原生窗口 (未来)
```

虽然当前只编译 Linux，但 UI 层（screens/widgets/providers）与平台无关。如果要扩展到 Windows/macOS，只需要替换 `services/system_monitor.dart` 中的平台数据采集逻辑，其余代码不用动。

> Flutter 桌面应用的一个优势：UI 逻辑跨平台复用，平台特定逻辑隔离在 service 层。

### 3.2 声明式 UI 天然适合监控面板

监控面板是一个典型的数据驱动 UI：

```
数据变化 → 状态更新 → UI 自动重建
```

Flutter 的声明式模型（`Widget = f(state)`）完美匹配这个范式。当 `DashboardProvider` 发出 `notifyListeners()` 时，所有 `Consumer` 包裹的 Widget 自动重建，不需要手动操作 DOM 或调用 `setText()`。

### 3.3 开发体验

- **热重载**：修改 UI → 保存 → 即刻生效，无需重新编译
- **Material Design 3**：内置暗色主题，`colorSchemeSeed` 自动生成完整调色板
- **统一工具链**：`flutter pub get`、`flutter run`、`flutter build`，不用学 CMake/autotools

### 3.4 为什么不选 Electron？

| 对比维度 | Flutter | Electron |
|---------|---------|---------|
| 内存占用 | ~50MB | ~200MB+ |
| 安装包大小 | ~30MB | ~150MB |
| 渲染引擎 | Skia (GPU) | Chromium |
| 语言 | Dart (编译型) | JavaScript |
| 系统托盘 | 原生插件 | 原生模块 |

对于一个需要常驻后台的系统监控工具，内存占用是关键指标。Flutter 的 Skia 引擎比完整的 Chromium 轻量得多。

---

## 4. 依赖分析

```yaml
dependencies:
  provider: ^6.1.5+1     # 状态管理：ChangeNotifier + Consumer
  window_manager: ^0.5.1  # 原生窗口：尺寸、位置、关闭拦截
  tray_manager: ^0.5.3    # 系统托盘：图标、菜单、标题
```

**只有 3 个业务依赖**。这是刻意控制的（详见 [08 设计决策](08-design-decisions.md)）。

每个依赖的职责单一明确：
- `provider`：管理应用状态
- `window_manager`：控制原生窗口行为
- `tray_manager`：操作系统托盘

没有引入路由库（只有单页面）、网络库（不联网）、数据库（不需要持久化）、代码生成（数据类简单）。

---

## 5. 技术要求

```bash
# 环境
Flutter SDK ≥ 3.x
Dart SDK ≥ 3.12.2
Linux (需 /proc 文件系统)

# GNOME 用户额外步骤（其他 DE 自带托盘支持）
sudo dnf install gnome-shell-extension-appindicator
```

---

## 延伸练习

1. 运行 `flutter run -d linux`，观察控制台输出，理解启动流程
2. 尝试修改 `pubspec.yaml` 中的 `version` 字段，重新构建看效果
3. 思考：如果要用 Electron 重写，哪些部分可以复用？哪些需要重写？

---

下一章：[02 架构全景](02-architecture-overview.md) — 四层架构如何组织，数据从 Linux 内核流向屏幕上每个像素。
