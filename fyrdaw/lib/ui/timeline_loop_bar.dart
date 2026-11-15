import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

enum _LoopDragMode { none, move, resizeLeft, resizeRight }

/// Interactive timeline loop region bar supporting toggling loop playback,
/// clicking & dragging the bar to relocate the loop window, and generous
/// left/right edge handles to resize [loopStart] and [loopEnd].
class TimelineLoopBar extends StatefulWidget {
  final double loopStart;
  final double loopEnd;
  final bool isLooping;
  final double zoomX;
  final double beatWidth;
  final bool snapToGrid;
  final double snapResolution;
  final Color accentColor;
  final Color handleColor;
  final double maxTimelineUnits;
  final VoidCallback onToggleLoop;
  final void Function(double newStart, double newEnd) onLoopRangeChanged;
  final VoidCallback? onDragStart;

  const TimelineLoopBar({
    super.key,
    required this.loopStart,
    required this.loopEnd,
    required this.isLooping,
    required this.zoomX,
    required this.beatWidth,
    required this.snapToGrid,
    required this.snapResolution,
    required this.accentColor,
    required this.handleColor,
    this.maxTimelineUnits = 2000.0,
    required this.onToggleLoop,
    required this.onLoopRangeChanged,
    this.onDragStart,
  });

  @override
  State<TimelineLoopBar> createState() => _TimelineLoopBarState();
}

class _TimelineLoopBarState extends State<TimelineLoopBar> {
  static const double _barHeight = 12.0;
  static const double _hitHeight = 18.0;
  static const double _handleHitWidth = 22.0;

  static const Set<PointerDeviceKind> _pointerDevices = {
    PointerDeviceKind.mouse,
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };

  _LoopDragMode _dragMode = _LoopDragMode.none;
  _LoopDragMode _hoverMode = _LoopDragMode.none;
  double _originStart = 0.0;
  double _originEnd = 0.0;
  double _dragStartGlobalX = 0.0;

  double get _minLoopSpan {
    if (widget.snapToGrid && widget.snapResolution > 0.0) {
      return widget.snapResolution;
    }
    return max(10.0, widget.beatWidth * 0.25);
  }

  double _maybeSnap(double value) {
    if (!widget.snapToGrid || widget.snapResolution <= 0.0) return value;
    return (value / widget.snapResolution).round() * widget.snapResolution;
  }

  void _beginDrag(_LoopDragMode mode, double globalX) {
    widget.onDragStart?.call();
    setState(() {
      _dragMode = mode;
      _originStart = widget.loopStart;
      _originEnd = widget.loopEnd;
      _dragStartGlobalX = globalX;
    });
  }

  void _endDrag() {
    if (_dragMode != _LoopDragMode.none) {
      setState(() => _dragMode = _LoopDragMode.none);
    }
  }

  void _updateDrag(double globalX) {
    if (_dragMode == _LoopDragMode.none) return;
    final double deltaTimeline =
        (globalX - _dragStartGlobalX) / max(0.01, widget.zoomX);
    final double minSpan = _minLoopSpan;

    switch (_dragMode) {
      case _LoopDragMode.move:
        final double span = (_originEnd - _originStart).clamp(
          minSpan,
          widget.maxTimelineUnits,
        );
        final double maxStart = max(0.0, widget.maxTimelineUnits - span);
        final double rawStart = (_originStart + deltaTimeline).clamp(
          0.0,
          maxStart,
        );
        final double snappedStart = _maybeSnap(rawStart).clamp(0.0, maxStart);
        widget.onLoopRangeChanged(snappedStart, snappedStart + span);
        break;
      case _LoopDragMode.resizeLeft:
        final double maxStart = max(0.0, _originEnd - minSpan);
        final double rawStart = (_originStart + deltaTimeline).clamp(
          0.0,
          maxStart,
        );
        final double snappedStart = _maybeSnap(rawStart).clamp(0.0, maxStart);
        widget.onLoopRangeChanged(snappedStart, _originEnd);
        break;
      case _LoopDragMode.resizeRight:
        final double minEnd = _originStart + minSpan;
        final double rawEnd = (_originEnd + deltaTimeline).clamp(
          minEnd,
          widget.maxTimelineUnits,
        );
        final double snappedEnd = _maybeSnap(rawEnd).clamp(
          minEnd,
          widget.maxTimelineUnits,
        );
        widget.onLoopRangeChanged(_originStart, snappedEnd);
        break;
      case _LoopDragMode.none:
        break;
    }
  }

  Widget _buildEdgeHandle({
    required Key handleKey,
    required _LoopDragMode mode,
    required double targetLineOffsetInHandle,
  }) {
    final bool active = _dragMode == mode || _hoverMode == mode;
    final Color capColor = active
        ? Colors.white
        : (widget.isLooping ? widget.handleColor : Colors.white70);

    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hoverMode = mode),
      onExit: (_) {
        if (_hoverMode == mode) {
          setState(() => _hoverMode = _LoopDragMode.none);
        }
      },
      child: GestureDetector(
        key: handleKey,
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        supportedDevices: _pointerDevices,
        onHorizontalDragStart: (d) => _beginDrag(mode, d.globalPosition.dx),
        onHorizontalDragUpdate: (d) => _updateDrag(d.globalPosition.dx),
        onHorizontalDragEnd: (_) => _endDrag(),
        onHorizontalDragCancel: _endDrag,
        child: SizedBox(
          width: _handleHitWidth,
          height: _hitHeight,
          child: Stack(
            children: [
              Positioned(
                left: (targetLineOffsetInHandle - (active ? 2.5 : 1.5)).clamp(
                  0.0,
                  _handleHitWidth - 4.0,
                ),
                top: 0,
                child: Container(
                  width: active ? 5.0 : 3.5,
                  height: _barHeight + 2.0,
                  decoration: BoxDecoration(
                    color: capColor,
                    borderRadius: BorderRadius.circular(1.5),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: widget.accentColor.withValues(alpha: 0.7),
                              blurRadius: 4,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double startPx = widget.loopStart * widget.zoomX;
    final double endPx = max(startPx + 14.0, widget.loopEnd * widget.zoomX);
    final double barWidth = endPx - startPx;

    // Keep left handle fully inside [0..) even when loopStart == 0.
    final double leftHandleLeft = max(0.0, startPx - 8.0);
    final double leftLineOffset = startPx - leftHandleLeft;

    // Right handle sits at endPx, nudged right of left handle if the bar is tiny.
    final double minRightLeft = leftHandleLeft + (_handleHitWidth * 0.55);
    final double rightHandleLeft = max(minRightLeft, endPx - 12.0);
    final double rightLineOffset = (endPx - rightHandleLeft).clamp(
      2.0,
      _handleHitWidth - 4.0,
    );

    final bool moveActive =
        _dragMode == _LoopDragMode.move || _hoverMode == _LoopDragMode.move;
    final Color barColor = widget.isLooping
        ? (moveActive
              ? Color.lerp(widget.accentColor, Colors.white, 0.2)!
              : widget.accentColor)
        : Colors.grey.withValues(alpha: moveActive ? 0.72 : 0.5);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (widget.isLooping)
          Positioned(
            left: startPx,
            width: barWidth,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                color: widget.accentColor.withValues(alpha: 0.16),
              ),
            ),
          ),
        Positioned(
          left: startPx,
          width: barWidth,
          top: 0,
          height: _hitHeight,
          child: MouseRegion(
            cursor: _dragMode == _LoopDragMode.move
                ? SystemMouseCursors.grabbing
                : SystemMouseCursors.grab,
            onEnter: (_) => setState(() => _hoverMode = _LoopDragMode.move),
            onExit: (_) {
              if (_hoverMode == _LoopDragMode.move) {
                setState(() => _hoverMode = _LoopDragMode.none);
              }
            },
            child: GestureDetector(
              key: const Key('loop_bar_body'),
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              supportedDevices: _pointerDevices,
              onTap: widget.onToggleLoop,
              onHorizontalDragStart: (d) =>
                  _beginDrag(_LoopDragMode.move, d.globalPosition.dx),
              onHorizontalDragUpdate: (d) => _updateDrag(d.globalPosition.dx),
              onHorizontalDragEnd: (_) => _endDrag(),
              onHorizontalDragCancel: _endDrag,
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  height: _barHeight,
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: moveActive
                          ? Colors.white.withValues(alpha: 0.75)
                          : Colors.black.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: barWidth >= 48
                      ? Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              3,
                              (_) => Container(
                                width: 3,
                                height: 3,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(
                                    alpha: widget.isLooping ? 0.85 : 0.6,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: leftHandleLeft,
          top: 0,
          child: _buildEdgeHandle(
            handleKey: const Key('loop_handle_left'),
            mode: _LoopDragMode.resizeLeft,
            targetLineOffsetInHandle: leftLineOffset,
          ),
        ),
        Positioned(
          left: rightHandleLeft,
          top: 0,
          child: _buildEdgeHandle(
            handleKey: const Key('loop_handle_right'),
            mode: _LoopDragMode.resizeRight,
            targetLineOffsetInHandle: rightLineOffset,
          ),
        ),
      ],
    );
  }
}
