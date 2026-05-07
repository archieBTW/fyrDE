import 'dart:io';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import '../fyr_theme.dart';

class CropRect {
  final int x;
  final int y;
  final int width;
  final int height;

  CropRect({required this.x, required this.y, required this.width, required this.height});
}

class CircleCropDialog extends StatefulWidget {
  final String imagePath;

  const CircleCropDialog({super.key, required this.imagePath});

  @override
  State<CircleCropDialog> createState() => _CircleCropDialogState();
}

class _CircleCropDialogState extends State<CircleCropDialog> {
  final TransformationController _controller = TransformationController();
  Size? _imageSize;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  Future<void> _loadImageSize() async {
    final image = FileImage(File(widget.imagePath));
    final ImageStream stream = image.resolve(ImageConfiguration.empty);
    stream.addListener(ImageStreamListener((ImageInfo info, bool _) {
      if (mounted) {
        setState(() {
          _imageSize = Size(info.image.width.toDouble(), info.image.height.toDouble());
          _loading = false;
        });
      }
    }));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: FyrTheme.accentColor)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
          final double cropSize = viewportSize.width < viewportSize.height 
              ? viewportSize.width * 0.8 
              : viewportSize.height * 0.8;
          
          return Stack(
            children: [
              // Image behind
              Positioned.fill(
                child: InteractiveViewer(
                  transformationController: _controller,
                  boundaryMargin: EdgeInsets.all(viewportSize.width),
                  minScale: 0.1,
                  maxScale: 5.0,
                  child: Center(
                    child: Image.file(
                      File(widget.imagePath),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              
              // Overlay (Darkened outside circle)
              IgnorePointer(
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.black.withOpacity(0.7),
                    BlendMode.srcOut,
                  ),
                  child: Stack(
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          color: Colors.black,
                          backgroundBlendMode: BlendMode.dstOut,
                        ),
                      ),
                      Center(
                        child: Container(
                          width: cropSize,
                          height: cropSize,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Border for the circle
              Center(
                child: Container(
                  width: cropSize,
                  height: cropSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: FyrTheme.accentColor, width: 2),
                  ),
                ),
              ),
              
              // App Bar UI
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black54, Colors.transparent],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(
                        'Crop Avatar',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          final Matrix4 matrix = _controller.value;
                          
                          // Image dimensions
                          double imgW = _imageSize!.width;
                          double imgH = _imageSize!.height;
                          
                          // How the image is fitted in the Center/Contain
                          double fitScale = 1.0;
                          if (imgW / imgH > viewportSize.width / viewportSize.height) {
                            fitScale = viewportSize.width / imgW;
                          } else {
                            fitScale = viewportSize.height / imgH;
                          }
                          
                          double displayedW = imgW * fitScale;
                          double displayedH = imgH * fitScale;
                          
                          // The center of the crop circle in UI coordinates
                          double circleCenterX = viewportSize.width / 2;
                          double circleCenterY = viewportSize.height / 2;
                          
                          // The top-left of the crop square in UI coordinates
                          double cropLeft = circleCenterX - cropSize / 2;
                          double cropTop = circleCenterY - cropSize / 2;
                          
                          final inverted = Matrix4.inverted(matrix);
                          final p1 = inverted.transform3(Vector3(cropLeft, cropTop, 0));
                          final p2 = inverted.transform3(Vector3(cropLeft + cropSize, cropTop + cropSize, 0));
                          
                          double childCenterX = viewportSize.width / 2;
                          double childCenterY = viewportSize.height / 2;
                          
                          double imgLeftInChild = childCenterX - displayedW / 2;
                          double imgTopInChild = childCenterY - displayedH / 2;
                          
                          double cropX = (p1.x - imgLeftInChild) / fitScale;
                          double cropY = (p1.y - imgTopInChild) / fitScale;
                          double cropW = (p2.x - p1.x) / fitScale;
                          double cropH = (p2.y - p1.y) / fitScale;
                          
                          Navigator.pop(context, CropRect(
                            x: cropX.round(),
                            y: cropY.round(),
                            width: cropW.round(),
                            height: cropH.round(),
                          ));
                        },
                        child: Text(
                          'SAVE',
                          style: TextStyle(
                            color: FyrTheme.accentColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Helper text
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Pinch to zoom • Drag to move',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

