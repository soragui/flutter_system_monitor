# SysMonitor 深度解析 — 系列教材总目录

> **面向读者**：Flutter 中级开发者、软件工程师、对 Flutter 桌面开发感兴趣的架构师
> **前置知识**：Dart 语言基础、Flutter Widget 树概念、Linux 基本命令行操作
> **总篇幅**：9 篇，逐层递进

---

## 为什么写这个系列？

SysMonitor 是一个 Flutter 桌面应用，~700 行代码，但覆盖了桌面应用的四个核心部分：

- **数据采集**：解析 Linux `/proc` 文件系统，并行 I/O
- **状态管理**：Provider + ChangeNotifier
- **UI 设计**：Material 3 暗色主题、Grid + List 混合布局
- **桌面集成**：原生窗口控制、系统托盘、生命周期管理

700 行代码，不大到淹没在业务逻辑里，也不小到只是玩具。正好拿来学 Flutter 桌面开发。

---

## 系列结构（总 → 分 → 总）

```
┌─ 总（建立全局认知）────────────────────────────────┐
│                                                    │
│  [01] 项目概述        这个项目是什么，解决什么问题    │
│  [02] 架构全景        四层架构，数据如何流动          │
│                                                    │
├─ 分（逐层深入剖析）────────────────────────────────┤
│                                                    │
│  [03] 数据模型        不可变数据类的设计哲学          │
│  [04] 数据采集        /proc 文件系统与并发 I/O       │
│  [05] 状态管理        Provider 模式的设计与陷阱       │
│  [06] UI 设计         Widget 树、布局策略、组件复用   │
│  [07] 桌面集成        窗口管理、系统托盘、生命周期     │
│                                                    │
├─ 总（提炼设计原则）────────────────────────────────┤
│                                                    │
│  [08] 设计决策        为什么这样设计？不做的事同样重要  │
│                                                    │
└────────────────────────────────────────────────────┘
```

---

## 各章概要

| 章节 | 核心问题 | 技术关键字 |
|------|---------|-----------|
| [01 项目概述](01-project-overview.md) | Flutter 能做桌面应用吗？怎么做？ | Flutter Desktop, Linux, 系统监控 |
| [02 架构全景](02-architecture-overview.md) | 代码如何分层？数据怎么流转？ | 四层架构, 依赖方向, 数据流向 |
| [03 数据模型](03-data-models.md) | Model 层怎么设计？为什么用不可变类？ | const constructor, data class, 扁平化 |
| [04 数据采集](04-data-collection.md) | 如何不依赖第三方库读取系统数据？ | /proc, Future.wait, 采样差分 |
| [05 状态管理](05-state-management.md) | Provider 在真实项目里怎么用？ | ChangeNotifier, Timer, 错误处理 |
| [06 UI 设计](06-ui-design.md) | 如何搭出一套好看的监控面板？ | Row+Expanded, Stack, M3暗色主题 |
| [07 桌面集成](07-desktop-integration.md) | 窗口怎么控制？系统托盘怎么做？ | window_manager, tray_manager, 生命周期 |
| [08 设计决策](08-design-decisions.md) | 为什么不做 DI？为什么不拆更多文件？ | YAGNI, 简洁优先, 错误降级 |

---

## 阅读建议

**如果你时间充裕（全部读）**：按顺序从 01 到 08，这是经过编排的学习路径。

**如果你只关心架构**：01 → 02 → 08，建立全局认知即可。

**如果你带着问题来查**：每章开头都有明确的"回答什么问题"指引，直接跳过去。

**如果你想实践**：每章末尾都有"延伸练习"，建议照着做一遍，收获远大于被动阅读。

---

## 项目源码

```bash
git clone <repo-url>
cd sys_monitor
flutter pub get
flutter run -d linux
```

源码结构：

```
lib/
├── main.dart                 # 入口
├── app.dart                  # 应用外壳
├── core/theme.dart           # 主题
├── models/system_info.dart   # 数据模型
├── services/system_monitor.dart  # 数据采集
├── providers/dashboard_provider.dart  # 状态管理
├── screens/dashboard_screen.dart     # 主页面
└── widgets/
    ├── usage_gauge.dart      # 复用组件
    ├── cpu_card.dart         # （遗留独立组件）
    ├── memory_card.dart
    ├── disk_card.dart
    ├── network_card.dart
    └── section_header.dart
```

---

准备好了？从 [01 项目概述](01-project-overview.md) 开始。
