# SysMonitor — Flutter 桌面系统监控应用

> **面向读者**：Flutter 开发者、软件工程师  
> **技术栈**：Flutter 3.x + Dart 3.12+ · Provider · window_manager · tray_manager  
> **目标平台**：Linux Desktop

---

## 目录

1. [项目概述](#1-项目概述)
2. [项目架构](#2-项目架构)
3. [数据采集层 — /proc 虚拟文件系统](#3-数据采集层--proc-虚拟文件系统)
4. [状态管理层 — Provider 模式](#4-状态管理层--provider-模式)
5. [UI 设计层](#5-ui-设计层)
6. [桌面集成 — 窗口与系统托盘](#6-桌面集成--窗口与系统托盘)
7. [关键技术决策与设计原则](#7-关键技术决策与设计原则)
8. [构建与运行](#8-构建与运行)

---

## 1. 项目概述

### 1.1 项目简介

SysMonitor 是一个使用 Flutter 构建的 Linux 桌面系统监控工具。它以轻量级常驻窗口的形式运行，实时展示 CPU 使用率、内存占用、磁盘使用情况和网络流量等关键系统指标。

### 1.2 核心功能

| 功能 | 描述 |
|------|------|
| CPU 监控 | 实时 CPU 使用率百分比、核心数、型号信息 |
| 内存监控 | 已用/总量/可用内存，支持 KB/MB/GB 自动单位换算 |
| 磁盘监控 | 所有挂载点的使用率、已用/剩余空间 |
| 网络监控 | 各网卡的接收(RX)/发送(TX)字节数 |
| 系统托盘 | 最小化到托盘，托盘图标悬停显示 CPU/MEM 摘要 |
| 定时刷新 | 每 3 秒自动拉取最新数据 |

### 1.3 为什么用 Flutter 做桌面应用？

选择 Flutter 而非传统 GTK/Qt 等 Linux 原生工具链，几个原因：

1. **跨平台潜力**：同一套代码可编译到 Linux/Windows/macOS，扩展成本低
2. **声明式 UI**：Widget 树天然适合数据驱动的监控面板，状态变化自动触发 UI 更新
3. **热重载**：修改 UI 即刻看到效果
4. **Material Design 3**：内置暗色主题支持

### 1.4 为什么不选 Electron？

| 对比维度 | Flutter | Electron |
|---------|---------|---------|
| 内存占用 | ~50MB | ~200MB+ |
| 安装包大小 | ~30MB | ~150MB |
| 渲染引擎 | Skia (GPU) | Chromium |
| 语言 | Dart (编译型) | JavaScript |

对常驻后台的系统监控工具来说，内存是关键。Skia 引擎比完整 Chromium 轻得多。

---

## 2. 项目架构

### 2.1 目录结构

```
sys_monitor/
├── lib/
│   ├── main.dart                  # 应用入口，窗口初始化
│   ├── app.dart                   # MaterialApp 外壳，托盘/窗口生命周期
│   ├── core/
│   │   └── theme.dart             # 暗色主题 & 用量颜色映射
│   ├── models/
│   │   └── system_info.dart       # 数据模型（纯 Dart 类）
│   ├── services/
│   │   └── system_monitor.dart    # 系统数据采集（读 /proc，调 shell）
│   ├── providers/
│   │   └── dashboard_provider.dart # 状态管理（ChangeNotifier + Timer）
│   ├── screens/
│   │   └── dashboard_screen.dart   # 主仪表盘页面
│   └── widgets/
│       ├── usage_gauge.dart        # 圆形 + 线性进度指示器
│       ├── cpu_card.dart           # CPU 卡片（已废弃，逻辑内联到 dashboard）
│       ├── memory_card.dart        # 内存卡片（同上）
│       ├── disk_card.dart          # 磁盘卡片（同上）
│       ├── network_card.dart       # 网络卡片（同上）
│       └── section_header.dart     # 分区标题
├── assets/
│   └── tray_icon.png              # 系统托盘图标
├── linux/                         # Linux 平台原生配置（CMake + C++ runner）
├── pubspec.yaml
└── analysis_options.yaml
```

### 2.2 分层架构图

```
┌─────────────────────────────────────────────┐
│  UI Layer (screens/ + widgets/)             │
│  DashboardScreen · UsageGauge               │
│  订阅状态变化 → 重建 Widget                   │
├─────────────────────────────────────────────┤
│  State Layer (providers/)                   │
│  DashboardProvider : ChangeNotifier         │
│  持有数据 · Timer 轮询 · 通知 UI              │
├─────────────────────────────────────────────┤
│  Service Layer (services/)                  │
│  SystemMonitor                              │
│  读 /proc 文件系统 · 执行 shell 命令          │
├─────────────────────────────────────────────┤
│  Model Layer (models/)                      │
│  SystemInfo · CpuInfo · MemoryInfo · ...    │
│  不可变数据类                                 │
└─────────────────────────────────────────────┘
```

### 2.3 数据流向

```
/proc 文件系统 / shell 命令
        │
        ▼
  SystemMonitor.fetchAll()
        │  Future.wait([cpu, memory, disk, network])
        ▼
  DashboardProvider._refresh()
        │  _data = info; notifyListeners()
        ▼
  Consumer<DashboardProvider>
        │  builder(context, provider, _)
        ▼
  DashboardScreen._body()
        │
        ▼
  CPU Card │ Memory Card │ Disk Cards │ Network Cards
```

---

## 3. 数据采集层 — /proc 虚拟文件系统

### 3.1 为什么不使用第三方系统监控库？

Linux 的 `/proc` 虚拟文件系统提供了几乎所有系统监控数据的标准接口。直接读取 `/proc` 比引入第三方库有几点优势：

- **零依赖**：不需要额外安装系统软件包（如 `lm-sensors`、`sysstat`）
- **高性能**：`/proc` 是内核内存映射文件，读取开销极低
- **普适性**：所有主流 Linux 发行版都提供 `/proc`
- **精确控制**：只获取需要的字段，避免冗余数据解析

### 3.2 CPU 使用率采集

**原理**：读取 `/proc/stat` 两次（间隔 200ms），计算时间差。

```
/proc/stat 第一行格式：
cpu  user nice system idle iowait irq softirq steal ...

算法：
  total = user + nice + system + idle + iowait + irq + softirq + steal
  idle  = idle + iowait
  usage% = (Δtotal - Δidle) / Δtotal × 100
```

**实现要点**（`system_monitor.dart:44-71`）：
- 缓存 CPU 型号（首次从 `/proc/cpuinfo` 读取，失败则回退到 `lscpu` 命令）
- 使用 `Future.delayed(200ms)` 而非 `sleep`，不阻塞 UI 事件循环
- 边界保护：除零检查、`clamp(0, 100)`

### 3.3 内存采集

**原理**：解析 `/proc/meminfo`，提取 `MemTotal`、`MemAvailable`、`MemFree`、`Buffers`、`Cached`、`SReclaimable`。

**实现要点**（`system_monitor.dart:114-144`）：
- 优先使用 `MemAvailable`（内核 3.14+），这是最准确的可用内存指标
- 回退方案：`MemFree + Buffers + Cached + SReclaimable`
- 使用正则 `RegExp(r'(\d+)')` 提取数值，兼容不同内核的输出格式

### 3.4 磁盘采集

**原理**：执行 `df -h` 命令，解析输出。

**实现要点**（`system_monitor.dart:148-171`）：
- 过滤只保留以 `/` 开头的挂载点（排除 `tmpfs`、`devtmpfs` 等虚拟文件系统）
- 使用 `df -h` 的 `-h` 参数直接获得人类可读的容量字符串（避免手动格式化 GB/TB）
- 空值安全：`double.tryParse` 处理非数字情形

### 3.5 网络采集

**原理**：读取 `/proc/net/dev`，解析各网卡的 RX/TX 字节数。

**实现要点**（`system_monitor.dart:175-198`）：
- 过滤 `lo` 回环接口
- 过滤零流量接口（`rx == 0 && tx == 0`）
- 使用 `whereType<NetworkInfo>()` 安全过滤 null

---

## 4. 状态管理层 — Provider 模式

### 4.1 为什么选择 Provider？

Provider 是 Flutter 官方推荐的状态管理方案。对于本项目"单一数据源 → 多个 UI 组件"的场景，选它很自然：

- **ChangeNotifier** 提供了最简单的响应式编程模型
- **Consumer Widget** 精确控制重建范围，避免不必要的 rebuild
- 不需要额外引入 Redux/BLoC 的概念负担

### 4.2 DashboardProvider 设计

```dart
class DashboardProvider extends ChangeNotifier {
  SystemInfo? _data;      // 当前系统数据快照
  bool _loading = true;   // 首次加载标志
  String? _error;         // 最后一次错误信息
  Timer? _timer;          // 定时器（3 秒周期）

  void start() { ... }    // 启动自动刷新
  Future<void> refresh()  // 手动 / 定时刷新
  String get trayTitle    // 托盘标题（CPU% + MEM%）
}
```

**关键设计决策**：

1. **Timer + ChangeNotifier 组合**：定时器触发刷新 → 数据更新 → `notifyListeners()` → UI 自动重建。这是一个经典的"定时轮询"模式。

2. **错误不中断**：`_refresh()` 方法捕获所有异常存入 `_error`，不中断定时器。这意味着即使某次采集失败（如权限不足读取 `/proc`），下一次定时轮询仍会正常执行。

3. **首屏加载与后续更新的区分**：
   - `isLoading && data == null` → 显示 loading 动画
   - `hasError && data == null` → 显示错误页面（有重试按钮）
   - `data != null` → 正常显示，错误在数据存在时不阻断 UI

4. **生命周期管理**：`dispose()` 中取消 Timer，`app.dart` 在 `dispose()` 中调用 `_provider.dispose()`，确保没有内存泄漏。

---

## 5. UI 设计层

### 5.1 布局策略：从 ListView 到 Grid 的演进

**v1 设计（ListView）**：所有卡片在垂直方向线性排列。简单直观，但存在问题：
- CPU 和 Memory 卡片不能并排，浪费水平空间
- 磁盘和网络混在一起，视觉层级不清晰

**v2 设计（当前版本 — Grid 布局）**：

```
┌──────────────────────────────────┐
│  AppBar: System Monitor  [─] [↻] │
├──────────────┬───────────────────┤
│              │                   │
│  CPU Card    │  Memory Card      │  ← Row（等宽并排）
│  64px gauge  │  64px gauge       │
│  + model     │  + used/total     │
│              │                   │
├──────────────┴───────────────────┤
│  ── Disks ──                     │
│  /dev/sda1   45% ████████░░░░    │
│  /home        78% ████████████░  │  ← 全宽列表
├──────────────────────────────────┤
│  ── Network ──                   │
│  eth0  ↓1.2GB  ↑340MB           │  ← 全宽列表
└──────────────────────────────────┘
```

**实现细节**：
- 外层 `SingleChildScrollView` + `Column`（替代 `ListView`）
- CPU/Memory 用 `IntrinsicHeight` + `Row` + `Expanded` 保持等高
- 磁盘/网络用 `Column` 内嵌 `Card` 列表，天然撑满宽度

### 5.2 UsageGauge 组件设计

UsageGauge 是复用率最高的组件，同时出现在 CPU 和 Memory 卡片中。

```dart
class UsageGauge extends StatelessWidget {
  final double percent;  // 0-100
  final double size;     // 直径，默认 50
}
```

**设计要点**：
- 圆形 `CircularProgressIndicator` + 百分比文字居中叠加（`Stack` + `Center`）
- 线性 `LinearProgressIndicator` 显示在圆形下方（`SizedBox` 约束宽度，避免无限宽错误）
- 颜色根据使用率动态变化：`<50% 绿` → `<75% 橙` → `<90% 深橙` → `≥90% 红`

**踩坑：无限宽度错误**：
Row 中嵌套 Column 再嵌套 LinearProgressIndicator 时，Column 从 Row 获得无界宽度（`BoxConstraints(w=Infinity)`），而 LinearProgressIndicator 尝试填充所有可用宽度，导致抛出 "BoxConstraints forces an infinite width" 异常。解决方法是 `SizedBox(width: ...)` 约束宽度。

### 5.3 暗色主题

```dart
class AppTheme {
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF1565C0),  // 蓝色基调
    brightness: Brightness.dark,
  );
}
```

使用 Material 3 的 `colorSchemeSeed` 自动生成完整的暗色调色板，确保所有组件（Card、Text、Icon）的颜色协调统一。

---

## 6. 桌面集成 — 窗口与系统托盘

### 6.1 窗口管理

使用 `window_manager` 插件控制原生窗口行为：

```dart
// main.dart
await windowManager.ensureInitialized();
await windowManager.setPreventClose(true);   // 关闭 → 最小化到托盘
await windowManager.setTitle('System Monitor');
await windowManager.setSize(const Size(420, 620));
await windowManager.center();
```

关键设计：`setPreventClose(true)` 使点击关闭按钮时触发 `onWindowClose` 回调而非退出应用。回调中调用 `windowManager.hide()` 将窗口隐藏（最小化到托盘）。

### 6.2 系统托盘

使用 `tray_manager` 插件实现系统托盘功能：

```dart
// 初始化托盘
await trayManager.setIcon('assets/tray_icon.png');
await trayManager.setContextMenu(Menu(items: [
  MenuItem(key: 'dashboard', label: 'Dashboard'),
  MenuItem.separator(),
  MenuItem(key: 'exit', label: 'Exit'),
]));

// 托盘标题实时更新（显示 CPU/MEM 百分比）
trayManager.setTitle('CPU45% MEM62%');
```

**托盘标题更新优化**：
- 使用 `SchedulerBinding.addPostFrameCallback` 将托盘标题设置推迟到帧渲染后，避免在 build 阶段执行可能失败的原生调用
- 使用 `_lastTrayTitle` 和 `_trayTitlePending` 防止重复设置和并发问题

---

## 7. 关键技术决策与设计原则

### 7.1 数据采集：纯 Dart + /proc，零原生插件

**决策**：不引入任何 C/C++ 原生插件来做系统监控，完全使用 Dart 的文件 I/O 和进程调用。

**原因**：
- Flutter 的 platform channel 涉及序列化/反序列化开销，对于简单的文件读取反而不如直接 `File.readAsString()`
- 避免维护平台特定代码（CMakeLists.txt 修改、C++ 编译链接问题）
- 基于 `/proc` 的采集逻辑在所有 Linux 发行版上行为一致

### 7.2 并发数据采集：Future.wait

```dart
final results = await Future.wait([
  _fetchCpu(),
  _fetchMemory(),
  _fetchDisks(),
  _fetchNetworks(),
]);
```

四项采集互不依赖，使用 `Future.wait` 并行执行。在 Dart 的单线程事件循环模型下，文件 I/O 操作本质上是异步非阻塞的，`Future.wait` 可以同时发起多个 I/O 请求，让 OS 内核并行处理，显著降低总延迟。

### 7.3 简洁优先的架构

本项目刻意保持架构简单：

- **无路由库**：只有单页面，不需要 go_router
- **无依赖注入框架**：手工创建 Provider 实例，在 Widget 树中传递
- **无代码生成**：没有 freezed/json_serializable，数据类纯手写
- **卡片逻辑内联**：CPU/Memory/Disk/Network 卡片从独立 Widget 文件重构为 dashboard_screen 的私有方法，减少文件数量和跨文件跳转

这不是偷懒，而是在项目复杂度范围内选最简方案。只有一个页面、四种数据类型时，引入 DI 容器或代码生成的边际收益远低于认知负担。

### 7.4 错误处理策略：优雅降级

```
数据采集失败 → _error 字段记录 → notifyListeners()
    │
    ├─ data == null（首次加载失败）→ 显示错误页 + 重试按钮
    │
    └─ data != null（后续刷新失败）→ 保留旧数据继续显示
```

原则：**已有数据时，单次采集失败不应清空整个界面**。即使网络接口偶尔无法读取或磁盘临时卸载，用户仍能看到之前采集的有效数据。

---

## 8. 构建与运行

### 8.1 环境要求

| 组件 | 版本 |
|------|------|
| Flutter SDK | ≥ 3.x |
| Dart SDK | ≥ 3.12.2 |
| 操作系统 | Linux（需支持 `/proc`） |
| 桌面环境 | 需系统托盘支持（GNOME 需安装 AppIndicator 扩展） |

### 8.2 依赖安装

```bash
cd sys_monitor
flutter pub get
```

### 8.3 运行 Debug 模式

```bash
flutter run -d linux
```

### 8.4 构建 Release 版本

```bash
flutter build linux --release
```

构建产物位于 `build/linux/x64/release/bundle/`。

### 8.5 GNOME 用户注意事项

GNOME 默认不显示系统托盘图标。需要安装扩展：

```bash
# Fedora
sudo dnf install gnome-shell-extension-appindicator

# Ubuntu/Debian
sudo apt install gnome-shell-extension-appindicator
```

安装后重启 GNOME Shell（`Alt+F2` → 输入 `r` → 回车），托盘图标即可正常显示。

---

## 附录 A：依赖清单

| 包名 | 版本 | 用途 |
|------|------|------|
| `provider` | ^6.1.5 | 状态管理 |
| `window_manager` | ^0.5.1 | 窗口尺寸/位置/关闭行为控制 |
| `tray_manager` | ^0.5.3 | 系统托盘图标与菜单 |
| `cupertino_icons` | ^1.0.8 | iOS 风格图标（未实际使用，模板自带） |
| `flutter_lints` | ^6.0.0 | Lint 规则（开发依赖） |

## 附录 B：数据模型定义

```dart
SystemInfo
├── CpuInfo
│   ├── usagePercent: double   // 0.0 ~ 100.0
│   ├── cores: int
│   └── model: String
├── MemoryInfo
│   ├── totalKb: int
│   ├── usedKb: int
│   ├── availableKb: int
│   └── usagePercent: double
├── List<DiskInfo>
│   ├── mountPoint: String     // 如 "/"、"/home"
│   ├── total: String          // 如 "256G"（df -h 输出）
│   ├── used: String
│   ├── available: String
│   └── usagePercent: double
└── List<NetworkInfo>
    ├── interfaceName: String  // 如 "eth0"、"wlan0"
    ├── rxBytes: int
    └── txBytes: int
```

---

*文档版本: 1.0 · 最后更新: 2026-06*
