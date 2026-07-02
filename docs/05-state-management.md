# 05 · 状态管理 — Provider 模式的设计与实践

> **回答什么问题**：Provider 在真实项目中如何组织？ChangeNotifier 的生命周期如何管理？Timer + Provider 的定时轮询模式有什么陷阱？
> **对应代码**：`lib/providers/dashboard_provider.dart` (57 行)，`lib/app.dart`

---

## 1. 为什么选择 Provider？

在 Flutter 生态中，状态管理方案众多：BLoC、Riverpod、Redux、MobX、GetX...

SysMonitor 选择 **Provider + ChangeNotifier**，基于以下判断：

| 判断维度 | Provider 的适配度 |
|---------|------------------|
| 应用规模 | 单页面，4 种数据类型 → **轻量方案足够** |
| 数据流复杂度 | 单向：采集 → 持有 → 展示 → **不需要 Stream/Event** |
| 团队/学习成本 | ChangeNotifier 是 Flutter 内置类 → **零额外概念** |
| 性能要求 | 3 秒刷新一次，非高频 → **不需要细粒度控制** |

> **选择状态管理框架的原则**：用能满足当前需求的最简单方案。别为了解决"可能"出现的复杂度而提前引入重型框架。

---

## 2. DashboardProvider 完整拆解

```dart
class DashboardProvider extends ChangeNotifier {
  // ═══════════════════════════════════════
  // 依赖
  // ═══════════════════════════════════════
  final SystemMonitor _monitor = SystemMonitor();

  // ═══════════════════════════════════════
  // 状态
  // ═══════════════════════════════════════
  SystemInfo? _data;       // 当前系统快照
  bool _loading = true;    // 首次加载中
  String? _error;          // 最后一次错误
  Timer? _timer;           // 轮询定时器

  // ═══════════════════════════════════════
  // 公开 getter（封装内部状态）
  // ═══════════════════════════════════════
  SystemInfo? get data => _data;
  bool get isLoading => _loading;
  bool get hasError => _error != null;
  String? get errorMessage => _error;
}
```

**设计要点**：

1. **`_monitor` 是私有成员** — Provider 持有 Service 实例，外部不知道数据来源
2. **所有状态字段都为私有** — 通过 getter 暴露只读访问，防止外部意外修改
3. **`Timer?` 可空** — 可能在 `start()` 前就被 `dispose()`，需要处理未初始化的情况

---

## 3. 定时轮询模式

```dart
void start({Duration interval = const Duration(seconds: 3)}) {
  _refresh();                                       // 1. 立即刷新一次
  _timer = Timer.periodic(interval, (_) => _refresh()); // 2. 启动定时器
}

Future<void> _refresh() async {
  try {
    final info = await _monitor.fetchAll();
    _data = info;
    _error = null;
  } catch (e) {
    _error = e.toString();
  } finally {
    _loading = false;
    notifyListeners();   // 无论成功失败，都通知 UI
  }
}
```

### 3.1 为什么先 _refresh() 再启动 Timer？

```
错误方式：
  _timer = Timer.periodic(3s, ...)  // 先启动定时器
  // 用户需要等 3 秒才能看到数据 ← 糟糕的首次体验

正确方式：
  _refresh()                         // 立即拉取数据
  _timer = Timer.periodic(3s, ...)   // 再启动定时器
  // 数据立即可见 ← 好的首次体验
```

### 3.2 错误不中断定时器

```dart
try {
  _data = info;      // 成功：更新数据
  _error = null;     // 清除旧错误
} catch (e) {
  _error = e.toString();  // 失败：记录错误，但不抛异常
}
```

这是关键设计：**`_refresh()` 的异常不会传播到 `Timer.periodic` 回调之外**。即使某次采集失败（如磁盘卸载导致 `df` 报错），定时器照常运行，3 秒后再次尝试。

对比错误设计：

```dart
// ❌ 错误会中断定时器
void onTick(_) async {
  _data = await _monitor.fetchAll();  // 如果抛异常，Timer 的回调终止
  notifyListeners();
}
```

---

## 4. UI 如何响应状态变化：Consumer

```dart
// dashboard_screen.dart
Consumer<DashboardProvider>(
  builder: (context, provider, _) {
    if (provider.isLoading && provider.data == null) {
      return CircularProgressIndicator();   // 首次加载
    }
    if (provider.hasError && provider.data == null) {
      return _errorView(context, provider);  // 首次加载失败
    }
    return _body(context, provider);         // 正常显示
  },
)
```

### 4.1 三种 UI 状态

| 条件 | UI 显示 | 场景 |
|------|--------|------|
| `isLoading && data == null` | 加载动画 | 应用刚刚启动 |
| `hasError && data == null` | 错误页 + 重试按钮 | 首次拉取就失败了 |
| `data != null` | 正常监控面板 | 至少成功过一次 |

### 4.2 关键细节：data != null 时容忍错误

```dart
if (p.hasError && p.data == null) {   // 注意：是 && 不是 ||
  return _errorView(context, p);
}
```

如果 `data != null`（之前成功过），即使 `hasError` 为 true，也正常显示旧数据。这是一种 **优雅降级**：

- 单次采集失败 → 保留上次数据，用户感知不到异常
- 只有从未成功过 → 显示错误页面

### 4.3 Consumer vs context.read vs context.watch

```dart
// Consumer — 精确重建（本项目使用）
Consumer<DashboardProvider>(
  builder: (context, provider, _) => Text('${provider.data?.cpu.usagePercent}'),
)

// context.watch — 整个 Widget rebuild
@override
Widget build(BuildContext context) {
  final provider = context.watch<DashboardProvider>();
  return Text('${provider.data?.cpu.usagePercent}');
}

// context.read — 只读不监听（用于事件处理）
onPressed: () => context.read<DashboardProvider>().refresh(),
```

本项目使用 `Consumer` 而非 `context.watch`，因为 DashboardScreen 是无状态 `StatelessWidget`，通过 `Consumer` 精确控制重建范围。

---

## 5. 生命周期管理

### 5.1 创建和销毁链

```
main.dart                  app.dart                    provider
─────────                  ────────                    ────────
runApp(SysMonitorShell)
                   ──→     initState()
                                │
                            _provider = DashboardProvider()
                            _provider.start()          start()
                                │                     _timer 启动
                                │
                   ──→     dispose()                  dispose()
                                │                     _timer?.cancel()
                            _provider.dispose()
```

Provider 的完整生命周期由 `app.dart` 管理：

```dart
// app.dart
class _SysMonitorShellState extends State<SysMonitorShell> {
  late final DashboardProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = DashboardProvider();
    _provider.addListener(_onProviderChanged);
    _provider.start();   // ← 启动定时器
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    _provider.dispose(); // ← 取消定时器，释放资源
    super.dispose();
  }
}
```

### 5.2 为什么 Provider 在 app.dart 创建而非 main.dart？

```dart
// ❌ 放在 main.dart
void main() {
  final provider = DashboardProvider();
  runApp(Provider.value(value: provider, child: MyApp()));
}
// 问题：main() 不管理生命周期，provider.dispose() 无人调用

// ✅ 放在 app.dart 的 State 中
// State.dispose() 确保 Widget 销毁时同步释放 Provider
```

---

## 6. 托盘标题更新：跨层通信

```dart
// app.dart — 监听 Provider 变化来更新托盘标题
void _onProviderChanged() {
  final title = _provider.trayTitle;  // "CPU45% MEM62%"
  if (title == _lastTrayTitle || _trayTitlePending) return;

  _trayTitlePending = true;
  SchedulerBinding.instance.addPostFrameCallback((_) {
    _trayTitlePending = false;
    _lastTrayTitle = title;
    trayManager.setTitle(title);
  });
}
```

这里有三个精心设计的细节：

1. **去重**：`title == _lastTrayTitle` 避免重复设置相同标题
2. **防并发**：`_trayTitlePending` 标志防止 PostFrameCallback 堆积
3. **推迟到帧后**：`addPostFrameCallback` 确保在 build 阶段结束后执行，避免在 build 中调用可能失败的原生方法

> 这是 Provider 监听器模式的应用：不通过 Widget 树，而是通过 `addListener` 让非 UI 代码也能响应状态变化。

---

## 延伸练习

1. 尝试将 `DashboardProvider` 改为 Riverpod 的 `StateNotifier`，对比两种写法的区别
2. 添加一个"刷新中"的 UI 状态（在已有数据的基础上显示一个小的 loading 指示器）
3. 修改定时器间隔为 10 秒，观察 `Future.wait` 中 200ms CPU 采样延迟的影响

---

上一章：[04 数据采集](04-data-collection.md)
下一章：[06 UI 设计](06-ui-design.md) — Widget 树的构建策略与 Material 3 暗色主题。
