# SysMonitor

Linux 桌面系统监控工具，基于 Flutter 构建。实时展示 CPU、内存、磁盘、网络等关键系统指标，支持系统托盘常驻。

![Platform](https://img.shields.io/badge/platform-Linux-blue)
![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.12+-0175C2?logo=dart)

## 功能

- **CPU 监控** — 实时使用率、核心数、型号信息
- **内存监控** — 已用 / 总量 / 可用，自动单位换算（KB/MB/GB）
- **磁盘监控** — 所有挂载点使用率、已用 / 剩余空间
- **网络监控** — 各网卡接收(RX) / 发送(TX)字节数
- **系统托盘** — 最小化到托盘，悬停显示 CPU/MEM 百分比
- **自动刷新** — 每 3 秒拉取最新数据
- **暗色主题** — Material Design 3 暗色调

## 截图

```
┌──────────────────────────────────┐
│  System Monitor           [─] [↻]│
├──────────────┬───────────────────┤
│  CPU    45%  │  Memory   62%     │
│  ◉ gauge     │  ◉ gauge          │
│  8 cores     │  Used  9.8 GB     │
│  i7-10750H   │  Total 15.6 GB    │
│              │  Free  5.8 GB     │
├──────────────┴───────────────────┤
│  ── Disks ──                     │
│  /         45%  ████████░░░░░░   │
│  /home     78%  ████████████░░   │
├──────────────────────────────────┤
│  ── Network ──                   │
│  eth0    ↓ 1.2 GB    ↑ 340 MB   │
└──────────────────────────────────┘
```

## 快速开始

### 环境要求

- Flutter SDK ≥ 3.x
- Dart SDK ≥ 3.12
- Linux（需 `/proc` 文件系统支持）

### 运行

```bash
cd sys_monitor
flutter pub get
flutter run -d linux
```

### 构建 Release

```bash
flutter build linux --release
```

构建产物：`build/linux/x64/release/bundle/`

### GNOME 用户

GNOME 默认不显示系统托盘。需安装 AppIndicator 扩展：

```bash
# Fedora
sudo dnf install gnome-shell-extension-appindicator

# Ubuntu/Debian
sudo apt install gnome-shell-extension-appindicator
```

安装后 `Alt+F2` → 输入 `r` → 回车重启 GNOME Shell。

## 项目结构

```
lib/
├── main.dart              # 入口，窗口初始化
├── app.dart               # MaterialApp 外壳，托盘/窗口生命周期
├── core/
│   └── theme.dart         # 暗色主题 & 用量颜色映射
├── models/
│   └── system_info.dart   # 数据模型
├── services/
│   └── system_monitor.dart # /proc 数据采集
├── providers/
│   └── dashboard_provider.dart # 状态管理（ChangeNotifier）
├── screens/
│   └── dashboard_screen.dart   # 主仪表盘
└── widgets/
    └── usage_gauge.dart        # 圆形+线性进度组件
```

## 架构

四层架构：UI → State（Provider）→ Service（/proc 采集）→ Model

详细设计文档见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)

## 技术栈

| 依赖 | 用途 |
|------|------|
| `provider` | 状态管理 |
| `window_manager` | 窗口尺寸/关闭行为控制 |
| `tray_manager` | 系统托盘图标与菜单 |

## License

MIT
