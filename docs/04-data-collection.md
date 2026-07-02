# 04 · 数据采集 — /proc 文件系统与并发 I/O

> **回答什么问题**：如何在没有 C/C++ 原生扩展的情况下采集系统数据？/proc 文件系统如何工作？`Future.wait` 如何降低采集延迟？
> **对应代码**：`lib/services/system_monitor.dart` (210 行)

---

## 1. 设计决策：纯 Dart，零原生插件

SysMonitor 的一个关键设计决策：**不引入 C/C++ 原生插件来做系统监控**。

```dart
// ✅ 本项目的方式 — 纯 Dart I/O
final stat = await File('/proc/stat').readAsString();
final meminfo = await File('/proc/meminfo').readAsString();

// ❌ 替代方案 — 引入原生插件
// import 'package:system_info/system_info.dart';
// SysInfo.getCpuUsage();
```

### 为什么选择纯 Dart？

| 方案 | 优点 | 缺点 |
|------|-----|-----|
| **纯 Dart + /proc** （本项目） | 零额外依赖、所有 Linux 一致、易调试 | 需要了解 /proc 格式、对非 Linux 不可移植 |
| **原生插件** (FFI/Platform Channel) | 性能更高、可封装复杂逻辑 | 需要维护 C/C++ 代码、跨编译平台问题、链接错误难排查 |
| **调用命令行工具** (top, free, etc.) | 简单直观 | 输出格式不稳定（各发行版不同）、解析错误多、性能差 |

对于"读取几个 /proc 文件"这种简单任务，引入原生插件的麻烦远超收益。Flutter 的 `dart:io` 库完全够用。

---

## 2. CPU 使用率采集：两次采样差分法

### 2.1 原始数据：/proc/stat

```
cpu  1187234 1254 895623 12938472 24562 0 8923 0 0 0
     │       │    │      │        │     │ │     │
     user    nice system idle     iowait  ...  steal
```

Linux 内核在 `/proc/stat` 中提供了启动以来 CPU 在各状态的总时间（单位：jiffies，通常 10ms）。

### 2.2 算法

CPU 使用率不是绝对值，而是 **一段时间内的变化率**：

```
第 1 次采样 (t1):
  total1 = user + nice + system + idle + iowait + ...
  idle1  = idle + iowait

等待 200ms

第 2 次采样 (t2):
  total2 = user + nice + system + idle + iowait + ...
  idle2  = idle + iowait

使用率 = (Δtotal - Δidle) / Δtotal × 100
       = (busy_time) / total_time × 100
```

### 2.3 代码实现

```dart
Future<CpuInfo> _fetchCpu() async {
  // 1. 获取 CPU 型号（缓存，只查一次）
  await _ensureCpuModel();

  // 2. 两次采样，间隔 200ms
  final t1 = await _readCpuTimes();       // 读 /proc/stat
  await Future.delayed(const Duration(milliseconds: 200));
  final t2 = await _readCpuTimes();       // 再读一次

  // 3. 计算差分
  final idle1 = t1[3] + (t1.length > 4 ? t1[4] : 0);  // idle + iowait
  final total1 = t1.fold<int>(0, (a, b) => a + b);
  final idle2 = t2[3] + (t2.length > 4 ? t2[4] : 0);
  final total2 = t2.fold<int>(0, (a, b) => a + b);

  final totalDelta = total2 - total1;
  if (totalDelta == 0) return CpuInfo(usagePercent: 0, ...);  // 除零保护

  final pct = ((totalDelta - (idle2 - idle1)) / totalDelta * 100).clamp(0, 100);
  return CpuInfo(usagePercent: double.parse(pct.toStringAsFixed(1)), ...);
}
```

### 2.4 关键细节

**① 为什么用 `Future.delayed` 而不是 `sleep`？**

```dart
await Future.delayed(const Duration(milliseconds: 200));  // ✅ 不阻塞线程
// sleep(Duration(milliseconds: 200));                    // ❌ 阻塞当前 isolate
```

Dart 是单线程事件循环模型。`sleep` 会阻塞整个 isolate，期间所有 UI 更新、用户交互都被冻结。`Future.delayed` 返回一个在指定时间后完成的 Future，不阻塞事件循环。

**② 为什么 200ms？**

经验值。太短则采样误差大（jiffy 粒度通常 10ms），太长则用户感觉刷新慢。200ms 在精度和响应性之间取得平衡。

**③ CPU 型号缓存**

```dart
String _cpuModel = '';

Future<void> _ensureCpuModel() async {
  if (_cpuModel.isNotEmpty) return;  // 已经查过了，跳过
  // 读 /proc/cpuinfo → 解析 "model name" 行
  // 失败则尝试 lscpu 命令
  // 再失败则设为 "Unknown CPU"
}
```

CPU 型号不会变化，所以只查一次，存入实例变量 `_cpuModel`。这是典型的 **懒加载 + 缓存** 模式。

---

## 3. 内存采集：优先使用 MemAvailable

### 3.1 /proc/meminfo 格式

```
MemTotal:       16332336 kB
MemFree:          598728 kB
MemAvailable:   10483292 kB
Buffers:          234892 kB
Cached:          8723456 kB
SReclaimable:     123456 kB
```

### 3.2 为什么有 MemFree 还要用 MemAvailable？

`MemFree` 是完全未被使用的内存，但 Linux 会把大量内存用于缓存（Cached/Buffers），这些内存在需要时可以释放。

- `MemFree = 598 MB` — 听起来内存快用完了
- `MemAvailable = 10,483 MB` — 但实际上还有 10GB 可用

`MemAvailable`（内核 3.14+ 引入）是内核估算的"可以在不换页情况下分配给新进程的内存"，这才是真正有意义的"可用内存"。

```dart
final available = available > 0
    ? available                           // 优先用内核的估算
    : free + buffers + cached + sReclaimable;  // 回退方案
```

> 这个算法来自 `free` 命令的源码。SysMonitor 没有调用 `free`，而是直接复现了它的逻辑。

---

## 4. 磁盘采集：用 `df -h` 简化格式化

```dart
Future<List<DiskInfo>> _fetchDisks() async {
  final result = await Process.run('df', ['-h']);
  final lines = (result.stdout as String).split('\n');

  return lines
    .skip(1)                                    // 跳过标题行
    .map((line) => line.split(RegExp(r'\s+')))  // 按空白分割
    .where((p) => p.length >= 6 && p[0].startsWith('/'))  // 只保留物理盘
    .map((p) {
      final pct = double.tryParse(p[4].replaceAll('%', '')) ?? 0;
      return DiskInfo(
        mountPoint: p[5],
        total: p[1],      // "256G"
        used: p[2],       // "45G"
        available: p[3],  // "211G"
        usagePercent: pct,
      );
    })
    .toList();
}
```

### 为什么过滤 `p[0].startsWith('/')`？

`df -h` 的输出包含大量虚拟文件系统：

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1       256G   45G  211G  18% /
tmpfs           7.8G     0  7.8G   0% /dev/shm    ← 虚拟，排除
devtmpfs        7.8G     0  7.8G   0% /dev        ← 虚拟，排除
```

过滤以 `/` 开头的设备路径（如 `/dev/sda1`），排除 `tmpfs`、`devtmpfs` 等虚拟 FS。只展示用户真正关心的物理磁盘挂载点。

---

## 5. 网络采集：过滤无关接口

```dart
Future<List<NetworkInfo>> _fetchNetworks() async {
  final text = await _read('/proc/net/dev');
  return text
    .split('\n')
    .where((l) => l.contains(':'))
    .map((l) => l.trim().split(RegExp(r'\s+')))
    .where((p) => p[0].replaceAll(':', '') != 'lo')  // 排除回环
    .map((p) {
      final rx = int.tryParse(p[1]) ?? 0;
      final tx = int.tryParse(p[9]) ?? 0;
      if (rx == 0 && tx == 0) return null;  // 排除零流量
      return NetworkInfo(interfaceName: p[0].replaceAll(':', ''), ...);
    })
    .whereType<NetworkInfo>()  // 过滤 null
    .toList();
}
```

三层过滤：
1. **排除 `lo`** — 回环接口对用户无意义
2. **排除零流量** — 未使用的虚拟接口（如 docker bridge）
3. **`whereType<NetworkInfo>()`** — 安全过滤 null（Dart 的类型安全特性）

---

## 6. 并发优化：Future.wait

```dart
Future<SystemInfo> fetchAll() async {
  final results = await Future.wait([
    _fetchCpu(),      // 约 200ms（包含采样等待）
    _fetchMemory(),   // < 1ms（纯文件读取）
    _fetchDisks(),    // 约 50ms（进程调用）
    _fetchNetworks(), // < 1ms（纯文件读取）
  ]);
  return SystemInfo(...);
}
```

四项采集互不依赖，使用 `Future.wait` 并行发起：

```
串行执行：Cpu(200ms) + Mem(1ms) + Disk(50ms) + Net(1ms) = 252ms
并行执行：max(200ms, 1ms, 50ms, 1ms) = 200ms  （节省约 20%）
```

在 Dart 的单线程模型中，文件 I/O 操作底层委托给操作系统，`Future.wait` 可以同时发起多个 I/O 请求，让内核并行处理。

---

## 7. 错误处理：静默降级

```dart
Future<String> _read(String path) async {
  try {
    return await File(path).readAsString();
  } catch (_) {
    return '';  // 失败返回空字符串，不抛异常
  }
}
```

每个采集方法内部都捕获异常，返回空数据或默认值：

- CPU 读取失败 → `usagePercent = 0`
- 内存读取失败 → 返回零值
- 磁盘 `df` 失败 → 返回空列表
- 网络读取失败 → 返回空列表

这不是"忽略错误"，而是**优雅降级**：一个模块失败不影响其他模块。如果 `/proc/net/dev` 不可读（比如容器环境），用户至少还能看到 CPU/Memory/Disk 的数据。

---

## 延伸练习

1. 修改 `_fetchCpu()` 的采样间隔为 500ms 和 50ms，观察使用率数值的变化
2. 用 `strace -e openat flutter run -d linux` 追踪实际读取了哪些 `/proc` 文件
3. 尝试添加 `/proc/loadavg` 的支持（系统负载），需要修改哪些文件？

---

上一章：[03 数据模型](03-data-models.md)
下一章：[05 状态管理](05-state-management.md) — Provider 模式在真实项目中的实践与陷阱。
