# 07 · 桌面集成 — 原生窗口管理与系统托盘

> **回答什么问题**：Flutter 桌面应用如何控制原生窗口？怎么实现"关闭按钮最小化到托盘"？系统托盘图标和菜单怎么做？应用的完整生命周期是怎样的？
> **对应代码**：`lib/main.dart` (17 行)，`lib/app.dart` (117 行)

---

## 1. 两个桌面集成插件

```yaml
window_manager: ^0.5.1   # 原生窗口控制
tray_manager: ^0.5.3     # 系统托盘
```

这两个插件通过 Flutter 的 **Platform Channel** 机制与 Linux 原生窗口系统（X11/Wayland）通信。它们在 Dart 侧提供跨平台 API，在底层调用平台特定的窗口管理接口。

---

## 2. 窗口初始化流程

```dart
// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();  // ① Flutter 引擎初始化
  await windowManager.ensureInitialized();    // ② 窗口管理器初始化

  // ③ 窗口配置
  await windowManager.setPreventClose(true);  // 关闭按钮 → 触发回调（而非退出）
  await windowManager.setTitle('System Monitor');
  await windowManager.setSize(const Size(420, 620));
  await windowManager.center();
  await windowManager.show();

  runApp(const SysMonitorShell());            // ④ 启动 Flutter UI
}
```

### 2.1 初始化顺序必须严格

```
WidgetsFlutterBinding  ← 必须先初始化，否则后续 platform channel 无法工作
        │
windowManager          ← 依赖 Flutter binding
        │
窗口属性设置             ← 依赖 windowManager
        │
runApp()               ← 最后启动 UI
```

### 2.2 窗口尺寸：420 × 620

这个尺寸是通过反复调整确定的：

- **420px 宽**：刚好装下 CPU/Memory 两个并排卡片 + 左右间距（16px × 2 = 32px，两个卡片各约 190px）
- **620px 高**：CPU/Memory 行 + 磁盘区（一般 2~3 个挂载点）+ 网络区 + 底部留白，刚好不出现滚动条

> 使用 `setSize` 而非 `setMinimumSize`，不强制固定大小。用户可以手动调整窗口尺寸。

---

## 3. "关闭即最小化"模式

```dart
// main.dart
await windowManager.setPreventClose(true);

// app.dart — WindowListener mixin
@override
void onWindowClose() => windowManager.hide();
```

这是桌面常驻应用的标准模式：

```
用户点击窗口关闭按钮 [X]
        │
setPreventClose(true) 拦截关闭事件
        │
调用 onWindowClose() 回调
        │
windowManager.hide()   ← 隐藏窗口（不退出应用）
        │
窗口消失，但程序仍在运行，托盘图标还在
```

**为什么这样做？**

系统监控工具的价值在于"常驻"。关闭按钮直接退出的话，用户需要反复手动启动。最小化到托盘让应用持续监控而不占任务栏空间。

---

## 4. 系统托盘集成

### 4.1 初始化

```dart
Future<void> _initTray() async {
  await trayManager.setIcon('assets/tray_icon.png');
  await trayManager.setContextMenu(Menu(items: [
    MenuItem(key: 'dashboard', label: 'Dashboard'),
    MenuItem.separator(),                    // 分隔线
    MenuItem(key: 'exit', label: 'Exit'),
  ]));
}
```

托盘菜单只有两个选项：
- **Dashboard**：显示监控窗口
- **Exit**：彻底退出应用

### 4.2 托盘标题：实时显示 CPU/MEM

```dart
// 鼠标悬停托盘图标时显示
trayManager.setTitle('CPU45% MEM62%');
```

这个功能让用户不需要打开主窗口就能快速了解系统状态。

### 4.3 托盘事件处理

```dart
// TrayListener mixin
@override
void onTrayIconMouseDown() => _showDashboard();  // 单击托盘图标

@override
void onTrayMenuItemClick(MenuItem item) {
  switch (item.key) {
    case 'dashboard':
      _showDashboard();   // 右键菜单 → Dashboard
    case 'exit':
      trayManager.destroy();
      exit(0);            // 右键菜单 → 退出
  }
}

Future<void> _showDashboard() async {
  await windowManager.show();
  await windowManager.focus();
  _provider.refresh();    // 窗口恢复时立即刷新数据
}
```

**关键细节**：`_showDashboard()` 在窗口恢复时调用 `_provider.refresh()`。因为窗口隐藏期间定时器仍在运行，数据已经是最新的，但调用一次 `refresh()` 确保用户看到的是最新数据（避免"定时器的本次轮询还有 2 秒才触发"的情况）。

---

## 5. 托盘标题更新的优化

```dart
void _onProviderChanged() {
  final title = _provider.trayTitle;          // "CPU45% MEM62%"
  if (title == _lastTrayTitle || _trayTitlePending) return;

  _trayTitlePending = true;
  SchedulerBinding.instance.addPostFrameCallback((_) {
    _trayTitlePending = false;
    _lastTrayTitle = title;
    trayManager.setTitle(title);
  });
}
```

### 5.1 为什么要用 addPostFrameCallback？

`_onProviderChanged` 在 `notifyListeners()` 时触发，此时可能处于 Widget 的 build 阶段。`trayManager.setTitle()` 是一个 Platform Channel 调用（异步、可能失败），在 build 阶段执行可能导致问题：

```
notifyListeners()
  → build() 执行中
    → _onProviderChanged() 被调用
      → trayManager.setTitle()  ← 在 build 期间调用原生方法
        → 可能触发 setState() → Flutter 抛出异常
```

`addPostFrameCallback` 将托盘标题设置推迟到帧渲染结束后（类似 React 的 `useEffect`）。

### 5.2 去重和防并发

```dart
if (title == _lastTrayTitle) return;  // 标题没变化，跳过
if (_trayTitlePending) return;        // 已经有一个待执行的更新，跳过
```

这两个检查避免了不必要的 Platform Channel 调用。在 3 秒刷新周期中，CPU/MEM 可能连续几次都是同样的百分比，不需要每次都调用原生 API。

---

## 6. 应用完整生命周期

```
启动
  │
  ├─ main()
  │   ├─ WidgetsFlutterBinding.ensureInitialized()
  │   ├─ windowManager 初始化 + 窗口配置
  │   └─ runApp(SysMonitorShell)
  │
  ├─ SysMonitorShell.initState()
  │   ├─ DashboardProvider() 创建
  │   ├─ _provider.start()  → 首次拉取 + 启动 Timer
  │   ├─ _initTray()  → 托盘图标 + 菜单
  │   └─ addListener (window + tray)
  │
  ├─ 运行中
  │   ├─ Timer 每 3 秒 → _refresh() → notifyListeners()
  │   ├─ 数据变化 → Consumer rebuild → 更新 UI
  │   └─ _onProviderChanged → 更新托盘标题
  │
  ├─ 用户关闭窗口
  │   └─ onWindowClose() → windowManager.hide()
  │
  ├─ 用户单击托盘
  │   └─ onTrayIconMouseDown() → windowManager.show() + refresh()
  │
  ├─ 用户右键托盘 → "Exit"
  │   └─ onTrayMenuItemClick('exit')
  │       ├─ trayManager.destroy()
  │       └─ exit(0)
  │
  └─ SysMonitorShell.dispose()
      ├─ _timer.cancel()
      ├─ trayManager.removeListener()
      ├─ windowManager.removeListener()
      └─ _provider.dispose()
```

---

## 7. GNOME 兼容性

GNOME 桌面环境默认不显示系统托盘图标。需要在系统中安装 AppIndicator 扩展：

```bash
# Fedora
sudo dnf install gnome-shell-extension-appindicator

# Ubuntu/Debian
sudo apt install gnome-shell-extension-appindicator

# 重启 GNOME Shell
# Alt+F2 → 输入 r → Enter
```

这是 GNOME 的设计选择（偏好简洁），不是 Flutter 或 `tray_manager` 的问题。KDE、XFCE、Cinnamon 等桌面环境都原生支持系统托盘。

---

## 延伸练习

1. 在 `onWindowClose` 中添加一个弹出确认框（"最小化到托盘 / 退出应用"），研究 `showDialog` 在桌面环境的表现
2. 尝试修改窗口默认位置为"屏幕右下角"，观察 `Alignment.bottomRight` 的行为
3. 添加开机自启功能（Linux 的 `.desktop` 文件 + `~/.config/autostart/`）

---

上一章：[06 UI 设计](06-ui-design.md)
下一章：[08 设计决策](08-design-decisions.md) — 回顾全局，总结架构决策与设计原则。
