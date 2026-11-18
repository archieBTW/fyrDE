import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/pod_models.dart';
import '../services/container_engine.dart';

class PodsController extends ChangeNotifier {
  final ContainerEngine engine;
  final bool enableTicker;
  Timer? _metricsTimer;
  final math.Random _rng = math.Random(42);

  ContainerRuntime activeRuntime = ContainerRuntime.podman;
  PodsNavSection activeSection = PodsNavSection.containers;
  ContainerFilter statusFilter = ContainerFilter.all;
  InspectorTab activeInspectorTab = InspectorTab.summary;

  String searchQuery = '';
  String logSearchQuery = '';
  String logLevelFilter = 'ALL'; // ALL, INFO, WARN, ERROR
  String? selectedContainerId;
  String? statusMessage;

  final List<ContainerInfo> containers = [];
  final List<PodGroupInfo> pods = [];
  final List<ContainerImageInfo> images = [];
  final List<VolumeInfo> volumes = [];
  final List<ContainerNetworkInfo> networks = [];
  final Map<String, List<String>> terminalTranscripts = {};

  PodsController({
    bool allowLiveCli = false,
    this.enableTicker = false,
  }) : engine = ContainerEngine(allowLiveCli: allowLiveCli) {
    _seedInitialState();
    selectedContainerId = 'c-llm-runner';
    if (enableTicker) {
      startMetricsTicker();
    }
  }

  void _seedInitialState() {
    final now = DateTime.now();

    pods.addAll([
      PodGroupInfo(
        id: 'pod-fyr-cloud-stack-8a91b2c3d4e5',
        name: 'fyr-cloud-stack',
        status: 'Running',
        infraId: 'infra-8a91b2c3d4e5',
        containerIds: ['c-gateway-nginx', 'c-postgres-db', 'c-redis-cache'],
        sharedPorts: const [
          PortMapping(hostIp: '0.0.0.0', hostPort: 8080, containerPort: 80),
          PortMapping(hostIp: '127.0.0.1', hostPort: 5432, containerPort: 5432),
          PortMapping(hostIp: '127.0.0.1', hostPort: 6379, containerPort: 6379),
        ],
        created: now.subtract(const Duration(hours: 6)),
      ),
      PodGroupInfo(
        id: 'pod-fyr-ai-inference-3f42e1a9b8c7',
        name: 'fyr-ai-inference',
        status: 'Running',
        infraId: 'infra-3f42e1a9b8c7',
        containerIds: ['c-llm-runner', 'c-webui-chat'],
        sharedPorts: const [
          PortMapping(
              hostIp: '127.0.0.1', hostPort: 11434, containerPort: 11434),
          PortMapping(hostIp: '0.0.0.0', hostPort: 3000, containerPort: 8080),
        ],
        created: now.subtract(const Duration(hours: 4)),
      ),
      PodGroupInfo(
        id: 'pod-fyr-telemetry-7c12d9e4f5a6',
        name: 'fyr-telemetry',
        status: 'Degraded',
        infraId: 'infra-7c12d9e4f5a6',
        containerIds: ['c-prometheus', 'c-legacy-worker'],
        sharedPorts: const [
          PortMapping(hostIp: '0.0.0.0', hostPort: 9090, containerPort: 9090),
          PortMapping(hostIp: '0.0.0.0', hostPort: 3001, containerPort: 3000),
        ],
        created: now.subtract(const Duration(days: 1, hours: 2)),
      ),
    ]);

    containers.addAll([
      ContainerInfo(
        id: 'c-gateway-nginx',
        name: 'fyr-gateway-nginx',
        image: 'ghcr.io/fyrde/gateway:1.27-alpine',
        podId: 'pod-fyr-cloud-stack-8a91b2c3d4e5',
        podName: 'fyr-cloud-stack',
        state: ContainerStateStatus.running,
        statusText: 'Up 6 hours (healthy)',
        created: now.subtract(const Duration(hours: 6)),
        ports: const [
          PortMapping(
              hostIp: '0.0.0.0',
              hostPort: 8080,
              containerPort: 80,
              protocol: 'tcp'),
        ],
        mounts: const [
          VolumeMount(
              source: '/etc/fyr/nginx.conf',
              destination: '/etc/nginx/nginx.conf',
              mode: 'ro'),
        ],
        env: const {
          'NGINX_WORKER_PROCESSES': 'auto',
          'UPSTREAM_API': 'http://127.0.0.1:3000',
          'FYR_TLS_MODE': 'strict',
        },
        command: 'nginx -g "daemon off;"',
        cpuPercent: 4.2,
        memUsageMb: 64.0,
        memLimitMb: 512.0,
        netRxMb: 412.8,
        netTxMb: 389.4,
        cpuHistory: [
          3.1, 3.4, 4.0, 3.8, 4.5, 5.1, 4.2, 3.9, 4.1, 4.8, 4.3, 4.0,
          3.7, 4.4, 4.9, 4.1, 3.8, 4.2, 4.6, 4.0, 4.3, 4.1, 4.4, 4.2,
        ],
        memHistory: [
          58, 59, 60, 60, 61, 61, 62, 62, 62, 63, 63, 63,
          63, 64, 64, 64, 63, 64, 64, 64, 64, 64, 64, 64,
        ],
        logs: [
          '2026-11-18T03:10:01Z [INFO] nginx/1.27.2 worker processes started (epoll)',
          '2026-11-18T03:14:22Z [INFO] 10.88.0.1 - "GET /api/v1/health HTTP/1.1" 200 48 "-" "fyr-monitor/1.0"',
          '2026-11-18T03:28:09Z [INFO] upstream pool cloud-stack verified (latency: 0.8ms)',
          '2026-11-18T03:45:11Z [WARN] rate-limiter burst threshold approached on /v1/completions',
          '2026-11-18T04:01:00Z [INFO] TLS session ticket key rotated cleanly',
        ],
      ),
      ContainerInfo(
        id: 'c-postgres-db',
        name: 'fyr-postgres-db',
        image: 'postgres:17-alpine',
        podId: 'pod-fyr-cloud-stack-8a91b2c3d4e5',
        podName: 'fyr-cloud-stack',
        state: ContainerStateStatus.running,
        statusText: 'Up 6 hours (healthy)',
        created: now.subtract(const Duration(hours: 6)),
        ports: const [
          PortMapping(
              hostIp: '127.0.0.1',
              hostPort: 5432,
              containerPort: 5432,
              protocol: 'tcp'),
        ],
        mounts: const [
          VolumeMount(
              source: 'fyr-pgdata-v17',
              destination: '/var/lib/postgresql/data',
              mode: 'rw'),
        ],
        env: const {
          'POSTGRES_DB': 'fyrcloud',
          'POSTGRES_USER': 'fyr_admin',
          'PGDATA': '/var/lib/postgresql/data/pgdata',
        },
        command: 'docker-entrypoint.sh postgres',
        cpuPercent: 11.8,
        memUsageMb: 384.0,
        memLimitMb: 2048.0,
        netRxMb: 198.2,
        netTxMb: 245.7,
        cpuHistory: [
          8.2, 9.5, 11.0, 14.2, 12.6, 10.4, 9.8, 11.2, 13.5, 12.1, 10.9, 11.4,
          12.8, 15.0, 13.2, 11.0, 10.5, 11.9, 12.4, 11.6, 10.8, 12.2, 11.5, 11.8,
        ],
        memHistory: [
          340, 345, 350, 356, 360, 362, 365, 368, 370, 372, 374, 375,
          376, 378, 380, 380, 381, 382, 382, 383, 383, 384, 384, 384,
        ],
        logs: [
          '2026-11-18T03:00:04Z [INFO] PostgreSQL 17.1 on x86_64-pc-linux-musl, compiled by gcc 13.2.1',
          '2026-11-18T03:00:05Z [INFO] listening on IPv4 address "0.0.0.0", port 5432',
          '2026-11-18T03:00:06Z [INFO] database system is ready to accept connections',
          '2026-11-18T03:30:00Z [INFO] checkpoint starting: time',
          '2026-11-18T03:30:02Z [INFO] checkpoint complete: wrote 142 buffers (0.9%); 0 WAL file(s) added',
        ],
      ),
      ContainerInfo(
        id: 'c-redis-cache',
        name: 'fyr-redis-cache',
        image: 'redis:7.4-alpine',
        podId: 'pod-fyr-cloud-stack-8a91b2c3d4e5',
        podName: 'fyr-cloud-stack',
        state: ContainerStateStatus.running,
        statusText: 'Up 6 hours (healthy)',
        created: now.subtract(const Duration(hours: 6)),
        ports: const [
          PortMapping(
              hostIp: '127.0.0.1',
              hostPort: 6379,
              containerPort: 6379,
              protocol: 'tcp'),
        ],
        mounts: const [
          VolumeMount(
              source: 'fyr-redis-aof', destination: '/data', mode: 'rw'),
        ],
        env: const {
          'REDIS_AOF_ENABLED': 'yes',
          'REDIS_MAXMEMORY': '256mb',
        },
        command: 'redis-server --appendonly yes',
        cpuPercent: 1.4,
        memUsageMb: 42.0,
        memLimitMb: 512.0,
        netRxMb: 84.1,
        netTxMb: 91.5,
        cpuHistory: [
          1.1, 1.3, 1.2, 1.5, 1.4, 1.6, 1.3, 1.2, 1.4, 1.5, 1.3, 1.4,
          1.2, 1.3, 1.5, 1.4, 1.3, 1.2, 1.4, 1.5, 1.3, 1.4, 1.3, 1.4,
        ],
        memHistory: List<double>.filled(24, 42.0, growable: true),
        logs: [
          '2026-11-18T03:00:02Z [INFO] Redis 7.4.1 (00000000/0) 64 bit, standalone mode',
          '2026-11-18T03:00:03Z [INFO] Ready to accept connections tcp on port 6379',
          '2026-11-18T03:40:12Z [INFO] DB saved on disk (AOF rewrite succeeded)',
        ],
      ),
      ContainerInfo(
        id: 'c-llm-runner',
        name: 'fyr-llm-runner',
        image: 'ollama/ollama:latest',
        podId: 'pod-fyr-ai-inference-3f42e1a9b8c7',
        podName: 'fyr-ai-inference',
        state: ContainerStateStatus.running,
        statusText: 'Up 4 hours (healthy)',
        created: now.subtract(const Duration(hours: 4)),
        ports: const [
          PortMapping(
              hostIp: '127.0.0.1',
              hostPort: 11434,
              containerPort: 11434,
              protocol: 'tcp'),
        ],
        mounts: const [
          VolumeMount(
              source: 'fyr-ollama-models',
              destination: '/root/.ollama',
              mode: 'rw'),
        ],
        env: const {
          'OLLAMA_HOST': '0.0.0.0:11434',
          'OLLAMA_NUM_PARALLEL': '4',
          'OLLAMA_FLASH_ATTENTION': '1',
        },
        command: '/bin/ollama serve',
        cpuPercent: 48.6,
        memUsageMb: 6420.0,
        memLimitMb: 16384.0,
        netRxMb: 1240.5,
        netTxMb: 682.0,
        cpuHistory: [
          22.0, 28.4, 35.0, 42.1, 54.0, 61.2, 58.4, 49.0, 44.2, 39.8, 45.6, 52.3,
          64.0, 59.5, 51.2, 46.8, 43.0, 47.5, 53.1, 50.4, 46.2, 49.8, 47.9, 48.6,
        ],
        memHistory: [
          4800, 5120, 5400, 5890, 6100, 6240, 6300, 6320, 6350, 6360, 6380, 6390,
          6400, 6410, 6410, 6415, 6415, 6418, 6420, 6420, 6420, 6420, 6420, 6420,
        ],
        logs: [
          '2026-11-18T03:05:10Z [INFO] Listening on [::]:11434 (version 0.5.4)',
          '2026-11-18T03:05:12Z [INFO] Dynamically detected Vulkan / ROCm compute device: gfx1100 (24560 MiB)',
          '2026-11-18T03:18:44Z [INFO] llama_model_loader: loaded meta data with 34 key-value pairs and 291 tensors (qwen2.5-coder:14b)',
          '2026-11-18T03:49:02Z [WARN] KV cache context shift triggered at 16384 tokens (flash_attn=true)',
          '2026-11-18T04:02:19Z [INFO] POST /api/chat 200 184.2ms (86.4 tok/s)',
        ],
      ),
      ContainerInfo(
        id: 'c-webui-chat',
        name: 'fyr-webui-chat',
        image: 'ghcr.io/open-webui/open-webui:main',
        podId: 'pod-fyr-ai-inference-3f42e1a9b8c7',
        podName: 'fyr-ai-inference',
        state: ContainerStateStatus.running,
        statusText: 'Up 4 hours (healthy)',
        created: now.subtract(const Duration(hours: 4)),
        ports: const [
          PortMapping(
              hostIp: '0.0.0.0',
              hostPort: 3000,
              containerPort: 8080,
              protocol: 'tcp'),
        ],
        mounts: const [
          VolumeMount(
              source: '/var/lib/fyr/webui-data',
              destination: '/app/backend/data',
              mode: 'rw'),
        ],
        env: const {
          'OLLAMA_BASE_URL': 'http://127.0.0.1:11434',
          'WEBUI_AUTH': 'true',
        },
        command: 'uvicorn open_webui.main:app --host 0.0.0.0 --port 8080',
        cpuPercent: 6.5,
        memUsageMb: 512.0,
        memLimitMb: 2048.0,
        netRxMb: 312.4,
        netTxMb: 518.9,
        cpuHistory: [
          5.2, 5.8, 6.1, 7.0, 6.4, 5.9, 6.2, 6.8, 7.4, 6.9, 6.3, 6.0,
          6.5, 7.1, 6.8, 6.2, 5.9, 6.4, 6.7, 6.3, 6.6, 6.4, 6.7, 6.5,
        ],
        memHistory: List<double>.filled(24, 512.0, growable: true),
        logs: [
          '2026-11-18T03:06:00Z [INFO] Started server process [1] on http://0.0.0.0:8080',
          '2026-11-18T03:06:02Z [INFO] Connected to local Ollama backend (http://127.0.0.1:11434)',
          '2026-11-18T03:55:14Z [INFO] 127.0.0.1:52418 - "GET /api/models HTTP/1.1" 200 OK',
        ],
      ),
      ContainerInfo(
        id: 'c-prometheus',
        name: 'fyr-prometheus',
        image: 'prom/prometheus:v3.0.0',
        podId: 'pod-fyr-telemetry-7c12d9e4f5a6',
        podName: 'fyr-telemetry',
        state: ContainerStateStatus.paused,
        statusText: 'Paused (25m ago)',
        created: now.subtract(const Duration(days: 1)),
        ports: const [
          PortMapping(
              hostIp: '0.0.0.0',
              hostPort: 9090,
              containerPort: 9090,
              protocol: 'tcp'),
        ],
        mounts: const [
          VolumeMount(
              source: 'fyr-prometheus-tsdb',
              destination: '/prometheus',
              mode: 'rw'),
        ],
        env: const {
          'PROMETHEUS_RETENTION': '15d',
        },
        command: '/bin/prometheus --config.file=/etc/prometheus/prometheus.yml',
        cpuPercent: 0.0,
        memUsageMb: 196.0,
        memLimitMb: 1024.0,
        netRxMb: 94.0,
        netTxMb: 42.1,
        cpuHistory: List<double>.filled(24, 0.0, growable: true),
        memHistory: List<double>.filled(24, 196.0, growable: true),
        logs: [
          '2026-11-18T02:00:00Z [INFO] TSDB started, head block loaded cleanly',
          '2026-11-18T03:35:00Z [WARN] Container cgroup frozen via Podman pause signal',
        ],
      ),
      ContainerInfo(
        id: 'c-legacy-worker',
        name: 'fyr-legacy-worker',
        image: 'alpine:3.20',
        podId: 'pod-fyr-telemetry-7c12d9e4f5a6',
        podName: 'fyr-telemetry',
        state: ContainerStateStatus.exited,
        statusText: 'Exited (0) 2 hours ago',
        created: now.subtract(const Duration(days: 1, hours: 2)),
        ports: const [],
        mounts: const [],
        env: const {
          'BATCH_MODE': 'once',
        },
        command: '/bin/sh -c "/usr/local/bin/sync-metrics.sh"',
        cpuPercent: 0.0,
        memUsageMb: 0.0,
        memLimitMb: 256.0,
        netRxMb: 12.4,
        netTxMb: 8.1,
        cpuHistory: List<double>.filled(24, 0.0, growable: true),
        memHistory: List<double>.filled(24, 0.0, growable: true),
        logs: [
          '2026-11-18T01:58:10Z [INFO] Starting batch telemetry compaction job...',
          '2026-11-18T01:59:42Z [ERROR] Remote sink 10.88.0.250:4317 connection refused (retrying with local spool)',
          '2026-11-18T02:00:01Z [INFO] Spool flushed (4,120 records). Exiting with code 0.',
        ],
      ),
    ]);

    for (final p in pods) {
      final members =
          containers.where((c) => p.containerIds.contains(c.id)).toList();
      p.kubeYaml = ContainerEngine.generatePodKubeYaml(p, members);
    }

    images.addAll([
      ContainerImageInfo(
        id: 'sha256:9f8b7a6c5d4e3f2a1b0c9d8e7f6a5b4c',
        repository: 'ollama/ollama',
        tag: 'latest',
        sizeMb: 3420.0,
        created: now.subtract(const Duration(days: 4)),
        inUse: true,
        layersCount: 14,
      ),
      ContainerImageInfo(
        id: 'sha256:2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f',
        repository: 'ghcr.io/open-webui/open-webui',
        tag: 'main',
        sizeMb: 1180.0,
        created: now.subtract(const Duration(days: 5)),
        inUse: true,
        layersCount: 18,
      ),
      ContainerImageInfo(
        id: 'sha256:7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d',
        repository: 'prom/prometheus',
        tag: 'v3.0.0',
        sizeMb: 264.5,
        created: now.subtract(const Duration(days: 9)),
        inUse: true,
        layersCount: 9,
      ),
      ContainerImageInfo(
        id: 'sha256:4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a',
        repository: 'postgres',
        tag: '17-alpine',
        sizeMb: 248.0,
        created: now.subtract(const Duration(days: 12)),
        inUse: true,
        layersCount: 11,
      ),
      ContainerImageInfo(
        id: 'sha256:1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d',
        repository: 'ghcr.io/fyrde/gateway',
        tag: '1.27-alpine',
        sizeMb: 48.2,
        created: now.subtract(const Duration(days: 2)),
        inUse: true,
        layersCount: 6,
      ),
      ContainerImageInfo(
        id: 'sha256:8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b',
        repository: 'redis',
        tag: '7.4-alpine',
        sizeMb: 42.6,
        created: now.subtract(const Duration(days: 15)),
        inUse: true,
        layersCount: 7,
      ),
    ]);

    volumes.addAll([
      VolumeInfo(
        name: 'fyr-ollama-models',
        driver: 'local',
        mountpoint:
            '/home/archer/.local/share/containers/storage/volumes/fyr-ollama-models/_data',
        sizeMb: 14820.0,
        createdAt: now.subtract(const Duration(days: 14)),
        attachedContainers: ['fyr-llm-runner'],
      ),
      VolumeInfo(
        name: 'fyr-pgdata-v17',
        driver: 'local',
        mountpoint:
            '/home/archer/.local/share/containers/storage/volumes/fyr-pgdata-v17/_data',
        sizeMb: 1420.4,
        createdAt: now.subtract(const Duration(days: 20)),
        attachedContainers: ['fyr-postgres-db'],
      ),
      VolumeInfo(
        name: 'fyr-prometheus-tsdb',
        driver: 'local',
        mountpoint:
            '/home/archer/.local/share/containers/storage/volumes/fyr-prometheus-tsdb/_data',
        sizeMb: 680.2,
        createdAt: now.subtract(const Duration(days: 10)),
        attachedContainers: ['fyr-prometheus'],
      ),
      VolumeInfo(
        name: 'fyr-redis-aof',
        driver: 'local',
        mountpoint:
            '/home/archer/.local/share/containers/storage/volumes/fyr-redis-aof/_data',
        sizeMb: 96.0,
        createdAt: now.subtract(const Duration(days: 18)),
        attachedContainers: ['fyr-redis-cache'],
      ),
    ]);

    networks.addAll([
      ContainerNetworkInfo(
        id: 'net-fyr-mesh-br0',
        name: 'fyr-mesh-br0',
        driver: 'bridge',
        subnet: '10.88.0.0/16',
        gateway: '10.88.0.1',
        dnsEnabled: true,
        internal: false,
        connectedContainers: [
          'fyr-gateway-nginx',
          'fyr-postgres-db',
          'fyr-redis-cache',
          'fyr-llm-runner',
          'fyr-webui-chat',
        ],
      ),
      ContainerNetworkInfo(
        id: 'net-podman-default',
        name: 'podman',
        driver: 'bridge',
        subnet: '10.89.0.0/24',
        gateway: '10.89.0.1',
        dnsEnabled: true,
        internal: false,
        connectedContainers: ['fyr-prometheus'],
      ),
      ContainerNetworkInfo(
        id: 'net-host-ns',
        name: 'host',
        driver: 'host',
        subnet: 'host-namespace',
        gateway: '127.0.0.1',
        dnsEnabled: true,
        internal: false,
        connectedContainers: const [],
      ),
    ]);

    for (final c in containers) {
      terminalTranscripts[c.id] = [
        'Connected to ${c.name} (${c.image}) via ${activeRuntime.shortLabel}',
        'Type "help", "ps aux", "env", "free -m", "df -h", or "ip addr" to inspect.',
      ];
    }
  }

  // Computed getters
  int get runningContainersCount =>
      containers.where((c) => c.state == ContainerStateStatus.running).length;
  int get pausedContainersCount =>
      containers.where((c) => c.state == ContainerStateStatus.paused).length;
  int get stoppedContainersCount =>
      containers.where((c) => c.state.isStopped).length;

  double get totalCpuPercent => containers.fold(
      0.0, (sum, c) => sum + (c.state.isRunning ? c.cpuPercent : 0.0));

  double get totalMemUsageMb => containers.fold(
      0.0,
      (sum, c) => sum +
          (c.state == ContainerStateStatus.exited ? 0.0 : c.memUsageMb));

  String get formattedTotalRam {
    final gb = totalMemUsageMb / 1024.0;
    return '${gb.toStringAsFixed(1)} GB';
  }

  List<ContainerInfo> get filteredContainers {
    return containers.where((c) {
      switch (statusFilter) {
        case ContainerFilter.all:
          break;
        case ContainerFilter.running:
          if (c.state != ContainerStateStatus.running) return false;
          break;
        case ContainerFilter.paused:
          if (c.state != ContainerStateStatus.paused) return false;
          break;
        case ContainerFilter.stopped:
          if (!c.state.isStopped) return false;
          break;
      }
      if (searchQuery.trim().isNotEmpty) {
        final q = searchQuery.toLowerCase();
        final matchesName = c.name.toLowerCase().contains(q);
        final matchesImage = c.image.toLowerCase().contains(q);
        final matchesPod = (c.podName ?? '').toLowerCase().contains(q);
        final matchesPort =
            c.ports.any((p) => p.formatted.toLowerCase().contains(q));
        if (!matchesName && !matchesImage && !matchesPod && !matchesPort) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  ContainerInfo? get selectedContainer {
    if (containers.isEmpty) return null;
    if (selectedContainerId != null) {
      for (final c in containers) {
        if (c.id == selectedContainerId) return c;
      }
    }
    return containers.first;
  }

  void setSection(PodsNavSection section) {
    activeSection = section;
    notifyListeners();
  }

  void setRuntime(ContainerRuntime runtime) {
    activeRuntime = runtime;
    engine.activeRuntime = runtime;
    statusMessage = 'Switched container runtime to ${runtime.label}';
    notifyListeners();
  }

  void setStatusFilter(ContainerFilter filter) {
    statusFilter = filter;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    searchQuery = query;
    notifyListeners();
  }

  void setLogSearchQuery(String query) {
    logSearchQuery = query;
    notifyListeners();
  }

  void setLogLevelFilter(String level) {
    logLevelFilter = level;
    notifyListeners();
  }

  void selectContainer(String id, {InspectorTab? tab}) {
    selectedContainerId = id;
    if (tab != null) {
      activeInspectorTab = tab;
    }
    notifyListeners();
  }

  void setInspectorTab(InspectorTab tab) {
    activeInspectorTab = tab;
    notifyListeners();
  }

  void startMetricsTicker() {
    _metricsTimer?.cancel();
    _metricsTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      tickMetrics();
    });
  }

  void stopMetricsTicker() {
    _metricsTimer?.cancel();
    _metricsTimer = null;
  }

  void tickMetrics() {
    for (final c in containers) {
      if (c.state == ContainerStateStatus.running) {
        final delta = (_rng.nextDouble() - 0.48) * 3.2;
        c.cpuPercent = (c.cpuPercent + delta).clamp(0.4, 95.0);
        c.cpuPercent = double.parse(c.cpuPercent.toStringAsFixed(1));
        c.cpuHistory.add(c.cpuPercent);
        if (c.cpuHistory.length > 24) c.cpuHistory.removeAt(0);

        final memDelta = (_rng.nextDouble() - 0.49) * 6.0;
        c.memUsageMb =
            (c.memUsageMb + memDelta).clamp(16.0, c.memLimitMb * 0.95);
        c.memUsageMb = double.parse(c.memUsageMb.toStringAsFixed(0));
        c.memHistory.add(c.memUsageMb);
        if (c.memHistory.length > 24) c.memHistory.removeAt(0);
      }
    }
    notifyListeners();
  }

  // Container lifecycle operations
  void startContainer(String id) {
    final idx = containers.indexWhere((c) => c.id == id);
    if (idx == -1) return;
    final c = containers[idx];
    c.state = ContainerStateStatus.running;
    c.statusText = 'Up Less than a second (healthy)';
    if (c.cpuPercent == 0.0) c.cpuPercent = 3.5;
    if (c.memUsageMb == 0.0) c.memUsageMb = 48.0;
    c.logs.add(
        '${DateTime.now().toUtc().toIso8601String()} [INFO] Container ${c.name} started by fyrPods (${activeRuntime.binary})');
    _recomputePodStatuses();
    statusMessage = 'Started container ${c.name}';
    notifyListeners();
  }

  void stopContainer(String id) {
    final idx = containers.indexWhere((c) => c.id == id);
    if (idx == -1) return;
    final c = containers[idx];
    c.state = ContainerStateStatus.exited;
    c.statusText = 'Exited (0) Just now';
    c.cpuPercent = 0.0;
    c.memUsageMb = 0.0;
    c.logs.add(
        '${DateTime.now().toUtc().toIso8601String()} [INFO] Container ${c.name} stopped gracefully (SIGTERM -> exit 0)');
    _recomputePodStatuses();
    statusMessage = 'Stopped container ${c.name}';
    notifyListeners();
  }

  void restartContainer(String id) {
    final idx = containers.indexWhere((c) => c.id == id);
    if (idx == -1) return;
    final c = containers[idx];
    c.state = ContainerStateStatus.running;
    c.statusText = 'Up Less than a second (restarted)';
    if (c.cpuPercent == 0.0) c.cpuPercent = 4.0;
    if (c.memUsageMb == 0.0) c.memUsageMb = 64.0;
    c.logs.add(
        '${DateTime.now().toUtc().toIso8601String()} [INFO] Container ${c.name} restarted cleanly');
    _recomputePodStatuses();
    statusMessage = 'Restarted container ${c.name}';
    notifyListeners();
  }

  void pauseContainer(String id) {
    final idx = containers.indexWhere((c) => c.id == id);
    if (idx == -1) return;
    final c = containers[idx];
    if (c.state == ContainerStateStatus.paused) {
      c.state = ContainerStateStatus.running;
      c.statusText = 'Up (unpaused)';
      c.cpuPercent = 4.2;
      c.logs.add(
          '${DateTime.now().toUtc().toIso8601String()} [INFO] Container ${c.name} unpaused');
      statusMessage = 'Unpaused container ${c.name}';
    } else {
      c.state = ContainerStateStatus.paused;
      c.statusText = 'Paused (just now)';
      c.cpuPercent = 0.0;
      c.logs.add(
          '${DateTime.now().toUtc().toIso8601String()} [WARN] Container ${c.name} cgroup frozen');
      statusMessage = 'Paused container ${c.name}';
    }
    _recomputePodStatuses();
    notifyListeners();
  }

  ContainerInfo createContainer({
    required String name,
    required String image,
    List<PortMapping> ports = const [],
    List<VolumeMount> mounts = const [],
    Map<String, String> env = const {},
    String? podName,
    double memLimitMb = 1024.0,
    bool startImmediately = true,
  }) {
    final cleanName = name.trim().isEmpty
        ? 'fyr-container-${containers.length + 1}'
        : name.trim();
    final id = 'c-$cleanName-${DateTime.now().millisecondsSinceEpoch % 10000}';

    String? podId;
    if (podName != null && podName.isNotEmpty) {
      for (final p in pods) {
        if (p.name == podName) {
          podId = p.id;
          p.containerIds.add(id);
          break;
        }
      }
    }

    final c = ContainerInfo(
      id: id,
      name: cleanName,
      image: image.trim().isEmpty ? 'alpine:latest' : image.trim(),
      podId: podId,
      podName: podName,
      state: startImmediately
          ? ContainerStateStatus.running
          : ContainerStateStatus.created,
      statusText:
          startImmediately ? 'Up Less than a second (healthy)' : 'Created',
      created: DateTime.now(),
      ports: ports,
      mounts: mounts,
      env: env,
      memLimitMb: memLimitMb,
      cpuPercent: startImmediately ? 3.2 : 0.0,
      memUsageMb: startImmediately ? 54.0 : 0.0,
      logs: [
        '${DateTime.now().toUtc().toIso8601String()} [INFO] Created container $cleanName from $image',
        if (startImmediately)
          '${DateTime.now().toUtc().toIso8601String()} [INFO] Entrypoint started cleanly',
      ],
    );

    containers.insert(0, c);
    terminalTranscripts[c.id] = [
      'Connected to ${c.name} (${c.image}) via ${activeRuntime.shortLabel}',
    ];
    selectedContainerId = c.id;
    _recomputePodStatuses();
    statusMessage = 'Created & started container $cleanName';
    notifyListeners();
    return c;
  }

  void removeContainer(String id) {
    final idx = containers.indexWhere((c) => c.id == id);
    if (idx == -1) return;
    final removed = containers.removeAt(idx);
    for (final p in pods) {
      p.containerIds.remove(id);
    }
    terminalTranscripts.remove(id);
    if (selectedContainerId == id) {
      selectedContainerId = containers.isNotEmpty ? containers.first.id : null;
    }
    _recomputePodStatuses();
    statusMessage = 'Removed container ${removed.name}';
    notifyListeners();
  }

  // Pod group actions
  void startPod(String podId) {
    final idx = pods.indexWhere((p) => p.id == podId);
    if (idx == -1) return;
    final pod = pods[idx];
    for (final c in containers) {
      if (pod.containerIds.contains(c.id)) {
        c.state = ContainerStateStatus.running;
        c.statusText = 'Up Less than a second (healthy)';
        if (c.cpuPercent == 0.0) c.cpuPercent = 3.8;
        if (c.memUsageMb == 0.0) c.memUsageMb = 64.0;
      }
    }
    _recomputePodStatuses();
    statusMessage = 'Started all containers in pod ${pod.name}';
    notifyListeners();
  }

  void stopPod(String podId) {
    final idx = pods.indexWhere((p) => p.id == podId);
    if (idx == -1) return;
    final pod = pods[idx];
    for (final c in containers) {
      if (pod.containerIds.contains(c.id)) {
        c.state = ContainerStateStatus.exited;
        c.statusText = 'Exited (0) Just now';
        c.cpuPercent = 0.0;
        c.memUsageMb = 0.0;
      }
    }
    _recomputePodStatuses();
    statusMessage = 'Stopped pod ${pod.name}';
    notifyListeners();
  }

  void restartPod(String podId) {
    startPod(podId);
    final idx = pods.indexWhere((p) => p.id == podId);
    if (idx != -1) {
      statusMessage = 'Restarted pod ${pods[idx].name}';
      notifyListeners();
    }
  }

  PodGroupInfo deployKubeYaml(String yamlContent) {
    // Extract metadata.name and container name/image from YAML
    String podName = 'fyr-kube-pod-${pods.length + 1}';
    String image = 'nginx:1.27-alpine';
    int hostPort = 8088;
    int containerPort = 80;

    final lines = yamlContent.split('\n');
    bool inMetadata = false;
    for (final raw in lines) {
      final line = raw.trim();
      if (raw.startsWith('metadata:')) {
        inMetadata = true;
        continue;
      }
      if (raw.startsWith('spec:')) {
        inMetadata = false;
      }
      if (inMetadata && line.startsWith('name:')) {
        final parsed = line.substring(5).trim().replaceAll('"', '');
        if (parsed.isNotEmpty) podName = parsed;
      }
      if (line.startsWith('image:')) {
        final parsed = line.substring(6).trim().replaceAll('"', '');
        if (parsed.isNotEmpty) image = parsed;
      }
      if (line.startsWith('hostPort:')) {
        hostPort = int.tryParse(line.substring(9).trim()) ?? hostPort;
      }
      if (line.startsWith('containerPort:')) {
        containerPort =
            int.tryParse(line.substring(14).trim()) ?? containerPort;
      }
    }

    final podId = 'pod-$podName-${DateTime.now().millisecondsSinceEpoch % 1000}';
    final container = ContainerInfo(
      id: 'c-$podName-main',
      name: '$podName-app',
      image: image,
      podId: podId,
      podName: podName,
      state: ContainerStateStatus.running,
      statusText: 'Up Less than a second (podman kube play)',
      created: DateTime.now(),
      ports: [
        PortMapping(
            hostIp: '0.0.0.0',
            hostPort: hostPort,
            containerPort: containerPort),
      ],
      cpuPercent: 2.8,
      memUsageMb: 52.0,
      logs: [
        '${DateTime.now().toUtc().toIso8601String()} [INFO] Deployed via `podman kube play` into pod $podName',
      ],
    );

    final pod = PodGroupInfo(
      id: podId,
      name: podName,
      status: 'Running',
      infraId: 'infra-${podId.hashCode.abs()}',
      containerIds: [container.id],
      sharedPorts: container.ports,
      created: DateTime.now(),
      kubeYaml: yamlContent,
    );

    containers.insert(0, container);
    pods.insert(0, pod);
    terminalTranscripts[container.id] = [
      'Connected to ${container.name} (${container.image})',
    ];
    selectedContainerId = container.id;
    statusMessage = 'Deployed Kubernetes Pod "$podName" via play kube';
    notifyListeners();
    return pod;
  }

  void _recomputePodStatuses() {
    for (final pod in pods) {
      final members =
          containers.where((c) => pod.containerIds.contains(c.id)).toList();
      if (members.isEmpty) {
        pod.status = 'Stopped';
        continue;
      }
      final running =
          members.where((c) => c.state == ContainerStateStatus.running).length;
      if (running == members.length) {
        pod.status = 'Running';
      } else if (running > 0) {
        pod.status = 'Degraded';
      } else {
        pod.status = 'Stopped';
      }
    }
  }

  // Image actions
  ContainerImageInfo pullImage(String imageRef) {
    final trimmed = imageRef.trim().isEmpty ? 'alpine:latest' : imageRef.trim();
    String repo = trimmed;
    String tag = 'latest';
    if (trimmed.contains(':')) {
      final idx = trimmed.lastIndexOf(':');
      repo = trimmed.substring(0, idx);
      tag = trimmed.substring(idx + 1);
    }
    final img = ContainerImageInfo(
      id: 'sha256:${trimmed.hashCode.abs().toRadixString(16).padLeft(12, '0')}a1b2c3',
      repository: repo,
      tag: tag,
      sizeMb: 84.5,
      created: DateTime.now(),
      inUse: false,
      layersCount: 6,
    );
    images.insert(0, img);
    statusMessage = 'Pulled image ${img.fullTag}';
    notifyListeners();
    return img;
  }

  ContainerImageInfo buildImage({
    required String tag,
    required String containerfile,
  }) {
    final img = pullImage(tag.trim().isEmpty ? 'fyr-custom:latest' : tag);
    statusMessage =
        'Built OCI image ${img.fullTag} (${containerfile.split('\n').length} Containerfile instructions)';
    notifyListeners();
    return img;
  }

  void removeImage(String id) {
    images.removeWhere((i) => i.id == id);
    statusMessage = 'Removed image $id';
    notifyListeners();
  }

  // Volume actions
  VolumeInfo createVolume({
    required String name,
    String driver = 'local',
  }) {
    final clean =
        name.trim().isEmpty ? 'fyr-vol-${volumes.length + 1}' : name.trim();
    final vol = VolumeInfo(
      name: clean,
      driver: driver,
      mountpoint:
          '/home/archer/.local/share/containers/storage/volumes/$clean/_data',
      sizeMb: 0.4,
      createdAt: DateTime.now(),
    );
    volumes.insert(0, vol);
    statusMessage = 'Created volume $clean';
    notifyListeners();
    return vol;
  }

  void removeVolume(String name) {
    volumes.removeWhere((v) => v.name == name);
    statusMessage = 'Removed volume $name';
    notifyListeners();
  }

  // Network actions
  ContainerNetworkInfo createNetwork({
    required String name,
    String driver = 'bridge',
    String subnet = '10.90.0.0/24',
    String gateway = '10.90.0.1',
    bool internal = false,
  }) {
    final clean =
        name.trim().isEmpty ? 'fyr-net-${networks.length + 1}' : name.trim();
    final net = ContainerNetworkInfo(
      id: 'net-$clean',
      name: clean,
      driver: driver,
      subnet: subnet,
      gateway: gateway,
      dnsEnabled: true,
      internal: internal,
    );
    networks.insert(0, net);
    statusMessage = 'Created container network $clean ($subnet)';
    notifyListeners();
    return net;
  }

  void removeNetwork(String id) {
    networks.removeWhere((n) => n.id == id && n.name != 'podman' && n.name != 'host');
    statusMessage = 'Removed network';
    notifyListeners();
  }

  void pruneUnused() {
    final beforeStopped = stoppedContainersCount;
    final beforeUnusedImages = images.where((i) => !i.inUse).length;
    containers.removeWhere((c) => c.state == ContainerStateStatus.exited);
    images.removeWhere((i) => !i.inUse);
    _recomputePodStatuses();
    if (selectedContainerId != null &&
        !containers.any((c) => c.id == selectedContainerId)) {
      selectedContainerId = containers.isNotEmpty ? containers.first.id : null;
    }
    statusMessage =
        'Pruned $beforeStopped exited containers and $beforeUnusedImages unused images';
    notifyListeners();
  }

  Future<String> execCommand(String containerId, String command) async {
    final idx = containers.indexWhere((c) => c.id == containerId);
    if (idx == -1) return 'Container not found';
    final c = containers[idx];
    final transcript = terminalTranscripts.putIfAbsent(c.id, () => []);
    transcript.add('root@${c.shortId}:/# $command');
    if (command.trim() == 'clear') {
      transcript.clear();
      notifyListeners();
      return '';
    }
    final output = await engine.execInContainer(c, command);
    if (output.isNotEmpty) {
      transcript.add(output);
    }
    notifyListeners();
    return output;
  }

  @override
  void dispose() {
    _metricsTimer?.cancel();
    super.dispose();
  }
}
