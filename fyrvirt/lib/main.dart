import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as p;
import 'fyr_theme.dart';

enum ResizeZoneEdge {
  left,
  right,
  top,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

class ResizableWindow extends StatelessWidget {
  final Widget child;
  const ResizableWindow({super.key, required this.child});

  static const _resizeThickness = 6.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        _ResizeHandle(edge: ResizeZoneEdge.left, size: _resizeThickness),
        _ResizeHandle(edge: ResizeZoneEdge.right, size: _resizeThickness),
        _ResizeHandle(edge: ResizeZoneEdge.top, size: _resizeThickness),
        _ResizeHandle(edge: ResizeZoneEdge.bottom, size: _resizeThickness),
        _ResizeHandle(edge: ResizeZoneEdge.topLeft, size: _resizeThickness),
        _ResizeHandle(edge: ResizeZoneEdge.topRight, size: _resizeThickness),
        _ResizeHandle(edge: ResizeZoneEdge.bottomLeft, size: _resizeThickness),
        _ResizeHandle(edge: ResizeZoneEdge.bottomRight, size: _resizeThickness),
      ],
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  final ResizeZoneEdge edge;
  final double size;

  const _ResizeHandle({required this.edge, required this.size});

  SystemMouseCursor get cursor {
    switch (edge) {
      case ResizeZoneEdge.left:
      case ResizeZoneEdge.right:
        return SystemMouseCursors.resizeLeftRight;
      case ResizeZoneEdge.top:
      case ResizeZoneEdge.bottom:
        return SystemMouseCursors.resizeUpDown;
      case ResizeZoneEdge.topLeft:
      case ResizeZoneEdge.bottomRight:
        return SystemMouseCursors.resizeUpLeftDownRight;
      case ResizeZoneEdge.topRight:
      case ResizeZoneEdge.bottomLeft:
        return SystemMouseCursors.resizeUpRightDownLeft;
    }
  }

  ResizeEdge get resizeEdge {
    switch (edge) {
      case ResizeZoneEdge.left: return ResizeEdge.left;
      case ResizeZoneEdge.right: return ResizeEdge.right;
      case ResizeZoneEdge.top: return ResizeEdge.top;
      case ResizeZoneEdge.bottom: return ResizeEdge.bottom;
      case ResizeZoneEdge.topLeft: return ResizeEdge.topLeft;
      case ResizeZoneEdge.topRight: return ResizeEdge.topRight;
      case ResizeZoneEdge.bottomLeft: return ResizeEdge.bottomLeft;
      case ResizeZoneEdge.bottomRight: return ResizeEdge.bottomRight;
    }
  }

  @override
  Widget build(BuildContext context) {
    Alignment alignment;
    double? width;
    double? height;

    switch (edge) {
      case ResizeZoneEdge.left: alignment = Alignment.centerLeft; width = size; height = double.infinity; break;
      case ResizeZoneEdge.right: alignment = Alignment.centerRight; width = size; height = double.infinity; break;
      case ResizeZoneEdge.top: alignment = Alignment.topCenter; width = double.infinity; height = size; break;
      case ResizeZoneEdge.bottom: alignment = Alignment.bottomCenter; width = double.infinity; height = size; break;
      case ResizeZoneEdge.topLeft: alignment = Alignment.topLeft; width = size; height = size; break;
      case ResizeZoneEdge.topRight: alignment = Alignment.topRight; width = size; height = size; break;
      case ResizeZoneEdge.bottomLeft: alignment = Alignment.bottomLeft; width = size; height = size; break;
      case ResizeZoneEdge.bottomRight: alignment = Alignment.bottomRight; width = size; height = size; break;
    }

    return Align(
      alignment: alignment,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (_) => windowManager.startResizing(resizeEdge),
          child: SizedBox(width: width, height: height),
        ),
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FyrTheme.initialize();
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1100, 800),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(const FyrVirtApp());
}

class FyrVirtApp extends StatelessWidget {
  const FyrVirtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([FyrTheme.themeModeNotifier, FyrTheme.accentColorNotifier]),
      builder: (_, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.light().copyWith(
            useMaterial3: true,
            primaryColor: FyrTheme.accentColor,
            colorScheme: ColorScheme.light(primary: FyrTheme.accentColor),
          ),
          darkTheme: ThemeData.dark().copyWith(
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFF2A282C),
            primaryColor: FyrTheme.accentColor,
            colorScheme: ColorScheme.dark(primary: FyrTheme.accentColor),
          ),
          themeMode: FyrTheme.themeMode,
          home: const FyrVirt(),
        );
      },
    );
  }
}

class VMInfo {
  final String id;
  final String name;
  final String state;

  VMInfo({required this.id, required this.name, required this.state});

  bool get isRunning => state.toLowerCase().contains('running');
}

class FyrVirt extends StatefulWidget {
  const FyrVirt({super.key});

  @override
  State<FyrVirt> createState() => _FyrVirtState();
}

class _FyrVirtState extends State<FyrVirt> {
  List<VMInfo> vms = [];
  bool isLoading = true;
  String selectedCategory = 'All';
  Timer? _refreshTimer;
  Timer? _screenshotTimer;
  final Map<String, String> _screenshots = {};
  final String _cachePath = '${Platform.environment['HOME']}/.cache/fyrvirt';

  @override
  void initState() {
    super.initState();
    _initCache();
    refreshVMs();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => refreshVMs());
    _screenshotTimer = Timer.periodic(const Duration(seconds: 3), (_) => _takeScreenshots());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _screenshotTimer?.cancel();
    super.dispose();
  }

  Future<void> _initCache() async {
    final dir = Directory(_cachePath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  Future<void> _takeScreenshots() async {
    for (var vm in vms) {
      if (vm.isRunning) {
        final filePath = '$_cachePath/${vm.name}.png';
        try {
          await Process.run('virsh', ['-c', 'qemu:///session', 'screenshot', vm.name, '--file', filePath]);
          if (File(filePath).existsSync()) {
            setState(() {
              _screenshots[vm.name] = filePath;
            });
          }
        } catch (e) {
          print('Error taking screenshot for ${vm.name}: $e');
        }
      }
    }
  }

  Future<void> refreshVMs() async {
    try {
      final result = await Process.run('virsh', ['-c', 'qemu:///session', 'list', '--all']);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        List<VMInfo> newVMs = [];
        bool startParsing = false;
        for (var line in lines) {
          line = line.trim();
          if (line.startsWith('---')) {
            startParsing = true;
            continue;
          }
          if (startParsing && line.isNotEmpty) {
            final parts = line.split(RegExp(r'\s{2,}'));
            if (parts.length >= 3) {
              newVMs.add(VMInfo(
                id: parts[0].trim(),
                name: parts[1].trim(),
                state: parts[2].trim(),
              ));
            }
          }
        }
        setState(() {
          vms = newVMs;
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error refreshing VMs: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> vmAction(String name, String action) async {
    await Process.run('virsh', ['-c', 'qemu:///session', action, name]);
    refreshVMs();
  }

  Future<void> launchVM(String name, {bool fullscreen = false}) async {
    try {
      List<String> args = ['-c', 'qemu:///session', '--attach'];
      if (fullscreen) args.add('-f');
      args.add(name);
      await Process.start('virt-viewer', args);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error launching virt-viewer: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _showCreateVMDialog() async {
    final nameController = TextEditingController();
    final ramController = TextEditingController(text: '2048');
    final cpuController = TextEditingController(text: '2');
    final diskController = TextEditingController(text: '20');
    final isoController = TextEditingController();
    final descController = TextEditingController();
    String firmware = 'BIOS';
    bool tpm = false;
    bool autostart = false;
    String network = 'NAT';

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF2A282C),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Create New Virtual Machine', style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDialogField('VM Name', nameController),
                    const SizedBox(height: 12),
                    _buildDialogField('Description', descController),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _buildDialogField('RAM (MiB)', ramController, isNumber: true)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildDialogField('CPU Cores', cpuController, isNumber: true)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildDialogField('Disk Size (GiB)', diskController, isNumber: true),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _buildDialogField('ISO Path', isoController)),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(Icons.folder_open, color: FyrTheme.accentColor),
                          onPressed: () async {
                            final result = await Process.run('fyrfiles', ['--picker']);
                            if (result.exitCode == 0) {
                              isoController.text = result.stdout.toString().trim();
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Divider(color: Colors.white10),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Firmware', style: TextStyle(color: Colors.white70)),
                        const Spacer(),
                        DropdownButton<String>(
                          value: firmware,
                          dropdownColor: const Color(0xFF2A282C),
                          underline: Container(),
                          style: TextStyle(color: FyrTheme.accentColor),
                          items: ['BIOS', 'UEFI'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                          onChanged: (val) => setDialogState(() => firmware = val!),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Text('Network', style: TextStyle(color: Colors.white70)),
                        const Spacer(),
                        DropdownButton<String>(
                          value: network,
                          dropdownColor: const Color(0xFF2A282C),
                          underline: Container(),
                          style: TextStyle(color: FyrTheme.accentColor),
                          items: ['NAT', 'Bridge'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                          onChanged: (val) => setDialogState(() => network = val!),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      title: const Text('TPM 2.0 Security', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      value: tpm,
                      activeColor: FyrTheme.accentColor,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) => setDialogState(() => tpm = val),
                    ),
                    SwitchListTile(
                      title: const Text('Autostart on Boot', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      value: autostart,
                      activeColor: FyrTheme.accentColor,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (val) => setDialogState(() => autostart = val),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: TextStyle(color: FyrTheme.textColorMuted)),
              ),
              ElevatedButton(
                onPressed: () async {
                  final name = nameController.text;
                  final ram = ramController.text;
                  final cpus = cpuController.text;
                  final disk = diskController.text;
                  final iso = isoController.text;
                  final desc = descController.text;

                  if (name.isEmpty || iso.isEmpty) return;

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Creating VM...')));

                  try {
                    List<String> args = [
                      '--name', name,
                      '--ram', ram,
                      '--vcpus', cpus,
                      '--disk', 'size=$disk,bus=virtio',
                      '--cdrom', iso,
                      '--os-variant', 'auto',
                      '--graphics', 'spice,listen=none',
                      '--connect', 'qemu:///session',
                      '--noautoconsole'
                    ];

                    if (firmware == 'UEFI') {
                      args.addAll(['--boot', 'uefi']);
                    }

                    if (tpm) {
                      args.addAll(['--tpm', 'backend.type=emulator,model=tpm-tis,version=2.0']);
                    }

                    if (desc.isNotEmpty) {
                      args.addAll(['--description', desc]);
                    }

                    if (network == 'Bridge') {
                      args.addAll(['--network', 'bridge=br0']);
                    } else {
                      args.addAll(['--network', 'network=default']);
                    }

                    final result = await Process.run('virt-install', args);
                    
                    if (result.exitCode != 0) {
                      throw Exception(result.stderr.toString().trim());
                    }

                    if (autostart) {
                      await Process.run('virsh', ['-c', 'qemu:///session', 'autostart', name]);
                    }
                    
                    refreshVMs();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error creating VM: $e'), backgroundColor: Colors.redAccent),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: FyrTheme.accentColor),
                child: const Text('Create VM', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    );
  }

  Widget _buildDialogField(String label, TextEditingController controller, {bool isNumber = false}) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: FyrTheme.accentColor, fontSize: 12),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: FyrTheme.dividerColor)),
        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: FyrTheme.accentColor)),
      ),
    );
  }

  Future<void> _showSettings(VMInfo vm) async {
    final result = await Process.run('virsh', ['-c', 'qemu:///session', 'dominfo', vm.name]);
    if (result.exitCode != 0) return;

    final lines = result.stdout.toString().split('\n');
    String cpus = '1';
    String memory = '1024';

    for (var line in lines) {
      if (line.startsWith('CPU(s):')) {
        cpus = line.split(':')[1].trim();
      } else if (line.startsWith('Max memory:')) {
        memory = line.split(':')[1].trim().split(' ')[0];
        memory = (int.parse(memory) ~/ 1024).toString();
      }
    }

    // Check for Autostart
    final autoResult = await Process.run('virsh', ['-c', 'qemu:///session', 'dominfo', vm.name]);
    bool autostart = autoResult.stdout.toString().contains('Autostart:       enable');

    // Check for Description
    final descResult = await Process.run('virsh', ['-c', 'qemu:///session', 'desc', vm.name]);
    String description = descResult.stdout.toString().trim();

    // Check for 3D acceleration
    final xmlResult = await Process.run('virsh', ['-c', 'qemu:///session', 'dumxml', vm.name]);
    bool accel3d = xmlResult.stdout.toString().contains("accel3d='yes'");

    final cpuController = TextEditingController(text: cpus);
    final memController = TextEditingController(text: memory);
    final descController = TextEditingController(text: description);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF2A282C),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Settings: ${vm.name}', style: const TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogField('Description', descController),
                const SizedBox(height: 16),
                _buildDialogField('CPU Cores', cpuController, isNumber: true),
                const SizedBox(height: 16),
                _buildDialogField('Memory (MiB)', memController, isNumber: true),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Autostart on Boot', style: TextStyle(color: Colors.white, fontSize: 14)),
                    const Spacer(),
                    Switch(
                      value: autostart,
                      activeColor: FyrTheme.accentColor,
                      onChanged: (val) {
                        setDialogState(() {
                          autostart = val;
                        });
                      },
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('GPU 3D Acceleration', style: TextStyle(color: Colors.white, fontSize: 14)),
                    const Spacer(),
                    Switch(
                      value: accel3d,
                      activeColor: FyrTheme.accentColor,
                      onChanged: (val) {
                        setDialogState(() {
                          accel3d = val;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Note: Changes will take effect on next boot.',
                  style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: TextStyle(color: FyrTheme.textColorMuted)),
              ),
              ElevatedButton(
                onPressed: () async {
                  final newCpus = cpuController.text;
                  final newMem = memController.text;
                  
                  try {
                    await Process.run('virsh', ['-c', 'qemu:///session', 'setvcpus', vm.name, newCpus, '--config', '--maximum']);
                    await Process.run('virsh', ['-c', 'qemu:///session', 'setvcpus', vm.name, newCpus, '--config']);
                    await Process.run('virsh', ['-c', 'qemu:///session', 'setmaxmem', vm.name, '${newMem}MiB', '--config']);
                    await Process.run('virsh', ['-c', 'qemu:///session', 'setmem', vm.name, '${newMem}MiB', '--config']);
                    
                    // Update Autostart
                    await Process.run('virsh', [
                      '-c', 'qemu:///session',
                      'autostart',
                      vm.name,
                      if (!autostart) '--disable'
                    ]);

                    // Update Description
                    await Process.run('virsh', ['-c', 'qemu:///session', 'desc', vm.name, descController.text]);

                    // Apply 3D Accel using virt-xml
                    await Process.run('virt-xml', [
                      '--connect', 'qemu:///session',
                      vm.name,
                      '--edit',
                      '--video', 'model.type=virtio,accel3d=${accel3d ? 'yes' : 'no'}',
                      '--edit',
                      '--graphics', 'spice,gl.enable=${accel3d ? 'yes' : 'no'}'
                    ]);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error saving settings: $e'), backgroundColor: Colors.redAccent),
                      );
                    }
                  }

                  if (context.mounted) Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: FyrTheme.accentColor),
                child: const Text('Save Changes', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredVMs = vms.where((vm) {
      if (selectedCategory == 'Running') return vm.isRunning;
      if (selectedCategory == 'Stopped') return !vm.isRunning;
      return true;
    }).toList();

    return ResizableWindow(
      child: Scaffold(
        backgroundColor: FyrTheme.bgColor,
        body: Column(
          children: [
            // Title Bar
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: () => windowManager.maximize(),
              child: Container(
                height: 55,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => windowManager.close(),
                      child: Icon(Icons.circle, color: Colors.red.shade300, size: 16),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => Process.run('swaymsg', ['[pid="$pid"] move scratchpad']),
                      child: Icon(Icons.circle, color: Colors.amber.shade300, size: 16),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => Process.run('swaymsg', ['[pid="$pid"] fullscreen toggle']),
                      child: Icon(Icons.circle, color: Colors.green.shade300, size: 16),
                    ),
                    const SizedBox(width: 24),
                    Text(
                      'FyrVirt',
                      style: TextStyle(
                        color: FyrTheme.textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.add_circle_outline, color: FyrTheme.accentColor, size: 22),
                      onPressed: _showCreateVMDialog,
                      tooltip: 'Create New VM',
                    ),
                    IconButton(
                      icon: Icon(Icons.refresh, color: FyrTheme.textColor, size: 20),
                      onPressed: refreshVMs,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  // Sidebar
                  Container(
                    width: 200,
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(color: FyrTheme.dividerColor),
                      ),
                    ),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        _buildSidebarItem('All', Icons.dns_outlined),
                        _buildSidebarItem('Running', Icons.play_circle_outline),
                        _buildSidebarItem('Stopped', Icons.stop),
                      ],
                    ),
                  ),
                  // Content
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : filteredVMs.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'No virtual machines found',
                                      style: TextStyle(color: FyrTheme.textColorMuted),
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton.icon(
                                      onPressed: _showCreateVMDialog,
                                      icon: const Icon(Icons.add, color: Colors.white),
                                      label: const Text('Create your first VM', style: TextStyle(color: Colors.white)),
                                      style: ElevatedButton.styleFrom(backgroundColor: FyrTheme.accentColor),
                                    ),
                                  ],
                                ),
                              )
                            : GridView.builder(
                                padding: const EdgeInsets.all(24),
                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 400,
                                  childAspectRatio: 0.9,
                                  crossAxisSpacing: 24,
                                  mainAxisSpacing: 24,
                                ),
                                itemCount: filteredVMs.length,
                                itemBuilder: (context, index) {
                                  final vm = filteredVMs[index];
                                  return _buildVMCard(vm);
                                },
                              ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(String title, IconData icon) {
    final isSelected = selectedCategory == title;
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? FyrTheme.accentColor : FyrTheme.textColorMuted,
        size: 20,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? FyrTheme.textColor : FyrTheme.textColorMuted,
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      onTap: () => setState(() => selectedCategory = title),
      dense: true,
      selected: isSelected,
      selectedTileColor: FyrTheme.hoverColor,
    );
  }

  Widget _buildVMCard(VMInfo vm) {
    final screenshot = _screenshots[vm.name];
    return Card(
      color: FyrTheme.cardColor,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: vm.isRunning ? FyrTheme.accentColor.withOpacity(0.5) : FyrTheme.dividerColor,
          width: vm.isRunning ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          // Preview Area
          Expanded(
            child: InkWell(
              onTap: () => launchVM(vm.name),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (vm.isRunning && screenshot != null)
                    Image.file(
                      File(screenshot),
                      fit: BoxFit.cover,
                      key: ValueKey('${vm.name}_${DateTime.now().millisecondsSinceEpoch ~/ 3000}'),
                    )
                  else
                    Container(
                      color: Colors.black.withOpacity(0.2),
                      child: Center(
                        child: Icon(
                          Icons.computer,
                          color: FyrTheme.textColorMuted.withOpacity(0.3),
                          size: 64,
                        ),
                      ),
                    ),
                  if (vm.isRunning)
                    PositionImageOverlay(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'LIVE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Fullscreen button
                  if (vm.isRunning)
                    Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: IconButton(
                          icon: const Icon(Icons.fullscreen, color: Colors.white),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black.withOpacity(0.5),
                          ),
                          onPressed: () => launchVM(vm.name, fullscreen: true),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Info Area
          Container(
            padding: const EdgeInsets.all(16),
            color: FyrTheme.cardColor,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vm.name,
                        style: TextStyle(
                          color: FyrTheme.textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        vm.state.toUpperCase(),
                        style: TextStyle(
                          color: FyrTheme.textColorMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!vm.isRunning)
                  IconButton(
                    icon: Icon(Icons.play_arrow_rounded, color: FyrTheme.accentColor, size: 28),
                    onPressed: () => vmAction(vm.name, 'start'),
                    tooltip: 'Start',
                  ),
                if (vm.isRunning)
                  IconButton(
                    icon: const Icon(Icons.power_settings_new_rounded, color: Colors.redAccent, size: 28),
                    onPressed: () => vmAction(vm.name, 'destroy'),
                    tooltip: 'Force Stop',
                  ),
                IconButton(
                  icon: Icon(Icons.settings_outlined, color: FyrTheme.textColorMuted, size: 24),
                  onPressed: () => _showSettings(vm),
                  tooltip: 'Settings',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PositionImageOverlay extends StatelessWidget {
  final Widget child;
  const PositionImageOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      bottom: 12,
      child: child,
    );
  }
}
