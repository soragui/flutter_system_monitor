# 06 · UI 设计 — Widget 树的构建策略与响应式布局

> **回答什么问题**：监控面板的 Widget 树如何组织？CPU/Memory 并排布局怎么实现？UsageGauge 组件如何复用？暗色主题怎么配置？
> **对应代码**：`lib/screens/dashboard_screen.dart` (537 行)，`lib/widgets/usage_gauge.dart` (67 行)，`lib/core/theme.dart` (17 行)

---

## 1. 整体布局结构

```
┌──────────────────────────────────────────┐
│  AppBar: System Monitor          [─] [↻] │
├────────────────┬─────────────────────────┤
│                │                         │
│  CPU Card      │  Memory Card            │  ← Row: 1:1 等宽
│  · usage%      │  · usage%               │     IntrinsicHeight
│  · gauge       │  · gauge                │     保持等高
│  · cores       │  · used / total / free  │
│  · model       │                         │
│                │                         │
├────────────────┴─────────────────────────┤
│  ── Disks ──────────────────────────────│
│  /           45%  ████████░░░░           │  ← Column:
│  /home       78%  ████████████░░         │     全宽卡片列表
│  /boot       23%  ████░░░░░░░░░░         │
├──────────────────────────────────────────┤
│  ── Network ────────────────────────────│
│  eth0    ↓ 1.2 GB    ↑ 340 MB           │  ← Column:
│  wlan0   ↓ 56 MB     ↑ 12 MB            │     全宽卡片列表
└──────────────────────────────────────────┘
```

### 1.1 为什么是 SingleChildScrollView + Column 而不是 ListView？

```dart
// ✅ 本项目方式
SingleChildScrollView(
  child: Column(
    children: [
      Row(children: [Expanded(child: cpu), Expanded(child: mem)]),
      ...disks.map((d) => _diskCard(d)),
      ...networks.map((n) => _networkCard(n)),
    ],
  ),
)
// ❌ 如果用 ListView
ListView(
  children: [
    // Row 无法放在 ListView 中 — ListView 子项只能占一整行
    // 需要用其他方式实现并排布局
  ],
)
```

`ListView` 的每个子项占满整行宽度，无法实现 CPU/Memory 的并排布局。`SingleChildScrollView` + `Column` 提供了完全自由的布局控制。

---

## 2. CPU / Memory 并排布局详解

```dart
IntrinsicHeight(
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(child: _cpuCard(context, info.cpu, theme)),
      const SizedBox(width: 12),     // 间距
      Expanded(child: _memoryCard(context, info.memory, theme)),
    ],
  ),
)
```

### 2.1 三个关键 Widget

| Widget | 作用 |
|--------|------|
| `Expanded` | 使两个卡片均分可用宽度（各占 50%） |
| `crossAxisAlignment: CrossAxisAlignment.stretch` | 让高度较小的卡片拉伸到与较高的卡片一致 |
| `IntrinsicHeight` | 先计算子 Widget 的自然高度，再应用到 Row 上 |

### 2.2 没有 IntrinsicHeight 会怎样？

```
┌──────────────┐
│              │
│  CPU Card    │  ← 正常高度
│  64px gauge  │
│  + cores     │
│  + model     │
│              │
└──────────────┘
┌──────────────┐
│  Memory Card │  ← 矮了一截
│  64px gauge  │
└──────────────┘
```

`IntrinsicHeight` 确保了视觉一致性 — 两个卡片始终等高。

> **性能提醒**：`IntrinsicHeight` 需要两次布局（先测量再应用），在长列表中应谨慎使用。这里只有两个卡片，性能损失可以忽略。

---

## 3. UsageGauge 组件：复用设计

UsageGauge 是项目中复用率最高的组件：

```dart
// cpu_card 中使用
UsageGauge(percent: cpu.usagePercent, size: 64)

// memory_card 中使用
UsageGauge(percent: mem.usagePercent, size: 64)
```

### 3.1 内部结构

```dart
class UsageGauge extends StatelessWidget {
  final double percent;
  final double size;

  Widget build(BuildContext context) {
    return Column(
      children: [
        // 1. 圆形进度指示器 + 百分比文字（Stack 叠加）
        SizedBox(
          width: size, height: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: percent / 100,
                valueColor: AlwaysStoppedAnimation(_color),
              ),
              Center(
                child: Text('${percent.toInt()}%', ...)
              ),
            ],
          ),
        ),
        SizedBox(height: 10),
        // 2. 线性进度条
        _Bar(percent: percent, color: _color, width: size),
      ],
    );
  }
}

// _Bar 是私有辅助类
class _Bar extends StatelessWidget {
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,  // ← 关键：必须给确定宽度！
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(...),
      ),
    );
  }
}
```

### 3.2 踩坑记录：LinearProgressIndicator 的无限宽度错误

如果直接使用 `LinearProgressIndicator` 而不包 `SizedBox`：

```dart
// ❌ 在 Row 的 Expanded 中会报错
Row(children: [
  UsageGauge(percent: 45),
  // LinearProgressIndicator → 从 Row 获得无限宽度 → 抛出异常
])
```

**根因**：`LinearProgressIndicator` 默认尝试填充父容器的全部宽度。在 `Row` 中，子 Widget 获得的是无界宽度约束（`unbounded`），导致 Flutter 抛出 "BoxConstraints forces an infinite width"。

**解决方案**：用 `SizedBox(width: size)` 给 `LinearProgressIndicator` 赋予确定的宽度约束。这个宽度从父组件 `UsageGauge` 传入，与圆形指示器保持一致。

---

## 4. 卡片设计的视觉层次

### 4.1 CPU Card 结构

```dart
Card(
  elevation: 1,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  child: Padding(
    padding: EdgeInsets.all(16),
    child: Column(
      children: [
        // ── 第 1 行：标题 + 百分比 ──
        Row(children: [
          Icon(Icons.memory, color: color),
          Text('CPU', ...),
          Spacer(),
          Text('${cpu.usagePercent.toInt()}%', style: 22pt bold),
        ]),
        SizedBox(height: 12),
        // ── 第 2 行：Gauge + 详细信息 ──
        Row(children: [
          UsageGauge(percent: cpu.usagePercent, size: 64),
          SizedBox(width: 14),
          Expanded(child: Column(children: [
            Text('${cpu.cores} cores', ...),
            Text(cpuModelShort, ...),  // 截断后的型号名称
          ])),
        ]),
      ],
    ),
  ),
)
```

### 4.2 Disk Card 对比 Network Card

| 特性 | Disk Card | Network Card |
|------|-----------|-------------|
| 百分比 | 右上角 20pt 粗体 | 无（累计流量无使用率概念） |
| 进度条 | LinearProgressIndicator | 无 |
| 颜色 | 按使用率变化（绿→红） | 固定图标色 |
| 信息 | used / total + free | ↓ 下载 + ↑ 上传 |

不同类型的数据使用不同的卡片布局，但共享统一的 Card 样式（elevation、圆角、间距），保持视觉一致性。

---

## 5. 暗色主题

### 5.1 极简配置

```dart
class AppTheme {
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF1565C0),  // 蓝色基调
    brightness: Brightness.dark,
  );
}
```

只设置了 3 个属性，但 Material 3 会根据 `colorSchemeSeed` 自动生成完整的调色板：

- `primary`, `onPrimary`：用于 AppBar、按钮
- `surface`, `onSurface`：用于 Card、背景
- `outline`：用于次要文字
- `surfaceContainerHighest`：用于变体背景

所有 Card、Text、Icon 的颜色都从 `Theme.of(context).colorScheme` 获取，确保全局一致。

### 5.2 用法颜色映射

```dart
static Color usageColor(double percent) {
  if (percent < 50) return Colors.green;       // 正常
  if (percent < 75) return Colors.orange;      // 注意
  if (percent < 90) return Colors.deepOrange;  // 警告
  return Colors.red;                           // 危险
}
```

这个函数在 CPU、Memory、Disk 三处使用，确保了颜色语义的一致。阈值设计参考了生产环境的告警分级。

---

## 6. 卡片逻辑的演进：从独立 Widget 到内联方法

### 6.1 两个版本对比

```dart
// v1: 每个卡片是独立的 Widget 文件
// widgets/cpu_card.dart      — class CpuCard extends StatelessWidget
// widgets/memory_card.dart   — class MemoryCard extends StatelessWidget
// widgets/disk_card.dart     — class DiskCard extends StatelessWidget
// widgets/network_card.dart  — class NetworkCard extends StatelessWidget

// v2: 卡片逻辑内联到 DashboardScreen（当前版本）
// screens/dashboard_screen.dart
//   _cpuCard()      — Widget 私有方法
//   _memoryCard()   — Widget 私有方法
//   _diskCard()     — Widget 私有方法
//   _networkCard()  — Widget 私有方法
```

### 6.2 为什么内联？

| 维度 | 独立 Widget 文件 | 内联方法 |
|------|-----------------|---------|
| 文件数量 | 4 个文件 | 1 个文件 |
| 跳转成本 | 跨文件跳转 | 同文件内滚动 |
| 参数传递 | 构造函数传参 | 闭包捕获 |
| 主题/上下文 | `Theme.of(context)` | 闭包捕获 — 更简洁 |
| 复用性 | 理论上可复用 | 不可复用 |

对于一个单页面应用，卡片不会被其他地方使用，拆成独立文件带来的抽象收益小于其认知负担。把所有卡片代码放在同一个文件中，修改一个布局效果时可以立即看到对其他卡片的影响。

> 如果未来需要复用（比如弹出一个独立的 CPU 详情窗口），再提取为 Widget 文件也不迟。别为"可能"的复用提前抽象。

---

## 延伸练习

1. 修改 `AppTheme.usageColor` 的阈值，观察 UI 颜色变化
2. 尝试把 `_cpuCard` 提取回独立的 `CpuCard` Widget 文件，对比两种方式的代码量差异
3. 在 CPU/Memory Row 上方添加一个"系统概览"卡片（显示主机名、运行时长等信息），数据需要从 Service 层新增

---

上一章：[05 状态管理](05-state-management.md)
下一章：[07 桌面集成](07-desktop-integration.md) — 原生窗口控制、系统托盘与生命周期管理。
