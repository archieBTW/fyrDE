import 'dart:convert';
import 'dart:io';
import '../models/pod_models.dart';

class ContainerEngine {
  final bool allowLiveCli;
  bool isLiveDaemonConnected = false;
  ContainerRuntime activeRuntime = ContainerRuntime.podman;

  ContainerEngine({this.allowLiveCli = false});

  /// Detects if `podman` or `docker` CLI is responsive on the system.
  Future<ContainerRuntime?> detectAvailableRuntime() async {
    if (!allowLiveCli) return null;
    for (final rt in ContainerRuntime.values) {
      try {
        final res = await Process.run(
          rt.binary,
          ['info', '--format', 'json'],
        ).timeout(const Duration(seconds: 2));
        if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
          activeRuntime = rt;
          isLiveDaemonConnected = true;
          return rt;
        }
      } catch (_) {
        // Binary not installed or daemon not running.
      }
    }
    isLiveDaemonConnected = false;
    return null;
  }

  /// Parses Podman or Docker `ps -a --format json` output into `ContainerInfo` models.
  static List<ContainerInfo> parseContainersJson(String rawJson) {
    final trimmed = rawJson.trim();
    if (trimmed.isEmpty) return [];

    final List<dynamic> items = [];
    if (trimmed.startsWith('[')) {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) items.addAll(decoded);
    } else {
      for (final line in trimmed.split('\n')) {
        final l = line.trim();
        if (l.isNotEmpty && l.startsWith('{')) {
          items.add(jsonDecode(l));
        }
      }
    }

    final result = <ContainerInfo>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final id = (map['Id'] ?? map['ID'] ?? '').toString();

      String name = '';
      final rawNames = map['Names'];
      if (rawNames is List && rawNames.isNotEmpty) {
        name = rawNames.first.toString();
      } else if (rawNames is String) {
        name = rawNames;
      }
      if (name.startsWith('/')) name = name.substring(1);

      final image = (map['Image'] ?? '').toString();
      final podId = map['Pod']?.toString();
      final podName = map['PodName']?.toString();

      final rawState = (map['State'] ?? map['Status'] ?? 'running')
          .toString()
          .toLowerCase();
      ContainerStateStatus state;
      if (rawState.contains('pause')) {
        state = ContainerStateStatus.paused;
      } else if (rawState.contains('exit') || rawState.contains('stop') || rawState.contains('dead')) {
        state = ContainerStateStatus.exited;
      } else if (rawState.contains('creat')) {
        state = ContainerStateStatus.created;
      } else if (rawState.contains('restart')) {
        state = ContainerStateStatus.restarting;
      } else {
        state = ContainerStateStatus.running;
      }

      final statusText = (map['Status'] ?? state.label).toString();

      final ports = <PortMapping>[];
      final rawPorts = map['Ports'];
      if (rawPorts is List) {
        for (final p in rawPorts) {
          if (p is Map) {
            final hostIp = (p['host_ip'] ?? p['HostIp'] ?? '0.0.0.0').toString();
            final hostPort = int.tryParse(
                    (p['host_port'] ?? p['PublicPort'] ?? '0').toString()) ??
                0;
            final containerPort = int.tryParse((p['container_port'] ??
                        p['PrivatePort'] ??
                        hostPort)
                    .toString()) ??
                hostPort;
            final protocol = (p['protocol'] ?? p['Type'] ?? 'tcp').toString();
            if (hostPort > 0 || containerPort > 0) {
              ports.add(PortMapping(
                hostIp: hostIp.isEmpty ? '0.0.0.0' : hostIp,
                hostPort: hostPort > 0 ? hostPort : containerPort,
                containerPort: containerPort,
                protocol: protocol,
              ));
            }
          }
        }
      } else if (rawPorts is String && rawPorts.isNotEmpty) {
        // Docker format: "0.0.0.0:8080->80/tcp, 127.0.0.1:5432->5432/tcp"
        final segments = rawPorts.split(',');
        final regex =
            RegExp(r'([\d\.]+):(\d+)->(\d+)/(tcp|udp)', caseSensitive: false);
        for (final seg in segments) {
          final m = regex.firstMatch(seg.trim());
          if (m != null) {
            ports.add(PortMapping(
              hostIp: m.group(1)!,
              hostPort: int.parse(m.group(2)!),
              containerPort: int.parse(m.group(3)!),
              protocol: m.group(4)!.toLowerCase(),
            ));
          }
        }
      }

      DateTime created = DateTime.now().subtract(const Duration(hours: 2));
      final rawCreated = map['Created'] ?? map['CreatedAt'];
      if (rawCreated is int) {
        created = DateTime.fromMillisecondsSinceEpoch(rawCreated * 1000);
      } else if (rawCreated is String) {
        created = DateTime.tryParse(rawCreated) ?? created;
      }

      result.add(ContainerInfo(
        id: id.isEmpty ? 'c-${result.length}' : id,
        name: name.isEmpty ? 'container-${result.length}' : name,
        image: image,
        podId: (podId != null && podId.isNotEmpty) ? podId : null,
        podName: (podName != null && podName.isNotEmpty) ? podName : null,
        state: state,
        statusText: statusText,
        created: created,
        ports: ports,
      ));
    }
    return result;
  }

  /// Parses Podman or Docker `images --format json` output into `ContainerImageInfo` models.
  static List<ContainerImageInfo> parseImagesJson(String rawJson) {
    final trimmed = rawJson.trim();
    if (trimmed.isEmpty) return [];

    final List<dynamic> items = [];
    if (trimmed.startsWith('[')) {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) items.addAll(decoded);
    } else {
      for (final line in trimmed.split('\n')) {
        final l = line.trim();
        if (l.isNotEmpty && l.startsWith('{')) {
          items.add(jsonDecode(l));
        }
      }
    }

    final result = <ContainerImageInfo>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final id = (map['Id'] ?? map['ID'] ?? '').toString();

      String repository = '<none>';
      String tag = 'latest';

      if (map['Names'] is List && (map['Names'] as List).isNotEmpty) {
        final firstName = (map['Names'] as List).first.toString();
        final lastColon = firstName.lastIndexOf(':');
        if (lastColon > 0) {
          repository = firstName.substring(0, lastColon);
          tag = firstName.substring(lastColon + 1);
        } else {
          repository = firstName;
        }
      } else {
        repository = (map['Repository'] ?? map['repository'] ?? '<none>').toString();
        tag = (map['Tag'] ?? map['tag'] ?? 'latest').toString();
      }

      double sizeMb = 120.0;
      final rawSize = map['Size'] ?? map['VirtualSize'];
      if (rawSize is num) {
        sizeMb = rawSize / (1024.0 * 1024.0);
      } else if (rawSize is String) {
        final upper = rawSize.toUpperCase();
        final numVal =
            double.tryParse(upper.replaceAll(RegExp(r'[^0-9\.]'), '')) ?? 100.0;
        if (upper.contains('GB')) {
          sizeMb = numVal * 1024.0;
        } else if (upper.contains('KB')) {
          sizeMb = numVal / 1024.0;
        } else {
          sizeMb = numVal;
        }
      }

      final containersCount =
          int.tryParse((map['Containers'] ?? '0').toString()) ?? 0;

      result.add(ContainerImageInfo(
        id: id.isEmpty ? 'sha256:img${result.length}' : id,
        repository: repository,
        tag: tag,
        sizeMb: double.parse(sizeMb.toStringAsFixed(1)),
        created: DateTime.now().subtract(const Duration(days: 3)),
        inUse: containersCount > 0,
      ));
    }
    return result;
  }

  /// Generates Kubernetes v1 Pod YAML manifest for a single container.
  static String generateKubeYaml(ContainerInfo c) {
    final buf = StringBuffer();
    buf.writeln('apiVersion: v1');
    buf.writeln('kind: Pod');
    buf.writeln('metadata:');
    buf.writeln('  name: ${c.podName ?? "${c.name}-pod"}');
    buf.writeln('  labels:');
    buf.writeln('    app.kubernetes.io/name: ${c.name}');
    buf.writeln('    app.kubernetes.io/managed-by: fyrPods');
    buf.writeln('spec:');
    buf.writeln('  restartPolicy: Always');
    buf.writeln('  containers:');
    buf.writeln('    - name: ${c.name}');
    buf.writeln('      image: ${c.image}');
    if (c.command.isNotEmpty) {
      buf.writeln('      command: ["${c.command}"]');
    }
    if (c.ports.isNotEmpty) {
      buf.writeln('      ports:');
      for (final p in c.ports) {
        buf.writeln('        - containerPort: ${p.containerPort}');
        buf.writeln('          hostPort: ${p.hostPort}');
        buf.writeln('          protocol: ${p.protocol.toUpperCase()}');
      }
    }
    if (c.env.isNotEmpty) {
      buf.writeln('      env:');
      for (final entry in c.env.entries) {
        buf.writeln('        - name: ${entry.key}');
        buf.writeln('          value: "${entry.value}"');
      }
    }
    buf.writeln('      resources:');
    buf.writeln('        limits:');
    buf.writeln('          memory: "${c.memLimitMb.round()}Mi"');
    if (c.mounts.isNotEmpty) {
      buf.writeln('      volumeMounts:');
      for (var i = 0; i < c.mounts.length; i++) {
        final m = c.mounts[i];
        buf.writeln('        - name: vol-$i');
        buf.writeln('          mountPath: ${m.destination}');
        buf.writeln('          readOnly: ${m.mode == "ro"}');
      }
      buf.writeln('  volumes:');
      for (var i = 0; i < c.mounts.length; i++) {
        final m = c.mounts[i];
        buf.writeln('    - name: vol-$i');
        if (m.source.startsWith('/')) {
          buf.writeln('      hostPath:');
          buf.writeln('        path: ${m.source}');
        } else {
          buf.writeln('      persistentVolumeClaim:');
          buf.writeln('        claimName: ${m.source}');
        }
      }
    }
    return buf.toString();
  }

  /// Generates Kubernetes v1 Pod YAML manifest for a multi-container Pod group.
  static String generatePodKubeYaml(
      PodGroupInfo pod, List<ContainerInfo> members) {
    final buf = StringBuffer();
    buf.writeln('apiVersion: v1');
    buf.writeln('kind: Pod');
    buf.writeln('metadata:');
    buf.writeln('  name: ${pod.name}');
    buf.writeln('  labels:');
    buf.writeln('    app.kubernetes.io/part-of: ${pod.name}');
    buf.writeln('    app.kubernetes.io/managed-by: fyrPods');
    buf.writeln('spec:');
    buf.writeln('  restartPolicy: Always');
    buf.writeln('  containers:');
    for (final c in members) {
      buf.writeln('    - name: ${c.name}');
      buf.writeln('      image: ${c.image}');
      if (c.ports.isNotEmpty) {
        buf.writeln('      ports:');
        for (final p in c.ports) {
          buf.writeln('        - containerPort: ${p.containerPort}');
          buf.writeln('          hostPort: ${p.hostPort}');
          buf.writeln('          protocol: ${p.protocol.toUpperCase()}');
        }
      }
      if (c.env.isNotEmpty) {
        buf.writeln('      env:');
        for (final entry in c.env.entries) {
          buf.writeln('        - name: ${entry.key}');
          buf.writeln('          value: "${entry.value}"');
        }
      }
      buf.writeln('      resources:');
      buf.writeln('        limits:');
      buf.writeln('          memory: "${c.memLimitMb.round()}Mi"');
    }
    return buf.toString();
  }

  /// Generates a Compose (`docker-compose.yml` / `compose.yaml`) file for a list of containers.
  static String generateComposeYaml(
    List<ContainerInfo> containers, {
    String stackName = 'fyr-stack',
  }) {
    final buf = StringBuffer();
    buf.writeln('name: $stackName');
    buf.writeln('services:');
    for (final c in containers) {
      buf.writeln('  ${c.name}:');
      buf.writeln('    image: ${c.image}');
      buf.writeln('    container_name: ${c.name}');
      buf.writeln('    restart: unless-stopped');
      if (c.ports.isNotEmpty) {
        buf.writeln('    ports:');
        for (final p in c.ports) {
          buf.writeln(
              '      - "${p.hostIp}:${p.hostPort}:${p.containerPort}/${p.protocol}"');
        }
      }
      if (c.env.isNotEmpty) {
        buf.writeln('    environment:');
        for (final entry in c.env.entries) {
          buf.writeln('      ${entry.key}: "${entry.value}"');
        }
      }
      if (c.mounts.isNotEmpty) {
        buf.writeln('    volumes:');
        for (final m in c.mounts) {
          buf.writeln('      - "${m.source}:${m.destination}:${m.mode}"');
        }
      }
    }
    return buf.toString();
  }

  /// Executes an interactive shell command inside a container (or simulates realistic output).
  Future<String> execInContainer(
      ContainerInfo container, String rawCommand) async {
    final cmd = rawCommand.trim();
    if (cmd.isEmpty) return '';

    if (allowLiveCli && isLiveDaemonConnected) {
      try {
        final res = await Process.run(
          activeRuntime.binary,
          ['exec', container.name, 'sh', '-c', cmd],
        ).timeout(const Duration(seconds: 5));
        final out = '${res.stdout}${res.stderr}'.trimRight();
        return out.isEmpty ? '(exit ${res.exitCode})' : out;
      } catch (_) {
        // Fall through to deterministic container shell simulation.
      }
    }

    if (!container.state.isRunning) {
      return 'Error: container ${container.name} (${container.shortId}) is not running (state: ${container.state.label})';
    }

    switch (cmd) {
      case 'whoami':
        return activeRuntime.isRootless ? 'root (mapped uid=1000)' : 'root';
      case 'uname -a':
        return 'Linux ${container.shortId} 6.12.8-arch1-1 #1 SMP PREEMPT_DYNAMIC x86_64 Linux';
      case 'ps aux':
      case 'ps':
        return 'PID   USER     TIME  COMMAND\n'
            '    1 root      0:04 ${container.command}\n'
            '   28 root      0:01 /usr/sbin/healthcheck-agent --interval=15s\n'
            '   64 root      0:00 /bin/sh -i';
      case 'free -m':
        final used = container.memUsageMb.round();
        final total = container.memLimitMb.round();
        final free = (total - used).clamp(0, total);
        return '              total        used        free      shared  buff/cache   available\n'
            'Mem:          ${total.toString().padLeft(5)}       ${used.toString().padLeft(5)}       ${free.toString().padLeft(5)}          12          48       ${free.toString().padLeft(5)}';
      case 'df -h':
        return 'Filesystem      Size  Used Avail Use% Mounted on\n'
            'overlay          64G  8.4G   55G  14% /\n'
            'tmpfs            64M     0   64M   0% /dev\n'
            'shm              64M  4.0K   64M   1% /dev/shm';
      case 'env':
        final lines = <String>[
          'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
          'HOSTNAME=${container.shortId}',
          'CONTAINER_NAME=${container.name}',
          if (container.podName != null) 'POD_NAME=${container.podName}',
          ...container.env.entries.map((e) => '${e.key}=${e.value}'),
        ];
        return lines.join('\n');
      case 'ip addr':
      case 'ifconfig':
        return '1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN\n'
            '    inet 127.0.0.1/8 scope host lo\n'
            '2: eth0@if14: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP\n'
            '    inet 10.88.0.${(container.name.hashCode.abs() % 200) + 10}/16 brd 10.88.255.255 scope global eth0';
      case 'cat /etc/os-release':
        return 'NAME="Alpine Linux"\n'
            'ID=alpine\n'
            'VERSION_ID=3.20.3\n'
            'PRETTY_NAME="Alpine Linux v3.20 (fyrPods Container Runtime)"';
      case 'ls':
      case 'ls -la':
        return 'drwxr-xr-x    1 root root  4096 Nov 18 03:20 .\n'
            'drwxr-xr-x    1 root root  4096 Nov 18 03:20 ..\n'
            '-rwxr-xr-x    1 root root  1842 Nov 18 03:18 entrypoint.sh\n'
            'drwxr-xr-x    2 root root  4096 Nov 18 03:20 etc\n'
            'drwxr-xr-x    4 root root  4096 Nov 18 03:22 var';
      case 'help':
        return 'Available built-in inspection commands:\n'
            '  ps aux | env | free -m | df -h | ip addr | uname -a | ls -la | cat /etc/os-release | whoami';
      default:
        if (cmd.startsWith('echo ')) {
          return cmd.substring(5).replaceAll('"', '');
        }
        return '[exec ${container.shortId}] \$ $cmd\n'
            'Executed in namespace of ${container.name} (${container.image}) -> exit code 0';
    }
  }
}
