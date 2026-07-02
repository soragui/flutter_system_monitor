# 03 · 数据模型 — 不可变数据类的设计哲学

> **回答什么问题**：Model 层的五个数据类如何设计？为什么全部不可变？Dart 的 `const` 构造函数在这里起什么作用？
> **对应代码**：`lib/models/system_info.dart` (69 行)

---

## 1. 五个数据类，一棵树

```dart
SystemInfo
├── CpuInfo
│   ├── usagePercent: double   // 0.0 ~ 100.0
│   ├── cores: int             // 逻辑核心数
│   └── model: String          // 如 "Intel(R) Core(TM) i7-10750H"
├── MemoryInfo
│   ├── totalKb: int           // MemTotal (KB)
│   ├── usedKb: int            // 计算得出：total - available
│   ├── availableKb: int       // MemAvailable (优先) 或估算
│   └── usagePercent: double
├── List<DiskInfo>
│   ├── mountPoint: String     // 如 "/", "/home"
│   ├── total: String          // 如 "256G" (df -h 的人类可读输出)
│   ├── used: String
│   ├── available: String
│   └── usagePercent: double   // 已解析的数字
└── List<NetworkInfo>
    ├── interfaceName: String  // 如 "eth0", "wlan0"
    ├── rxBytes: int           // 累计接收字节数
    └── txBytes: int           // 累计发送字节数
```

---

## 2. 设计原则

### 2.1 全部 `final` — 不可变性

```dart
class CpuInfo {
  final double usagePercent;  // ✅ 不可变
  // double usagePercent;     // ❌ 可变 —— 谁都可以改
  final int cores;
  final String model;

  const CpuInfo({
    required this.usagePercent,
    required this.cores,
    required this.model,
  });
}
```

**为什么不可变？**

在 SysMonitor 的数据流中，数据只在一个地方创建（`SystemMonitor`），在另一个地方消费（`DashboardScreen`）：

```
SystemMonitor.fetchAll() → 创建 SystemInfo
         │
         ▼
DashboardProvider._data = info    ← 持有引用
         │
         ▼
Consumer builder 中读取 info.cpu.usagePercent
```

如果数据是可变的，会出现这类 bug：

```dart
// ❌ 假设 CpuInfo 是可变的
var cpu = info.cpu;
cpu.usagePercent = 99.9;  // 谁改的？为什么改？在哪里改的？
```

不可变性消除了这类问题：**数据一旦创建，就永远保持一致**。

### 2.2 `const` 构造函数 — 编译期常量

```dart
const CpuInfo({
  required this.usagePercent,
  required this.cores,
  required this.model,
});
```

`const` 构造函数有两个好处：

1. **编译期优化**：Dart 编译器可以在编译时分配常量对象，减少运行时内存分配
2. **语义约束**：`const` 强制所有字段必须是 `final`，从语言层面保证不可变性

> `const` 构造函数在本项目中主要用于语义约束。`SystemInfo` 实例在运行时创建（数据来自 `/proc`），实际不会用 `const` 实例化。保留 `const` 是防御性设计：如果未来需要编译期常量，不需要改构造函数。

### 2.3 扁平化 vs 深层嵌套

对比两种设计：

```dart
// ❌ 深层嵌套 v1
class DashboardData {
  CpuSection cpu;
  MemorySection memory;
}
class CpuSection {
  Detail detail;
  Chart chart;
}
class Detail {
  double percent;
  int cores;
}

// ✅ 扁平化 v2（本项目采用）
class SystemInfo {
  CpuInfo cpu;
  MemoryInfo memory;
  List<DiskInfo> disks;
  List<NetworkInfo> networks;
}
class CpuInfo {
  double usagePercent;
  int cores;
  String model;
}
```

本项目刻意保持数据模型扁平：**每个类最多 4 个字段，只有一层嵌套**（`SystemInfo` → 具体类型）。

原因很简单：
- 监控数据本身结构简单，不需要深层抽象
- 扁平结构在 UI 中直接：`info.cpu.usagePercent` vs `info.cpu.detail.metrics.usage.percent`
- 过度嵌套 = 过早抽象，增加理解成本

---

## 3. 数据类型选择

### 3.1 为什么 `usagePercent` 是 `double` 而非 `int`？

```dart
final double usagePercent;   // ✅ 精度到 0.1%
// final int usagePercent;   // ❌ 丢失精度

// 在 SystemMonitor 中：
final pct = double.parse(pct.toStringAsFixed(1));  // 保留一位小数
```

CPU 使用率可能是 3.7%、12.4% 这种非整数值。`double` 保留了一位小数的精度，UI 层通过 `toInt()` 显示整数。

### 3.2 为什么 `MemoryInfo` 用 KB 而非 MB？

```dart
final int totalKb;   // KB 为单位的整数值
final int usedKb;
final int availableKb;
```

因为 `/proc/meminfo` 以 KB 为单位输出，这是 Linux 内核的标准格式：

```
MemTotal:       16332336 kB
MemFree:          598728 kB
```

直接用 KB 存储避免了数据转换中的精度损失。需要人类可读格式时，调用 `SystemMonitor.formatKb()` 转换即可。

### 3.3 为什么 `DiskInfo` 的容量用 `String` 而非 `int`？

```dart
final String total;      // "256G" — 来自 df -h 的输出
final double usagePercent;  // 45.0 — 解析后的数字
```

这是实用性优先的选择。`df -h` 的 `-h` 参数直接输出人类可读的容量字符串。如果存为字节数，还需要写格式化逻辑。保留了原始字符串方便直接显示，同时解析出 `usagePercent` 供颜色映射和进度条使用。

---

## 4. 模型层的测试友好性

因为 Model 层是纯数据、无副作用，它是最容易测试的一层：

```dart
// ✅ 测试零依赖，不需要 mock
test('CpuInfo 构造正确', () {
  final cpu = CpuInfo(
    usagePercent: 45.5,
    cores: 8,
    model: 'Test CPU',
  );
  expect(cpu.usagePercent, 45.5);
  expect(cpu.cores, 8);
});

test('MemoryInfo usagePercent 计算一致', () {
  final mem = MemoryInfo(
    totalKb: 1000,
    usedKb: 300,
    availableKb: 700,
    usagePercent: 30.0,
  );
  expect(mem.usagePercent, 30.0);
});
```

不需要 mock 文件系统，不需要启动 Flutter 引擎，纯粹的单元测试。

---

## 5. 一个改进思考

当前设计中，`DiskInfo` 混合了两种类型的数据：

- `total`/`used`/`available` 是 String（人类可读）
- `usagePercent` 是 double（机器计算）

更纯粹的设计可能是：

```dart
class DiskInfo {
  final int totalBytes;    // 原始字节数
  final int usedBytes;
  final int availableBytes;

  // 计算属性：延迟计算
  double get usagePercent => totalBytes > 0
    ? (usedBytes / totalBytes * 100)
    : 0;
}
```

这样所有字段都是原始数据类型，格式化逻辑放在 UI 层。但这也意味着需要自己解析 `df` 的非 `-h` 输出，增加了 Service 层的复杂度。

**当前的设计取舍**：牺牲了一点类型纯度，换取了 Service 层的简洁（直接使用 `df -h` 的输出）。

---

## 延伸练习

1. 给 `SystemInfo` 添加一个 GPU 温度字段（`double gpuTemp`），画出需要修改的所有文件
2. 尝试将 `DiskInfo.total` 改为 `int`（字节数），修改 Service 层和 UI 层以适应这个变化
3. 阅读 Dart 文档中关于 `const` constructor 的章节，理解什么情况下真正的编译期常量会被创建

---

上一章：[02 架构全景](02-architecture-overview.md)
下一章：[04 数据采集](04-data-collection.md) — 深入 Service 层，理解 /proc 文件系统与并发 I/O。
