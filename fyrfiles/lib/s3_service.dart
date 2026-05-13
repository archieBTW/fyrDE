import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;

class S3Config {
  final String remoteName;
  final String endpoint;
  final String accessKey;
  final String secretKey;
  final String region;
  final String bucket;
  final bool enabled;

  S3Config({
    required this.remoteName,
    required this.endpoint,
    required this.accessKey,
    required this.secretKey,
    required this.region,
    required this.bucket,
    this.enabled = false,
  });

  Map<String, dynamic> toJson() => {
    'remoteName': remoteName,
    'endpoint': endpoint,
    'accessKey': accessKey,
    'secretKey': secretKey,
    'region': region,
    'bucket': bucket,
    'enabled': enabled,
  };

  factory S3Config.fromJson(Map<String, dynamic> json) => S3Config(
    remoteName: json['remoteName'] ?? 's3',
    endpoint: json['endpoint'] ?? '',
    accessKey: json['accessKey'] ?? '',
    secretKey: json['secretKey'] ?? '',
    region: json['region'] ?? 'us-east-1',
    bucket: json['bucket'] ?? '',
    enabled: json['enabled'] ?? false,
  );

  factory S3Config.empty() => S3Config(
    remoteName: 's3',
    endpoint: '',
    accessKey: '',
    secretKey: '',
    region: 'us-east-1',
    bucket: '',
    enabled: false,
  );
}

class S3Service {
  static const String _configFileName = 's3_config.json';
  
  static String get _configPath {
    final home = Platform.environment['HOME'] ?? '/home/';
    return p.join(home, '.fyr/files', _configFileName);
  }

  static String get mountPath {
    final home = Platform.environment['HOME'] ?? '/home/';
    return p.join(home, '.fyr/mounts/s3');
  }

  static Future<S3Config> loadConfig() async {
    final file = File(_configPath);
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        return S3Config.fromJson(jsonDecode(content));
      } catch (e) {
        return S3Config.empty();
      }
    }
    return S3Config.empty();
  }

  static Future<void> saveConfig(S3Config config) async {
    final file = File(_configPath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(jsonEncode(config.toJson()));
  }

  static Future<void> updateRcloneConfig(S3Config config) async {
    // rclone config create <name> s3 provider <provider> access_key_id <key> secret_access_key <secret> endpoint <endpoint> region <region>
    final result = await Process.run('rclone', [
      'config', 'create', 
      config.remoteName, 
      's3', 
      'provider', 'Other',
      'access_key_id', config.accessKey,
      'secret_access_key', config.secretKey,
      'endpoint', config.endpoint,
      'region', config.region,
    ]);
    
    if (result.exitCode != 0) {
      throw Exception('Failed to update rclone config: ${result.stderr}');
    }
  }

  static Future<void> mount(S3Config config) async {
    final dir = Directory(mountPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Check if already mounted and healthy
    final checkMount = await Process.run('mountpoint', ['-q', mountPath]);
    if (checkMount.exitCode == 0) {
      try {
        // Quick check to see if the mount is healthy (not stale/IO error)
        final checkResult = await Process.run('ls', [mountPath]).timeout(const Duration(seconds: 2));
        if (checkResult.exitCode == 0) {
          return; // Already mounted and healthy
        }
      } catch (e) {
        // Stale or timed out, proceed to unmount and remount
      }
      await unmount();
    }

    // rclone mount remote:bucket /path/to/mount --vfs-cache-mode full --daemon
    // We exclude "//" because S3 keys named "/" cause IO errors on FUSE mounts
    final result = await Process.run('rclone', [
      'mount', 
      '${config.remoteName}:${config.bucket}', 
      mountPath,
      '--vfs-cache-mode', 'full',
      '--exclude', '//',
      '--daemon',
    ]);

    if (result.exitCode != 0) {
      throw Exception('Failed to mount S3: ${result.stderr}');
    }
  }

  static Future<void> unmount() async {
    final checkMount = await Process.run('mountpoint', ['-q', mountPath]);
    if (checkMount.exitCode != 0) {
      return; // Not mounted
    }

    final result = await Process.run('fusermount3', ['-u', mountPath]);
    if (result.exitCode != 0) {
      // Fallback to fusermount
      await Process.run('fusermount', ['-u', mountPath]);
    }
  }

  static String getRelativePath(String absolutePath) {
    if (!absolutePath.startsWith(mountPath)) return absolutePath;
    String relative = absolutePath.substring(mountPath.length);
    if (relative.startsWith('/')) relative = relative.substring(1);
    return relative;
  }
}
