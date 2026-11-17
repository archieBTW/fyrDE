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

  static const _resizeThickness = 5.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        const _ResizeHandle(edge: _ResizeZoneEdge.left, size: _resizeThickness),
        const _ResizeHandle(
            edge: _ResizeZoneEdge.right, size: _resizeThickness),
        const _ResizeHandle(edge: _ResizeZoneEdge.top, size: _resizeThickness),
        const _ResizeHandle(
            edge: _ResizeZoneEdge.bottom, size: _resizeThickness),
        const _ResizeHandle(
            edge: _ResizeZoneEdge.topLeft, size: _resizeThickness),
        const _ResizeHandle(
            edge: _ResizeZoneEdge.topRight, size: _resizeThickness),
        const _ResizeHandle(
            edge: _ResizeZoneEdge.bottomLeft, size: _resizeThickness),
        const _ResizeHandle(
            edge: _ResizeZoneEdge.bottomRight, size: _resizeThickness),
      ],
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  final _ResizeZoneEdge edge;
  final double size;

  const _ResizeHandle({required this.edge, required this.size});

  SystemMouseCursor get cursor {
    switch (edge) {
      case _ResizeZoneEdge.left:
      case _ResizeZoneEdge.right:
        return SystemMouseCursors.resizeLeftRight;
      case _ResizeZoneEdge.top:
      case _ResizeZoneEdge.bottom:
        return SystemMouseCursors.resizeUpDown;
      case _ResizeZoneEdge.topLeft:
      case _ResizeZoneEdge.bottomRight:
        return SystemMouseCursors.resizeUpLeftDownRight;
      case _ResizeZoneEdge.topRight:
      case _ResizeZoneEdge.bottomLeft:
        return SystemMouseCursors.resizeUpRightDownLeft;
    }
  }

  ResizeEdge get resizeEdge {
    switch (edge) {
      case _ResizeZoneEdge.left:
        return ResizeEdge.left;
      case _ResizeZoneEdge.right:
        return ResizeEdge.right;
      case _ResizeZoneEdge.top:
        return ResizeEdge.top;
      case _ResizeZoneEdge.bottom:
        return ResizeEdge.bottom;
      case _ResizeZoneEdge.topLeft:
        return ResizeEdge.topLeft;
      case _ResizeZoneEdge.topRight:
        return ResizeEdge.topRight;
      case _ResizeZoneEdge.bottomLeft:
        return ResizeEdge.bottomLeft;
      case _ResizeZoneEdge.bottomRight:
        return ResizeEdge.bottomRight;
    }
  }

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
