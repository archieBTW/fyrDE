import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'fyr_theme.dart';

late List<CameraDescription> _cameras;

void main() async {
  FyrTheme.initialize();
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  
  try {
    _cameras = await availableCameras();
  } catch (e) {
    _cameras = [];
    debugPrint('Error fetching cameras: $e');
  }

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1000, 750),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const FyrCameraApp());
}

class FyrCameraApp extends StatelessWidget {
  const FyrCameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        FyrTheme.accentColorNotifier,
        FyrTheme.themeModeNotifier,
      ]),
      builder: (context, child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'FyrCamera',
        themeMode: FyrTheme.themeMode,
        darkTheme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: Colors.transparent,
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'San Francisco'),
          colorScheme: ColorScheme.dark(
            primary: FyrTheme.accentColor,
            secondary: FyrTheme.accentColor,
          ),
        ),
        theme: ThemeData.light().copyWith(
          scaffoldBackgroundColor: Colors.transparent,
          textTheme: ThemeData.light().textTheme.apply(fontFamily: 'San Francisco'),
          colorScheme: ColorScheme.light(
            primary: FyrTheme.accentColor,
            secondary: FyrTheme.accentColor,
          ),
        ),
        home: const CameraScreen(),
      ),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? controller;
  bool _isRecording = false;
  bool _isStoppingRecording = false;
  int _selectedCameraIndex = 0;
  String? _lastCapturedPath;
  bool _isPhotoMode = true;
  String? _initializationError;
  bool _isInitializing = false;

  @override
  void initState() {
    super.initState();
    if (_cameras.isNotEmpty) {
      _initializeCamera(_cameras[_selectedCameraIndex]);
    } else {
      _initializationError = 'No cameras found on this device.';
    }
  }

  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    if (_isInitializing) return;
    setState(() {
      _isInitializing = true;
      _initializationError = null;
    });

    try {
      // Attempt 1: Medium Resolution with Audio
      bool success = await _tryInitialize(cameraDescription, ResolutionPreset.medium, true);
      
      if (!success && mounted) {
        // Attempt 2: Medium Resolution without Audio
        success = await _tryInitialize(cameraDescription, ResolutionPreset.medium, false);
      }
      
      if (!success && mounted) {
        // Attempt 3: Low Resolution without Audio
        success = await _tryInitialize(cameraDescription, ResolutionPreset.low, false);
      }

      if (!success && mounted) {
        setState(() {
          _initializationError = 'Camera initialization failed. Please check your connection.';
        });
      }
    } finally {
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  Future<bool> _tryInitialize(CameraDescription description, ResolutionPreset preset, bool audio) async {
    final CameraController cameraController = CameraController(
      description,
      preset,
      enableAudio: audio,
    );

    final oldController = controller;
    controller = null;
    if (oldController != null) {
      await oldController.dispose();
    }

    try {
      await cameraController.initialize();
      if (mounted) {
        setState(() {
          controller = cameraController;
          _initializationError = null;
        });
        return true;
      } else {
        cameraController.dispose();
        return false;
      }
    } catch (e) {
      debugPrint('Initialization failed (preset: $preset, audio: $audio): $e');
      Future.delayed(const Duration(milliseconds: 100), () {
        try {
          cameraController.dispose();
        } catch (_) {}
      });
      return false;
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (controller == null || !controller!.value.isInitialized) return;

    try {
      final XFile file = await controller!.takePicture();
      
      final String? home = Platform.environment['HOME'];
      if (home == null) throw Exception('Could not find HOME directory');
      
      final String picturesDir = p.join(home, 'Pictures', 'Camera');
      final directory = Directory(picturesDir);
      
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      
      final String timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final String newPath = p.join(directory.path, 'FYR_IMG_$timestamp.jpg');
      
      await File(file.path).copy(newPath);
      
      setState(() {
        _lastCapturedPath = newPath;
      });
      
      _showToast('Picture saved to Pictures/Camera');
    } catch (e) {
      debugPrint('Error taking picture: $e');
      _showToast('Error taking picture: $e');
    }
  }

  Future<void> _toggleRecording() async {
    if (controller == null || !controller!.value.isInitialized || _isStoppingRecording) return;

    if (_isRecording) {
      setState(() => _isStoppingRecording = true);
      try {
        final XFile file = await controller!.stopVideoRecording();
        
        // Give GStreamer a moment to fully release the file lock
        await Future.delayed(const Duration(milliseconds: 500));
        
        final String? home = Platform.environment['HOME'];
        if (home == null) throw Exception('Could find HOME directory');
        
        final String videosDir = p.join(home, 'Videos', 'Camera');
        final directory = Directory(videosDir);
        
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
        
        final String timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
        final String newPath = p.join(directory.path, 'FYR_VID_$timestamp.mp4');
        
        final sourceFile = File(file.path);
        if (await sourceFile.exists()) {
          await sourceFile.copy(newPath);
          await sourceFile.delete();
        }

        setState(() {
          _isRecording = false;
          _isStoppingRecording = false;
          _lastCapturedPath = newPath;
        });
        
        _showToast('Video saved to Videos/Camera');

        // Force re-initialize to unfreeze the GStreamer pipeline
        if (mounted) {
          _initializeCamera(_cameras[_selectedCameraIndex]);
        }
      } catch (e) {
        debugPrint('Error stopping recording: $e');
        setState(() => _isStoppingRecording = false);
        _showToast('Error stopping recording: $e');
      }
    } else {
      try {
        await controller!.startVideoRecording();
        setState(() {
          _isRecording = true;
        });
      } catch (e) {
        debugPrint('Error starting recording: $e');
        _showToast('Error starting recording: $e');
      }
    }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: FyrTheme.accentColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildTrafficLight(Color color, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black26, width: 0.5),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = FyrTheme.isDark;
    final Color bgColor = isDark ? Colors.black : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: Colors.black,
          child: Stack(
            children: [
              // Full Window Camera Feed
              Positioned.fill(
                child: controller == null || !controller!.value.isInitialized || _initializationError != null || _isInitializing
                    ? Container(
                        color: bgColor,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isInitializing)
                                CircularProgressIndicator(
                                  color: FyrTheme.accentColor,
                                )
                              else
                                Icon(
                                  _initializationError != null ? Icons.error_outline : Icons.camera_alt,
                                  size: 48,
                                  color: _initializationError != null ? Colors.redAccent : textColor.withOpacity(0.2),
                                ),
                              const SizedBox(height: 24),
                              if (_initializationError != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 32),
                                  child: Text(
                                    _initializationError!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: textColor.withOpacity(0.5)),
                                  ),
                                ),
                              if (_initializationError != null) ...[
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () {
                                    if (_cameras.isNotEmpty) {
                                      _initializeCamera(_cameras[_selectedCameraIndex]);
                                    } else {
                                      availableCameras().then((val) {
                                        setState(() => _cameras = val);
                                        if (_cameras.isNotEmpty) _initializeCamera(_cameras[_selectedCameraIndex]);
                                      });
                                    }
                                  },
                                  child: const Text('Retry'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: controller!.value.previewSize?.width ?? 1,
                                height: controller!.value.previewSize?.height ?? 1,
                                child: CameraPreview(controller!),
                              ),
                            );
                          },
                        ),
                      ),
              ),
              
              // Processing Indicator (Stop recording)
              if (_isStoppingRecording)
                Positioned.fill(
                  child: Container(
                    color: Colors.black54,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: FyrTheme.accentColor),
                          const SizedBox(height: 16),
                          const Text('Saving video...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),

              // Recording Indicator Overlay
              if (_isRecording && !_isStoppingRecording)
                Positioned(
                  top: 64,
                  right: 24,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _RecordingDot(),
                        const SizedBox(width: 8),
                        const Text(
                          'REC',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),

              // Window Bar Overlay
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: DragToMoveArea(
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.4),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        _buildTrafficLight(Colors.redAccent, () => windowManager.close()),
                        const SizedBox(width: 8),
                        _buildTrafficLight(Colors.orangeAccent, () => windowManager.minimize()),
                        const SizedBox(width: 8),
                        _buildTrafficLight(Colors.greenAccent, () async {
                          if (await windowManager.isMaximized()) {
                            windowManager.unmaximize();
                          } else {
                            windowManager.maximize();
                          }
                        }),
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Bottom Controls Overlay
              Positioned(
                bottom: 24,
                left: 24,
                right: 24,
                child: AnimatedOpacity(
                  opacity: _isInitializing || _isStoppingRecording ? 0.3 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    height: 100,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Last Capture Thumbnail
                        GestureDetector(
                          onTap: () {
                            // Could open file here
                          },
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white24),
                              image: _lastCapturedPath != null && !_lastCapturedPath!.endsWith('.mp4')
                                  ? DecorationImage(
                                      image: FileImage(File(_lastCapturedPath!)),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: _lastCapturedPath == null
                                ? const Icon(Icons.photo_library_outlined, color: Colors.white54, size: 24)
                                : (_lastCapturedPath!.endsWith('.mp4') 
                                    ? const Icon(Icons.play_circle_fill, color: Colors.white70, size: 30)
                                    : null),
                          ),
                        ),
                        const SizedBox(width: 32),
                        // Mode & Capture
                        Row(
                          children: [
                            // Mode Switcher
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.4),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Row(
                                children: [
                                  _buildModeButton(true, Icons.camera_alt_rounded),
                                  _buildModeButton(false, Icons.videocam_rounded),
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            // Capture Button
                            GestureDetector(
                              onTap: _isStoppingRecording || _isInitializing ? null : (_isPhotoMode ? _takePicture : _toggleRecording),
                              child: Container(
                                width: 64,
                                height: 64,
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  decoration: BoxDecoration(
                                    color: _isPhotoMode 
                                        ? Colors.white 
                                        : (_isRecording ? Colors.redAccent : Colors.white),
                                    shape: _isRecording ? BoxShape.rectangle : BoxShape.circle,
                                    borderRadius: _isRecording ? BorderRadius.circular(8) : null,
                                  ),
                                  child: _isStoppingRecording 
                                    ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)))
                                    : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 82), // Balance the thumbnail
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeButton(bool isPhoto, IconData icon) {
    final bool isSelected = _isPhotoMode == isPhoto;
    return GestureDetector(
      onTap: () {
        if (_isRecording || _isStoppingRecording || _isInitializing) return;
        setState(() {
          _isPhotoMode = isPhoto;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          icon,
          color: isSelected ? Colors.black : Colors.white54,
          size: 20,
        ),
      ),
    );
  }
}

class _RecordingDot extends StatefulWidget {
  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animationController,
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
