import 'package:flutter/material.dart';

/// A lightweight placeholder with a soft, accessible shimmer effect.
class Skeleton extends StatefulWidget {
  final double? height;
  final double? width;
  final double borderRadius;

  const Skeleton({super.key, this.height, this.width, this.borderRadius = 12});

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _shimmerPosition;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    );
    _shimmerPosition = Tween<double>(begin: -1.25, end: 1.25).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final baseColor = isDark
        ? const Color(0xFF263548)
        : const Color(0xFFE8EFF6);
    final highlightColor = isDark
        ? const Color(0xFF3B4E64)
        : const Color(0xFFF8FBFE);
    final radius = BorderRadius.circular(widget.borderRadius);

    return RepaintBoundary(
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: radius,
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.white.withValues(alpha: 0.78),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.08 : 0.025),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: reduceMotion
                ? const SizedBox.expand()
                : LayoutBuilder(
                    builder: (context, constraints) {
                      return AnimatedBuilder(
                        animation: _shimmerPosition,
                        builder: (context, _) {
                          final sweepWidth = constraints.maxWidth * 0.72;
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              Transform.translate(
                                offset: Offset(
                                  _shimmerPosition.value *
                                      (constraints.maxWidth + sweepWidth),
                                  0,
                                ),
                                child: Transform.rotate(
                                  angle: -0.18,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      width: sweepWidth,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            highlightColor.withValues(alpha: 0),
                                            highlightColor.withValues(
                                              alpha: 0.72,
                                            ),
                                            highlightColor.withValues(alpha: 0),
                                          ],
                                          stops: const [0, 0.5, 1],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
