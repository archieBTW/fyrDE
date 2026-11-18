enum ContainerRuntime {
  podman(
    label: 'Podman 5.3 (rootless)',
    shortLabel: 'Podman 5.3 • rootless',
    binary: 'podman',
    isRootless: true,
    socketPath: 'unix:///run/user/1000/podman/podman.sock',
  ),
  docker(
    label: 'Docker 27.4',
    shortLabel: 'Docker 27.4 • rootful',
    binary: 'docker',
    isRootless: false,
    socketPath: 'unix:///var/run/docker.sock',
  );

  final String label;
  final String shortLabel;
  final String binary;
  final bool isRootless;
  final String socketPath;

  const ContainerRuntime({
    required this.label,
    required this.shortLabel,
    required this.binary,
    required this.isRootless,
    required this.socketPath,
  });
}

enum ContainerStateStatus {
  running('Running'),
  paused('Paused'),
  exited('Exited'),
  created('Created'),
  restarting('Restarting');

  final String label;
  const ContainerStateStatus(this.label);

  bool get isRunning => this == ContainerStateStatus.running;
  bool get isStopped =>
      this == ContainerStateStatus.exited ||
      this == ContainerStateStatus.created;
}

enum PodsNavSection {
  dashboard('Dashboard'),
  containers('Containers'),
  pods('Pods & Stacks'),
  images('Images'),
  volumes('Volumes'),
  networks('Networks');

  final String label;
  const PodsNavSection(this.label);
}

enum ContainerFilter {
  all('All'),
  running('Running'),
  paused('Paused'),
  stopped('Stopped');

  final String label;
  const ContainerFilter(this.label);
}

enum InspectorTab {
  summary('Summary & Metrics'),
  logs('Logs'),
  terminal('Terminal (Exec)'),
  kubeYaml('Kube YAML / Inspect');

  final String label;
  const InspectorTab(this.label);
}

class PortMapping {
  final String hostIp;
  final int hostPort;
  final int containerPort;
  final String protocol;

  const PortMapping({
    this.hostIp = '0.0.0.0',
    required this.hostPort,
    required this.containerPort,
    this.protocol = 'tcp',
  });

  String get formatted => '$hostIp:$hostPort->$containerPort/$protocol';
  String get shortFormatted => '$hostPort:$containerPort';

  Map<String, dynamic> toJson() => {
        'host_ip': hostIp,
        'host_port': hostPort,
        'container_port': containerPort,
        'protocol': protocol,
      };
}

class VolumeMount {
  final String source;
  final String destination;
  final String mode;

  const VolumeMount({
    required this.source,
    required this.destination,
    this.mode = 'rw',
  });

  String get formatted => '$source:$destination:$mode';

  Map<String, dynamic> toJson() => {
        'source': source,
        'destination': destination,
        'mode': mode,
      };
}

class ContainerMetricSample {
  final DateTime timestamp;
  final double cpuPercent;
  final double memUsageMb;
  final double memLimitMb;
  final double netRxMbps;
  final double netTxMbps;

  const ContainerMetricSample({
    required this.timestamp,
    required this.cpuPercent,
    required this.memUsageMb,
    required this.memLimitMb,
    this.netRxMbps = 0.0,
    this.netTxMbps = 0.0,
  });
}

class ContainerInfo {
  final String id;
  final String name;
  final String image;
  final String? podId;
  final String? podName;
  ContainerStateStatus state;
  String statusText;
  final DateTime created;
  final List<PortMapping> ports;
  final List<VolumeMount> mounts;
  final Map<String, String> env;
  final String command;
  double cpuPercent;
  double memUsageMb;
  double memLimitMb;
  double netRxMb;
  double netTxMb;
  final List<double> cpuHistory;
  final List<double> memHistory;
  final List<String> logs;

  ContainerInfo({
    required this.id,
    required this.name,
    required this.image,
    this.podId,
    this.podName,
    required this.state,
    required this.statusText,
    required this.created,
    List<PortMapping>? ports,
    List<VolumeMount>? mounts,
    Map<String, String>? env,
    this.command = '/entrypoint.sh',
    this.cpuPercent = 0.0,
    this.memUsageMb = 0.0,
    this.memLimitMb = 512.0,
    this.netRxMb = 0.0,
    this.netTxMb = 0.0,
    List<double>? cpuHistory,
    List<double>? memHistory,
    List<String>? logs,
  })  : ports = ports ?? [],
        mounts = mounts ?? [],
        env = env ?? {},
        cpuHistory = cpuHistory ?? List<double>.filled(24, cpuPercent, growable: true),
        memHistory = memHistory ?? List<double>.filled(24, memUsageMb, growable: true),
        logs = logs ?? [];

  String get shortId => id.length > 12 ? id.substring(0, 12) : id;

  double get memPercent =>
      memLimitMb > 0 ? ((memUsageMb / memLimitMb) * 100.0).clamp(0.0, 100.0) : 0.0;
}

class PodGroupInfo {
  final String id;
  final String name;
  String status; // 'Running', 'Degraded', 'Stopped'
  final String infraId;
  final List<String> containerIds;
  final List<PortMapping> sharedPorts;
  final DateTime created;
  String kubeYaml;

  PodGroupInfo({
    required this.id,
    required this.name,
    required this.status,
    required this.infraId,
    required this.containerIds,
    required this.sharedPorts,
    required this.created,
    this.kubeYaml = '',
  });

  String get shortId => id.length > 12 ? id.substring(0, 12) : id;
}

class ContainerImageInfo {
  final String id;
  final String repository;
  final String tag;
  final double sizeMb;
  final DateTime created;
  bool inUse;
  final int layersCount;

  ContainerImageInfo({
    required this.id,
    required this.repository,
    required this.tag,
    required this.sizeMb,
    required this.created,
    this.inUse = false,
    this.layersCount = 5,
  });

  String get fullTag => '$repository:$tag';
  String get shortId => id.replaceFirst('sha256:', '').substring(
      0,
      id.replaceFirst('sha256:', '').length > 12
          ? 12
          : id.replaceFirst('sha256:', '').length);
}

class VolumeInfo {
  final String name;
  final String driver;
  final String mountpoint;
  final double sizeMb;
  final DateTime createdAt;
  final List<String> attachedContainers;

  VolumeInfo({
    required this.name,
    this.driver = 'local',
    required this.mountpoint,
    required this.sizeMb,
    required this.createdAt,
    List<String>? attachedContainers,
  }) : attachedContainers = attachedContainers ?? [];
}

class ContainerNetworkInfo {
  final String id;
  final String name;
  final String driver;
  final String subnet;
  final String gateway;
  final bool dnsEnabled;
  final bool internal;
  final List<String> connectedContainers;

  ContainerNetworkInfo({
    required this.id,
    required this.name,
    this.driver = 'bridge',
    required this.subnet,
    required this.gateway,
    this.dnsEnabled = true,
    this.internal = false,
    List<String>? connectedContainers,
  }) : connectedContainers = connectedContainers ?? [];
}
