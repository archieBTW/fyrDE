import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/pod_models.dart';
import '../state/pods_controller.dart';

class RunContainerDialog extends StatefulWidget {
  final String? initialImage;
  const RunContainerDialog({super.key, this.initialImage});

  static Future<void> show(BuildContext context, {String? initialImage}) {
    return showDialog(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<PodsController>(),
        child: RunContainerDialog(initialImage: initialImage),
      ),
    );
  }

  @override
  State<RunContainerDialog> createState() => _RunContainerDialogState();
}

class _RunContainerDialogState extends State<RunContainerDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _imageCtrl;
  final TextEditingController _hostPortCtrl = TextEditingController(text: '8085');
  final TextEditingController _containerPortCtrl =
      TextEditingController(text: '80');
  final TextEditingController _envCtrl =
      TextEditingController(text: 'TZ=UTC\nNODE_ENV=production');
  final TextEditingController _mountSourceCtrl = TextEditingController();
  final TextEditingController _mountDestCtrl = TextEditingController();
  String? _selectedPod;
  double _memLimitMb = 1024;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: 'fyr-app-service');
    _imageCtrl =
        TextEditingController(text: widget.initialImage ?? 'nginx:1.27-alpine');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _imageCtrl.dispose();
    _hostPortCtrl.dispose();
    _containerPortCtrl.dispose();
    _envCtrl.dispose();
    _mountSourceCtrl.dispose();
    _mountDestCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<PodsController>();
    return AlertDialog(
      backgroundColor: FyrTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: FyrTheme.dividerColor),
      ),
      title: Row(
        children: [
          Icon(Icons.rocket_launch_rounded,
              color: FyrTheme.accentColor, size: 20),
          const SizedBox(width: 8),
          Text(
            'Run New Container',
            style: GoogleFonts.outfit(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: FyrTheme.textColor,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldLabel('Container Name'),
              _textField(_nameCtrl, hint: 'e.g. fyr-api-worker'),
              const SizedBox(height: 10),
              _fieldLabel('OCI Image Reference'),
              _textField(_imageCtrl,
                  hint: 'e.g. ghcr.io/fyrde/gateway:1.27-alpine'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('Host Port'),
                        _textField(_hostPortCtrl, hint: '8085'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('Container Port'),
                        _textField(_containerPortCtrl, hint: '80'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('Attach to Pod'),
                        DropdownButtonFormField<String?>(
                          initialValue: _selectedPod,
                          dropdownColor: FyrTheme.surfaceColor,
                          style: TextStyle(
                              fontSize: 12.5, color: FyrTheme.textColor),
                          decoration: _inputDecoration(),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Standalone (No Pod)'),
                            ),
                            ...ctrl.pods.map(
                              (p) => DropdownMenuItem<String?>(
                                value: p.name,
                                child: Text(p.name),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() => _selectedPod = v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('Volume / Host Source (optional)'),
                        _textField(_mountSourceCtrl,
                            hint: 'fyr-pgdata-v17 or /host/path'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('Mount Target Path'),
                        _textField(_mountDestCtrl, hint: '/data'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _fieldLabel('Environment Variables (KEY=VALUE per line)'),
              _textField(_envCtrl, maxLines: 3),
              const SizedBox(height: 10),
              Row(
                children: [
                  _fieldLabel('Memory Limit: ${_memLimitMb.round()} MB'),
                  Expanded(
                    child: Slider(
                      value: _memLimitMb,
                      min: 128,
                      max: 16384,
                      divisions: 32,
                      activeColor: FyrTheme.accentColor,
                      onChanged: (v) => setState(() => _memLimitMb = v),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: FyrTheme.textColorMuted)),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: FyrTheme.accentColor,
            foregroundColor: FyrTheme.getContrastingColor(FyrTheme.accentColor),
          ),
          onPressed: () {
            final hp = int.tryParse(_hostPortCtrl.text.trim()) ?? 0;
            final cp = int.tryParse(_containerPortCtrl.text.trim()) ?? 0;
            final ports = <PortMapping>[
              if (hp > 0 && cp > 0)
                PortMapping(hostIp: '0.0.0.0', hostPort: hp, containerPort: cp),
            ];
            final mounts = <VolumeMount>[
              if (_mountSourceCtrl.text.trim().isNotEmpty &&
                  _mountDestCtrl.text.trim().isNotEmpty)
                VolumeMount(
                  source: _mountSourceCtrl.text.trim(),
                  destination: _mountDestCtrl.text.trim(),
                ),
            ];
            final env = <String, String>{};
            for (final line in _envCtrl.text.split('\n')) {
              final idx = line.indexOf('=');
              if (idx > 0) {
                env[line.substring(0, idx).trim()] =
                    line.substring(idx + 1).trim();
              }
            }
            ctrl.createContainer(
              name: _nameCtrl.text,
              image: _imageCtrl.text,
              ports: ports,
              mounts: mounts,
              env: env,
              podName: _selectedPod,
              memLimitMb: _memLimitMb,
            );
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.play_arrow_rounded, size: 16),
          label: const Text('Create & Run'),
        ),
      ],
    );
  }
}

class PullImageDialog extends StatefulWidget {
  const PullImageDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<PodsController>(),
        child: const PullImageDialog(),
      ),
    );
  }

  @override
  State<PullImageDialog> createState() => _PullImageDialogState();
}

class _PullImageDialogState extends State<PullImageDialog> {
  final TextEditingController _refCtrl =
      TextEditingController(text: 'ghcr.io/fyrde/edge-proxy:latest');

  @override
  void dispose() {
    _refCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<PodsController>();
    return AlertDialog(
      backgroundColor: FyrTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: FyrTheme.dividerColor),
      ),
      title: Row(
        children: [
          Icon(Icons.cloud_download_rounded,
              color: FyrTheme.accentColor, size: 20),
          const SizedBox(width: 8),
          Text(
            'Pull Container Image',
            style: GoogleFonts.outfit(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: FyrTheme.textColor,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabel('Registry / Image Tag'),
            _textField(_refCtrl,
                hint: 'docker.io/library/redis:7.4-alpine or ghcr.io/...'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                'alpine:3.20',
                'nginx:1.27-alpine',
                'postgres:17-alpine',
                'redis:7.4-alpine',
                'ollama/ollama:latest',
              ]
                  .map((preset) => ActionChip(
                        label: Text(preset,
                            style: TextStyle(
                                fontSize: 11, color: FyrTheme.textColor)),
                        backgroundColor: FyrTheme.cardColor,
                        onPressed: () => setState(() => _refCtrl.text = preset),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: FyrTheme.textColorMuted)),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: FyrTheme.accentColor,
            foregroundColor: FyrTheme.getContrastingColor(FyrTheme.accentColor),
          ),
          onPressed: () {
            ctrl.pullImage(_refCtrl.text);
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.download_rounded, size: 16),
          label: const Text('Pull Image'),
        ),
      ],
    );
  }
}

class BuildImageDialog extends StatefulWidget {
  const BuildImageDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<PodsController>(),
        child: const BuildImageDialog(),
      ),
    );
  }

  @override
  State<BuildImageDialog> createState() => _BuildImageDialogState();
}

class _BuildImageDialogState extends State<BuildImageDialog> {
  final TextEditingController _tagCtrl =
      TextEditingController(text: 'localhost/fyr-microservice:1.0.0');
  final TextEditingController _fileCtrl = TextEditingController(
    text: 'FROM alpine:3.20\n'
        'RUN apk add --no-cache ca-certificates curl\n'
        'WORKDIR /app\n'
        'EXPOSE 8080\n'
        'CMD ["/bin/sh", "-c", "httpd -f -p 8080"]',
  );

  @override
  void dispose() {
    _tagCtrl.dispose();
    _fileCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<PodsController>();
    return AlertDialog(
      backgroundColor: FyrTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: FyrTheme.dividerColor),
      ),
      title: Row(
        children: [
          Icon(Icons.construction_rounded,
              color: FyrTheme.accentColor, size: 20),
          const SizedBox(width: 8),
          Text(
            'Build Image from Containerfile',
            style: GoogleFonts.outfit(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: FyrTheme.textColor,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabel('Target Image Tag (-t)'),
            _textField(_tagCtrl),
            const SizedBox(height: 10),
            _fieldLabel('Containerfile / Dockerfile'),
            _textField(_fileCtrl, maxLines: 7, monospace: true),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: FyrTheme.textColorMuted)),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: FyrTheme.accentColor,
            foregroundColor: FyrTheme.getContrastingColor(FyrTheme.accentColor),
          ),
          onPressed: () {
            ctrl.buildImage(
              tag: _tagCtrl.text,
              containerfile: _fileCtrl.text,
            );
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.build_circle_outlined, size: 16),
          label: const Text('Build OCI Image'),
        ),
      ],
    );
  }
}

class PlayKubeDialog extends StatefulWidget {
  const PlayKubeDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<PodsController>(),
        child: const PlayKubeDialog(),
      ),
    );
  }

  @override
  State<PlayKubeDialog> createState() => _PlayKubeDialogState();
}

class _PlayKubeDialogState extends State<PlayKubeDialog> {
  final TextEditingController _yamlCtrl = TextEditingController(
    text: 'apiVersion: v1\n'
        'kind: Pod\n'
        'metadata:\n'
        '  name: fyr-edge-analytics\n'
        'spec:\n'
        '  containers:\n'
        '    - name: vector-agent\n'
        '      image: timberio/vector:0.42.0-alpine\n'
        '      ports:\n'
        '        - containerPort: 8686\n'
        '          hostPort: 8686\n',
  );

  @override
  void dispose() {
    _yamlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<PodsController>();
    return AlertDialog(
      backgroundColor: FyrTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: FyrTheme.dividerColor),
      ),
      title: Row(
        children: [
          Icon(Icons.hub_rounded, color: FyrTheme.accentColor, size: 20),
          const SizedBox(width: 8),
          Text(
            'Play Kubernetes YAML (podman kube play)',
            style: GoogleFonts.outfit(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: FyrTheme.textColor,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabel('Pod or Deployment Manifest (YAML)'),
            _textField(_yamlCtrl, maxLines: 11, monospace: true),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: FyrTheme.textColorMuted)),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: FyrTheme.accentColor,
            foregroundColor: FyrTheme.getContrastingColor(FyrTheme.accentColor),
          ),
          onPressed: () {
            ctrl.deployKubeYaml(_yamlCtrl.text);
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.play_arrow_rounded, size: 16),
          label: const Text('Deploy Pod'),
        ),
      ],
    );
  }
}

Widget _fieldLabel(String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: FyrTheme.textColorMuted,
      ),
    ),
  );
}

InputDecoration _inputDecoration({String? hint}) {
  return InputDecoration(
    hintText: hint,
    hintStyle:
        TextStyle(fontSize: 12, color: FyrTheme.textColorMuted.withValues(alpha: 0.5)),
    filled: true,
    fillColor: FyrTheme.cardColor,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: FyrTheme.dividerColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: FyrTheme.dividerColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: FyrTheme.accentColor),
    ),
  );
}

Widget _textField(
  TextEditingController controller, {
  String? hint,
  int maxLines = 1,
  bool monospace = false,
}) {
  return TextField(
    controller: controller,
    maxLines: maxLines,
    style: monospace
        ? GoogleFonts.jetBrainsMono(fontSize: 12, color: FyrTheme.textColor)
        : TextStyle(fontSize: 12.5, color: FyrTheme.textColor),
    decoration: _inputDecoration(hint: hint),
  );
}
