# 02 · 架构全景 — 四层架构与数据流向

> **回答什么问题**：代码如何分层？每层职责是什么？数据从内核到屏幕经过了哪些步骤？
> **对应代码**：所有 `lib/` 目录下的文件

---

## 1. 分层架构图

```
┌─────────────────────────────────────────────┐
│                                             │
│   UI Layer  (screens/ + widgets/)           │  ← 声明式 Widget，订阅状态变化
│   DashboardScreen · UsageGauge              │
│                                             │
├─────────────────────────────────────────────┤
│                                             │
│   State Layer  (providers/)                 │  ← ChangeNotifier，持有数据，定时轮询
│   DashboardProvider                         │
│                                             │
├─────────────────────────────────────────────┤
│                                             │
│   Service Layer  (services/)                │  ← 读 /proc，执行 shell，并发 I/O
│   SystemMonitor                             │
│                                             │
├─────────────────────────────────────────────┤
│                                             │
│   Model Layer  (models/)                    │  ← 不可变数据类，纯 Dart 对象
│   SystemInfo · CpuInfo · MemoryInfo · ...   │
│                                             │
└─────────────────────────────────────────────┘
```

这是经典的 **四层架构**，依赖方向严格自上而下：

```
UI ──→ State ──→ Service ──→ Model

上层依赖下层，下层不知道上层存在
```

---

## 2. 各层职责

### 2.1 Model 层 — 数据结构定义

```dart
// models/system_info.dart — 纯数据，无行为
class CpuInfo {
  final double usagePercent;
  final int cores;
  final String model;
  const CpuInfo({...});
}
```

**原则**：
- 所有属性都是 `final`，构造后不可变
- 所有构造器都是 `const`
- 不包含任何业务逻辑（没有方法，只有数据）

> 为什么不可变？—— 因为数据从 Service 层到 UI 层是单向流动的。如果数据在中途被修改，追踪 bug 将非常困难。不可变性保证了"数据在哪里创建，就在哪里保持一致"。

### 2.2 Service 层 — 数据采集

```dart
// services/system_monitor.dart — 与 Linux 内核交互
class SystemMonitor {
  Future<SystemInfo> fetchAll() async {
    final results = await Future.wait([
      _fetchCpu(),     // 读 /proc/stat，采样差分
      _fetchMemory(),  // 读 /proc/meminfo
      _fetchDisks(),   // 执行 df -h
      _fetchNetworks(),// 读 /proc/net/dev
    ]);
    return SystemInfo(
      cpu: results[0],
      memory: results[1],
      disks: results[2],
      networks: results[3],
    );
  }
}
```

**原则**：
- 封装所有平台相关逻辑（文件 I/O、进程调用）
- 返回干净的 Model 对象，调用方无需关心数据来源
- 四项采集用 `Future.wait` 并行执行，降低延迟

### 2.3 State 层 — 状态管理

```dart
// providers/dashboard_provider.dart — 数据的持有者和分发者
class DashboardProvider extends ChangeNotifier {
  SystemInfo? _data;
  Timer? _timer;

  void start() {
    _refresh();
    _timer = Timer.periodic(Duration(seconds: 3), (_) => _refresh());
  }

  Future<void> _refresh() async {
    _data = await _monitor.fetchAll();
    notifyListeners();  // 触发 UI 重建
  }
}
```

**原则**：
- 持有 `SystemMonitor` 实例
- 用 `Timer` 实现周期性自动刷新
- 数据变化时调用 `notifyListeners()`
- 错误不中断流程（捕获异常 → 存入 `_error` → 继续定时器）

### 2.4 UI 层 — 界面渲染

```dart
// screens/dashboard_screen.dart — 声明式 UI
Consumer<DashboardProvider>(
  builder: (context, provider, _) {
    final info = provider.data!;
    return Column(children: [
      Row(children: [
        Expanded(child: _cpuCard(info.cpu)),
        Expanded(child: _memoryCard(info.memory)),
      ]),
      ...info.disks.map((d) => _diskCard(d)),
    ]);
  },
)
```

**原则**：
- 通过 `Consumer` 订阅状态变化
- 将数据映射为 Widget 树
- 使用 `Expanded` + `Row` 实现响应式并排布局
- 私有方法组织卡片构建逻辑（`_cpuCard`, `_memoryCard`, ...）

---

## 3. 完整数据流向

一次完整的数据刷新流程：

```
Step 1: Timer 触发 (每 3 秒)
        │
Step 2: DashboardProvider._refresh()
        │  └─→ SystemMonitor.fetchAll()
        │       │
        │       ├─ _fetchCpu()      ← 读 /proc/stat × 2  (间隔200ms)
        │       ├─ _fetchMemory()   ← 读 /proc/meminfo
        │       ├─ _fetchDisks()    ← 执行 df -h
        │       └─ _fetchNetworks() ← 读 /proc/net/dev
        │              │
        │       (Future.wait 并行执行)
        │              │
        │       SystemInfo 对象组装完成
        │
Step 3: _data = info; notifyListeners()
        │
Step 4: Consumer<DashboardProvider> 收到通知
        │  └─→ builder 函数被调用
        │       │
        │       provider.data 是最新 SystemInfo
        │       │
Step 5: Widget 树重建
        │  └─→ CPU Card 更新百分比
        │  └─→ Memory Card 更新数值
        │  └─→ Disk Cards 更新使用率
        │  └─→ Network Cards 更新流量
        │
Step 6: 帧渲染 → 用户看到新数据
```

整个流程中，数据经历了 **5 次传递**，但每次都是单向的：

```
Linux /proc ──→ SystemMonitor ──→ DashboardProvider ──→ Consumer ──→ Widget
  (内核态)      (Service 层)      (State 层)            (UI 层)      (渲染)
```

没有回调地狱，没有事件总线，没有全局变量。这就是分层架构的价值。

---

## 4. 依赖方向规则

```
✅ 允许的依赖方向：
   dashboard_screen.dart → dashboard_provider.dart → system_monitor.dart → system_info.dart
   (UI 依赖 State 依赖 Service 依赖 Model)

❌ 禁止的依赖方向：
   system_info.dart → system_monitor.dart   (Model 不应依赖 Service)
   system_monitor.dart → dashboard_provider.dart  (Service 不应依赖 State)
   dashboard_provider.dart → dashboard_screen.dart (State 不应依赖 UI)
```

这确保了：
- **Model 层**可以独立测试（纯数据，无副作用）
- **Service 层**可以替换（未来换到 Windows 只需重写 Service）
- **UI 层**可以重构（不影响业务逻辑）

---

## 5. 一个反例

如果不分层，把数据采集直接写在 Widget 里会怎样？

```dart
// ❌ 反模式：Widget 直接读 /proc
class DashboardScreen extends StatefulWidget {
  @override
  Widget build(BuildContext context) {
    final cpuInfo = File('/proc/stat').readAsStringSync(); // 阻塞 UI!
    return Text(cpuInfo);
  }
}
```

问题：
1. **阻塞 UI 线程** — `readAsStringSync()` 在 build 阶段同步等待 I/O
2. **测试困难** — 无法 mock `/proc` 文件系统
3. **不可移植** — Windows/macOS 没有 `/proc`
4. **重复代码** — 多个 Widget 需要同样的数据时，每处都读一遍

SysMonitor 的分层架构恰好解决了这些问题。

---

## 延伸练习

1. 画出当前项目的依赖关系图（用箭头标注方向）
2. 思考：如果要添加 GPU 温度监控，新代码应该放在哪几层？
3. 尝试解读 `app.dart` 的代码，它属于哪一层？它与 provider 层是什么关系？

---

上一章：[01 项目概述](01-project-overview.md)
下一章：[03 数据模型](03-data-models.md) — 深入 Model 层，理解不可变数据类的设计哲学。
