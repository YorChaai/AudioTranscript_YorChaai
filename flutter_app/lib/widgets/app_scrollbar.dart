import 'dart:async';
import 'package:flutter/material.dart';

class AppScrollbar extends StatefulWidget {
  final Widget child;
  final ScrollController? controller;
  final Axis scrollDirection;
  final ScrollbarOrientation? scrollbarOrientation;
  final bool thumbVisibility;
  final double thickness;
  final double interactiveThickness;
  final Radius radius;
  final bool interactive;
  final ScrollNotificationPredicate? notificationPredicate;

  const AppScrollbar({
    super.key,
    required this.child,
    this.controller,
    this.scrollDirection = Axis.vertical,
    this.scrollbarOrientation,
    this.thumbVisibility = false,
    this.thickness = 8.0,
    this.interactiveThickness = 16.0,
    this.radius = const Radius.circular(4),
    this.interactive = true,
    this.notificationPredicate,
  });

  @override
  State<AppScrollbar> createState() => _AppScrollbarState();
}

class _AppScrollbarState extends State<AppScrollbar> {
  Timer? _scrollTimer;
  bool _isHoldingTrack = false;
  DateTime? _startHoldTime;
  double _currentSpeed = 1000.0;
  static const double _baseSpeed = 1000.0; 

  void _startScrolling(Offset localPosition) {
    if (_scrollTimer != null) return;

    _isHoldingTrack = true;
    _startHoldTime = DateTime.now();
    _currentSpeed = _baseSpeed;

    _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted || !_isHoldingTrack || widget.controller == null || !widget.controller!.hasClients) {
        timer.cancel();
        _scrollTimer = null;
        return;
      }

      // Akselerasi Kecepatan: 1000 -> 2000 -> 4000 -> 8000 setiap 1.5 detik
      if (_startHoldTime != null) {
        final elapsed = DateTime.now().difference(_startHoldTime!).inMilliseconds;
        if (elapsed > 4500) {
          _currentSpeed = 8000.0;
        } else if (elapsed > 3000) {
          _currentSpeed = 4000.0;
        } else if (elapsed > 1500) {
          _currentSpeed = 2000.0;
        } else {
          _currentSpeed = _baseSpeed;
        }
      }

      final position = widget.controller!.position;
      final maxScroll = position.maxScrollExtent;
      final viewport = position.viewportDimension;
      final totalContent = maxScroll + viewport;

      if (totalContent <= viewport) return;

      final trackLength = viewport;
      
      double relativeTouch;
      if (widget.scrollDirection == Axis.vertical) {
        relativeTouch = localPosition.dy / trackLength;
      } else {
        relativeTouch = localPosition.dx / trackLength;
      }
      relativeTouch = relativeTouch.clamp(0.0, 1.0);

      final targetOffset = relativeTouch * totalContent - (viewport / 2);
      final clampedTarget = targetOffset.clamp(0.0, maxScroll);

      final currentOffset = widget.controller!.offset;
      final distance = (clampedTarget - currentOffset).abs();

      if (distance < 5.0) return;

      // Gunakan _currentSpeed yang sudah diakselerasi
      final step = _currentSpeed * (16 / 1000); 
      final newOffset = currentOffset < clampedTarget
          ? (currentOffset + step).clamp(0.0, clampedTarget)
          : (currentOffset - step).clamp(clampedTarget, currentOffset);

      widget.controller!.jumpTo(newOffset);
    });
  }

  void _stopScrolling() {
    _isHoldingTrack = false;
    _startHoldTime = null;
    _currentSpeed = _baseSpeed;
    _scrollTimer?.cancel();
    _scrollTimer = null;
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        if (widget.controller == null || !widget.controller!.hasClients) return;

        final renderBox = context.findRenderObject() as RenderBox;
        final localPos = renderBox.globalToLocal(event.position);
        final size = renderBox.size;

        bool inScrollbarArea = false;
        const hitSlop = 32.0;

        if (widget.scrollDirection == Axis.vertical) {
          if (widget.scrollbarOrientation == ScrollbarOrientation.left) {
            inScrollbarArea = localPos.dx <= hitSlop;
          } else {
            inScrollbarArea = localPos.dx >= (size.width - hitSlop);
          }
        } else {
          if (widget.scrollbarOrientation == ScrollbarOrientation.top) {
            inScrollbarArea = localPos.dy <= hitSlop;
          } else {
            inScrollbarArea = localPos.dy >= (size.height - hitSlop);
          }
        }

        if (!inScrollbarArea) return;

        final position = widget.controller!.position;
        final maxScroll = position.maxScrollExtent;
        final viewport = position.viewportDimension;
        final currentScroll = position.pixels;
        final totalContent = maxScroll + viewport;

        if (totalContent > 0) {
          double actualThumbLength = (viewport / totalContent) * viewport;
          if (actualThumbLength < 18.0) actualThumbLength = 18.0;

          final double fraction = maxScroll > 0 ? (currentScroll / maxScroll).clamp(0.0, 1.0) : 0.0;
          final double thumbOffset = fraction * (viewport - actualThumbLength);

          double touchCoord = widget.scrollDirection == Axis.vertical ? localPos.dy : localPos.dx;

          if (touchCoord >= thumbOffset - 30 && touchCoord <= thumbOffset + actualThumbLength + 30) {
            return;
          }
        }

        _startScrolling(localPos);
      },
      onPointerUp: (_) => _stopScrolling(),
      onPointerCancel: (_) => _stopScrolling(),
      child: RawScrollbar(
        controller: widget.controller,
        thumbVisibility: widget.thumbVisibility,
        trackVisibility: false,
        thickness: 8.0,
        radius: widget.radius,
        interactive: true,
        notificationPredicate: widget.notificationPredicate ?? defaultScrollNotificationPredicate,
        scrollbarOrientation: widget.scrollbarOrientation,
        thumbColor: const Color(0xFF2596BE),
        child: widget.child,
      ),
    );
  }
}
