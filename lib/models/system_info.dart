/// Data models for system monitoring information.
class CpuInfo {
  final double usagePercent;
  final int cores;
  final String model;

  const CpuInfo({
    required this.usagePercent,
    required this.cores,
    required this.model,
  });
}

class MemoryInfo {
  final int totalKb;
  final int usedKb;
  final int availableKb;
  final double usagePercent;

  const MemoryInfo({
    required this.totalKb,
    required this.usedKb,
    required this.availableKb,
    required this.usagePercent,
  });
}

class DiskInfo {
  final String mountPoint;
  final String total;
  final String used;
  final String available;
  final double usagePercent;

  const DiskInfo({
    required this.mountPoint,
    required this.total,
    required this.used,
    required this.available,
    required this.usagePercent,
  });
}

class NetworkInfo {
  final String interfaceName;
  final int rxBytes;
  final int txBytes;

  const NetworkInfo({
    required this.interfaceName,
    required this.rxBytes,
    required this.txBytes,
  });
}

class SystemInfo {
  final CpuInfo cpu;
  final MemoryInfo memory;
  final List<DiskInfo> disks;
  final List<NetworkInfo> networks;

  const SystemInfo({
    required this.cpu,
    required this.memory,
    required this.disks,
    required this.networks,
  });
}
