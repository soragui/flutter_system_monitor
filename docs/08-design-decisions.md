# 08 · 设计决策 — 为什么这样设计？不做的事同样重要

> **回答什么问题**：回顾全局，理解每个架构决策背后的理由。为什么不引入更多依赖？为什么不拆更多文件？错误处理的原则是什么？
> **对应代码**：整个项目

---

## 1. 决策全景图

| 决策 | 选择 | 为什么不做另一种 |
|------|------|----------------|
| 状态管理 | Provider + ChangeNotifier | 不用 BLoC/Riverpod：单页面不需要 Stream |
| 数据采集 | 纯 Dart + /proc 文件系统 | 不用原生插件：维护成本 > 收益 |
| 并发 | Future.wait 并行采集 | 不用 Isolate：I/O 密集型，不需要多线程 |
| UI 组件 | 卡片逻辑内联方法 | 不拆独立文件：没有复用场景，过早抽象 |
| 依赖数量 | 3 个业务依赖 | 不引入路由/数据库/DI/代码生成 |
| 错误处理 | 捕获 + 静默降级 | 不抛异常给 UI：已有数据时继续显示旧数据 |
| 类型设计 | 扁平不可变数据类 | 不深度嵌套：监控数据本身简单 |
| 构建目标 | Linux only | 不跨平台（当前阶段）：专注做好一个平台 |

---

## 2. 架构决策详解

### 2.1 为什么只有 3 个业务依赖？

```yaml
dependencies:
  provider: ^6.1.5+1      # 状态管理
  window_manager: ^0.5.1   # 窗口控制
  tray_manager: ^0.5.3     # 系统托盘
```

不是"来不及加"，而是**刻意不加**。每一个被排除的依赖都有一个明确的理由：

| 被排除的依赖 | 理由 |
|------------|------|
| `go_router` / 路由库 | 只有单页面，不需要路由 |
| `freezed` / 代码生成 | 7 个数据类，手写更快，codegen 增加维护负担 |
| `get_it` / DI 容器 | 只有一个 Provider，手工创建即可 |
| `dio` / 网络库 | 不联网 |
| `shared_preferences` | 不需要持久化 |
| `flutter_bloc` | ChangeNotifier 够用，BLoC 增加概念负担 |
| `equatable` | 不需要比较数据类实例 |

> **核心原则**：每一个依赖都是债务。它需要你跟踪版本更新、处理破坏性变更、理解其 API 设计哲学。在 700 行代码的项目中，3 个依赖是合理上限。

### 2.2 为什么不拆更多文件？

当前文件结构（12 个 Dart 文件）：

```
lib/
├── main.dart                 # 1. 入口
├── app.dart                  # 2. 外壳
├── core/theme.dart           # 3. 主题
├── models/system_info.dart   # 4. 模型
├── services/system_monitor.dart  # 5. 采集
├── providers/dashboard_provider.dart  # 6. 状态
├── screens/dashboard_screen.dart     # 7. UI 主逻辑
└── widgets/
    ├── usage_gauge.dart      # 8. 复用组件
    ├── section_header.dart   # 9. 分区标题
    ├── cpu_card.dart         # 10. (遗留)
    ├── memory_card.dart      # 11. (遗留)
    ├── disk_card.dart        # 12. (遗留)
    └── network_card.dart     # 13. (遗留)
```

注意到 `widgets/` 下的 4 个卡片文件标注了 "(遗留)"。在项目演进中，它们被重构内联到了 `dashboard_screen.dart`。之所以保留文件而不是删除，是因为它们在重构过程中可以作为对比参考。

**拆文件的判断标准**：

```
一个类/函数应该独立成文件，当且仅当：
  ✓ 被多个文件引用
  ✓ 有自己的测试文件
  ✓ 可以被独立理解和修改

不满足以上任何一个条件 → 保持在同一文件中
```

`UsageGauge` 独立是因为被 CPU 和 Memory 两处使用。`SectionHeader` 独立是因为它是通用 UI 组件。卡片方法只在一个文件中使用 → 保持内联。

### 2.3 错误处理的三级策略

```
Level 1 — Service 层
  _read('/proc/stat')  → 捕获所有异常 → 返回空字符串
  _fetchDisks()        → 捕获所有异常 → 返回空列表
  原则：单点失败不影响整体，返回安全默认值

Level 2 — Provider 层
  _refresh()  → 捕获所有异常 → 存入 _error
  原则：错误不中断定时器，保留上次有效数据

Level 3 — UI 层
  if (hasError && data == null)  → 错误页 + 重试
  if (hasError && data != null)  → 显示旧数据（优雅降级）
  原则：有数据时永远不白屏
```

这三层形成了一条"异常防火墙"：每一层都阻止错误向上传播，越来越温和地处理。

---

## 3. 不做的事（YAGNI 原则）

YAGNI = You Aren't Gonna Need It，是极端编程（XP）的核心原则。

### 3.1 不做依赖注入

```dart
// ❌ 过早的 DI
@injectable
class DashboardProvider extends ChangeNotifier {
  final SystemMonitor _monitor;
  DashboardProvider(this._monitor);  // 构造器注入
}

// ✅ 当前做法
class DashboardProvider extends ChangeNotifier {
  final SystemMonitor _monitor = SystemMonitor();  // 直接创建
}
```

当只有一个 Provider、一个 Service 时，DI 容器是多余的。把它引入进来需要：
1. 添加 `get_it` / `injectable` 依赖
2. 配置注入规则
3. 运行代码生成
4. 团队理解 DI 概念

收益？在这个项目中几乎为零。

### 3.2 不做数据持久化

没有 `SharedPreferences`，没有 SQLite。为什么？

- 监控数据是**实时数据**，上一秒的 CPU 使用率下一秒已经没有意义
- 用户配置（窗口尺寸、刷新间隔）可预留但暂未实现
- 如果未来需要"保存历史数据画折线图"——那是一个新功能，到时候再加存储

### 3.3 不做跨平台抽象

```dart
// ❌ 过早的跨平台抽象
abstract class SystemDataCollector {
  Future<SystemInfo> fetchAll();
}
class LinuxCollector implements SystemDataCollector { ... }
class WindowsCollector implements SystemDataCollector { ... }

// ✅ 当前做法
class SystemMonitor { ... }  // Linux 实现，零抽象
```

当前项目只编译 Linux。如果未来需要 Windows 支持，到时再抽象。现在加抽象层 = 增加代码复杂度而没有对应的测试覆盖。

---

## 4. 可扩展性预留

虽然不做过度抽象，但项目有意保留了一些"扩展点"：

| 扩展点 | 当前状态 | 如何扩展 |
|--------|---------|---------|
| 新增指标（GPU 温度） | `SystemMonitor` 有 4 个采集方法 | 新增 `_fetchGpu()`，加入 `Future.wait` |
| 新增卡片 | `DashboardScreen` 用 Column 排列 | 在 Column 的 children 中插入新 Widget |
| 调整刷新频率 | `Timer.periodic` 硬编码 3 秒 | `start()` 接受 `interval` 参数 |
| 多页面 | 单页面 | 引入 `go_router`，`DashboardScreen` 作为子页面 |
| 持久化配置 | 无 | 引入 `shared_preferences`，在 `_initTray` 中读取 |

---

## 5. 代码质量标准

### 5.1 命名约定

| 层级 | 命名模式 | 示例 |
|------|---------|------|
| Model | `XxxInfo` | `CpuInfo`, `MemoryInfo` |
| Service | `XxxMonitor` / `SystemXxx` | `SystemMonitor` |
| Provider | `XxxProvider` / `XxxNotifier` | `DashboardProvider` |
| Screen | `XxxScreen` 或 `XxxPage` | `DashboardScreen` |
| Widget | 描述性名词 | `UsageGauge`, `SectionHeader` |

### 5.2 注释风格

```dart
// ── Section divider ──

/// Documentation comment for public API

// ════════════════════════════════
// Block header for logical sections
// ════════════════════════════════

// Inline comment for non-obvious logic
```

### 5.3 文件组织

```
lib/
├── main.dart          # 入口：越短越好
├── app.dart           # 组装：Provider + Tray + Window
├── core/              # 横切关注点（主题）
├── models/            # 纯数据（无行为）
├── services/          # 平台相关（I/O、进程）
├── providers/         # 状态管理（ChangeNotifier）
├── screens/           # 页面级 Widget
└── widgets/           # 可复用组件
```

这个结构与 Flutter 社区的"feature-first" (by feature) 不同，采用了 "layer-first" (by layer)。选择 layer-first 的原因：
- 项目只有一个 feature（dashboard），feature-first 没有意义
- layer-first 让依赖方向一目了然

---

## 6. 总结：简洁是一种能力

SysMonitor 证明了一个观点：**好的架构不是加出来的，是减出来的**。

```
项目统计：
  总 Dart 文件：8 个（去除遗留文件）
  总代码行数：~700 行
  业务依赖：3 个
  数据模型：5 个类
  架构层级：4 层
  页面数：1
```

在这个规模下，它覆盖了：

- ✅ Linux 系统底层数据采集（/proc 解析）
- ✅ 并发 I/O 优化（Future.wait）
- ✅ 响应式状态管理（Provider + ChangeNotifier）
- ✅ Material 3 暗色 UI（colorSchemeSeed）
- ✅ 原生窗口控制（尺寸 + 关闭拦截）
- ✅ 系统托盘集成（图标 + 菜单 + 实时标题）
- ✅ 三级错误处理策略
- ✅ 正确的生命周期管理

它不是一个"大"项目，但它是一个**完整**的项目。它展示了一个桌面应用应该怎么做，以及更重要的是 — **不应该做什么**。

---

## 延伸练习（终篇）

1. 尝试给项目添加一个`--minimized` 命令行参数（启动时直接最小化到托盘），观察需要改动哪些文件
2. 用 `flutter analyze` 运行代码质量检查，理解每条 lint 规则的意义
3. 思考：如果要做一个"多服务器监控"版本（同时监控多台机器），架构需要如何调整？

---

上一章：[07 桌面集成](07-desktop-integration.md)
返回：[00 系列总目录](00-index.md)

---

*系列完 · 2026-07*
