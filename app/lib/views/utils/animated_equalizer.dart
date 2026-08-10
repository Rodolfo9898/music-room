import 'dart:math' as math;

import 'package:flutter/material.dart';

/// An animated drop-in replacement for [Icons.graphic_eq_rounded].
///
/// Renders a row of vertical bars (mimicking a graphic equalizer) that
/// continuously grow and shrink with staggered phases while [isPlaying] is
/// true. When [isPlaying] is false, the bars freeze at a fixed, still
/// pattern instead of animating.
class AnimatedEqualizer extends StatefulWidget {
  final bool isPlaying;
  final Color color;
  final double size;
  final int barCount;

  const AnimatedEqualizer({
    super.key,
    required this.isPlaying,
    this.color = Colors.white,
    this.size = 24,
    this.barCount = 4,
  });

  @override
  State<AnimatedEqualizer> createState() => _AnimatedEqualizerState();
}

class _AnimatedEqualizerState extends State<AnimatedEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Fixed still pattern used whenever playback is paused (relative bar
  // heights, from 0 to 1).
  static const List<double> _stillPattern = [0.35, 0.75, 0.5, 0.62];

  // Per-bar phase offsets (in the 0..1 cycle) so bars don't move in lockstep.
  static const List<double> _phaseOffsets = [0.0, 0.2, 0.45, 0.7];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedEqualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
      } else {
        _controller.stop();
        _controller.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _barHeightFactor(int index) {
    if (!widget.isPlaying) {
      return _stillPattern[index % _stillPattern.length];
    }
    final phase = _phaseOffsets[index % _phaseOffsets.length];
    final t = (_controller.value + phase) % 1.0;
    // Smooth sine oscillation between a minimum and maximum height.
    final wave = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    return 0.25 + 0.75 * wave;
  }

  @override
  Widget build(BuildContext context) {
    final barWidth = widget.size / (widget.barCount * 2 - 1.5);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(widget.barCount, (index) {
              final heightFactor = _barHeightFactor(index);
              return Container(
                width: barWidth,
                height: widget.size * heightFactor,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(barWidth / 2),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
