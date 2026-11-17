import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

enum _ResizeZoneEdge {
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

  static const _thickness = 5.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        const _ResizeHandle(edge: _ResizeZoneEdge.left, size: _thickness),
        const _ResizeHandle(edge: _ResizeZoneEdge.right, size: _thickness),
        const _ResizeHandle(edge: _ResizeZoneEdge.top, size: _thickness),
        const _ResizeHandle(edge: _ResizeZoneEdge.bottom, size: _thickness),
        const _ResizeHandle(edge: _ResizeZoneEdge.topLeft, size: _thickness),
        const _ResizeHandle(edge: _ResizeZoneEdge.topRight, size: _thickness),
        const _ResizeHandle(edge: _ResizeZoneEdge.bottomLeft, size: _thickness),
        const _ResizeHandle(edge: _ResizeZoneEdge.bottomRight, size: _thickness),
      ],
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  final _ResizeZoneEdge edge;
  final double size;

  const _ResizeHandle({required this.edge, required this.size});

  SystemMouseCursor get cursor => switch (edge) {
        _ResizeZoneEdge.left || _ResizeZoneEdge.right => SystemMouseCursors.resizeLeftRight,
        _ResizeZoneEdge.top || _ResizeZoneEdge.bottom => SystemMouseCursors.resizeUpDown,
        _ResizeZoneEdge.topLeft || _ResizeZoneEdge.bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
        _ResizeZoneEdge.topRight || _ResizeZoneEdge.bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
      };

  ResizeEdge get resizeEdge => switch (edge) {
        _ResizeZoneEdge.left => ResizeEdge.left,
        _ResizeZoneEdge.right => ResizeEdge.right,
        _ResizeZoneEdge.top => ResizeEdge.top,
        _ResizeZoneEdge.bottom => ResizeEdge.bottom,
        _ResizeZoneEdge.topLeft => ResizeEdge.topLeft,
        _ResizeZoneEdge.topRight => ResizeEdge.topRight,
        _ResizeZoneEdge.bottomLeft => ResizeEdge.bottomLeft,
        _ResizeZoneEdge.bottomRight => ResizeEdge.bottomRight,
      };

  @override
  Widget build(BuildContext context) {
    Alignment alignment;
    double? width;
    double? height;

    switch (edge) {
      case _ResizeZoneEdge.left:
        alignment = Alignment.centerLeft;
        width = size;
        height = double.infinity;
        break;
      case _ResizeZoneEdge.right:
        alignment = Alignment.centerRight;
        width = size;
        height = double.infinity;
        break;
      case _ResizeZoneEdge.top:
        alignment = Alignment.topCenter;
        width = double.infinity;
        height = size;
        break;
      case _ResizeZoneEdge.bottom:
        alignment = Alignment.bottomCenter;
        width = double.infinity;
        height = size;
        break;
      case _ResizeZoneEdge.topLeft:
        alignment = Alignment.topLeft;
        width = size;
        height = size;
        break;
      case _ResizeZoneEdge.topRight:
        alignment = Alignment.topRight;
        width = size;
        height = size;
        break;
      case _ResizeZoneEdge.bottomLeft:
        alignment = Alignment.bottomLeft;
        width = size;
        height = size;
        break;
      case _ResizeZoneEdge.bottomRight:
        alignment = Alignment.bottomRight;
        width = size;
        height = size;
        break;
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
