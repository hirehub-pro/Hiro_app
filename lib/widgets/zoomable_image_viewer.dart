import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class ZoomableImageViewer extends StatefulWidget {
  final String imageUrl;
  final String? localPath;
  final bool enableHero;
  final String? heroTag;
  final bool enableSwipeDismiss;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onZoomStateChanged;
  final ValueChanged<int>? onEdgePageRequest;

  const ZoomableImageViewer({
    super.key,
    required this.imageUrl,
    this.localPath,
    this.enableHero = false,
    this.heroTag,
    this.enableSwipeDismiss = false,
    this.onTap,
    this.onZoomStateChanged,
    this.onEdgePageRequest,
  });

  @override
  State<ZoomableImageViewer> createState() => _ZoomableImageViewerState();
}

class _ZoomableImageViewerState extends State<ZoomableImageViewer>
    with TickerProviderStateMixin {
  static const double _minScale = 1;
  static const double _maxScale = 4;
  static const double _doubleTapScale = 2.6;
  static const double _zoomEpsilon = 1.02;
  static const double _dismissVelocity = 980;
  static const double _pinchSoftClampFactor = 0.22;
  static const double _edgeSwipeTrigger = 32;
  static const double _edgeTolerance = 6;

  final TransformationController _transformationController =
      TransformationController();
  TapDownDetails? _doubleTapDetails;
  AnimationController? _zoomAnimationController;
  AnimationController? _reboundController;

  Animation<Matrix4>? _zoomAnimation;
  bool _isZoomed = false;
  bool _lastReportedZoomed = false;
  double _verticalDragOffset = 0;
  Animation<double>? _reboundAnimation;
  bool _isPinching = false;
  double _horizontalEdgeSwipeProgress = 0;
  bool _edgePageTriggered = false;
  Size _viewportSize = Size.zero;
  final Set<int> _activePointerIds = <int>{};

  @override
  void initState() {
    super.initState();
    _zoomAnimationController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          final animation = _zoomAnimation;
          if (animation == null) return;
          _transformationController.value = animation.value;
        });
    _reboundController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 200),
        )..addListener(() {
          final animation = _reboundAnimation;
          if (animation == null || !mounted) return;
          setState(() {
            _verticalDragOffset = animation.value;
          });
        });
  }

  @override
  void dispose() {
    _zoomAnimationController?.dispose();
    _reboundController?.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _animateTo(Matrix4 target) {
    final controller = _zoomAnimationController;
    if (controller == null) {
      _transformationController.value = target;
      return;
    }

    _zoomAnimation = Matrix4Tween(
      begin: _transformationController.value,
      end: target,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOutCubic));

    controller
      ..stop()
      ..reset()
      ..forward();
  }

  void _handleDoubleTap(Size viewportSize) {
    final tapPosition = _doubleTapDetails?.localPosition;
    final currentScale = _transformationController.value.getMaxScaleOnAxis();

    if (tapPosition == null || currentScale > 1.05) {
      _animateTo(Matrix4.identity());
      setState(() => _isZoomed = false);
      _reportZoomStateIfChanged();
      return;
    }

    final scenePoint = _transformationController.toScene(tapPosition);
    final dx = viewportSize.width / 2 - (scenePoint.dx * _doubleTapScale);
    final dy = viewportSize.height / 2 - (scenePoint.dy * _doubleTapScale);

    final zoomedMatrix = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(_doubleTapScale, _doubleTapScale, 1, 1);

    _animateTo(zoomedMatrix);
    setState(() => _isZoomed = true);
    _reportZoomStateIfChanged();
  }

  void _handleInteractionEnd(ScaleEndDetails details) {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    _isPinching = _activePointerIds.length > 1;
    _horizontalEdgeSwipeProgress = 0;
    _edgePageTriggered = false;

    if (scale <= _zoomEpsilon) {
      _transformationController.value = Matrix4.identity();
      if (mounted) {
        setState(() => _isZoomed = false);
      }
      _reportZoomStateIfChanged();
      return;
    }

    if (scale > _maxScale) {
      final clampedMatrix = Matrix4.copy(_transformationController.value)
        ..scaleByDouble(_maxScale / scale, _maxScale / scale, 1, 1);
      _animateTo(clampedMatrix);
      if (mounted) {
        setState(() => _isZoomed = true);
      }
      _reportZoomStateIfChanged();
      return;
    }

    if (mounted) {
      setState(() => _isZoomed = scale > _zoomEpsilon);
    }
    _reportZoomStateIfChanged();
  }

  void _handleInteractionUpdate(ScaleUpdateDetails details) {
    _isPinching = details.pointerCount > 1 || _activePointerIds.length > 1;

    if (_isPinching) {
      _applySoftScaleBounds(details.localFocalPoint);
    }

    final scale = _transformationController.value.getMaxScaleOnAxis();
    final nextZoomed = scale > _zoomEpsilon;
    if (nextZoomed != _isZoomed && mounted) {
      setState(() => _isZoomed = nextZoomed);
    }

    _maybeRequestEdgePage(details);
    _reportZoomStateIfChanged();
  }

  void _reportZoomStateIfChanged() {
    if (_isZoomed == _lastReportedZoomed) return;
    _lastReportedZoomed = _isZoomed;
    widget.onZoomStateChanged?.call(_isZoomed);
  }

  void _maybeRequestEdgePage(ScaleUpdateDetails details) {
    if (_edgePageTriggered ||
        !_isZoomed ||
        details.pointerCount > 1 ||
        widget.onEdgePageRequest == null ||
        _viewportSize == Size.zero) {
      return;
    }

    final scale = _transformationController.value.getMaxScaleOnAxis();
    if (scale <= _zoomEpsilon) return;

    final translationX = _transformationController.value.storage[12];
    final minTranslateX = _viewportSize.width * (1 - scale);
    final atLeftEdge = translationX >= -_edgeTolerance;
    final atRightEdge = translationX <= (minTranslateX + _edgeTolerance);
    final fingerDx = details.focalPointDelta.dx;

    final wantsPrevious = atLeftEdge && fingerDx > 0;
    final wantsNext = atRightEdge && fingerDx < 0;

    if (wantsPrevious || wantsNext) {
      _horizontalEdgeSwipeProgress += fingerDx.abs();
    } else {
      _horizontalEdgeSwipeProgress = 0;
    }

    if (_horizontalEdgeSwipeProgress < _edgeSwipeTrigger) return;

    _edgePageTriggered = true;
    _horizontalEdgeSwipeProgress = 0;
    widget.onEdgePageRequest?.call(wantsPrevious ? -1 : 1);
  }

  void _applySoftScaleBounds(Offset localFocalPoint) {
    final matrix = _transformationController.value;
    final scale = matrix.getMaxScaleOnAxis();

    double? desiredScale;
    if (scale > _maxScale) {
      desiredScale = _maxScale + ((scale - _maxScale) * _pinchSoftClampFactor);
    } else if (scale < _minScale) {
      desiredScale = _minScale - ((_minScale - scale) * _pinchSoftClampFactor);
      desiredScale = desiredScale.clamp(_minScale * 0.92, _minScale).toDouble();
    }

    if (desiredScale == null || (desiredScale - scale).abs() < 0.0001) return;

    final focalScene = _transformationController.toScene(localFocalPoint);
    final scaleDelta = desiredScale / scale;
    final adjusted = Matrix4.copy(matrix)
      ..translateByDouble(focalScene.dx, focalScene.dy, 0, 1)
      ..scaleByDouble(scaleDelta, scaleDelta, 1, 1)
      ..translateByDouble(-focalScene.dx, -focalScene.dy, 0, 1);
    _transformationController.value = adjusted;
  }

  double _dismissThreshold(Size viewportSize) =>
      (viewportSize.height * 0.18).clamp(110, 220).toDouble();

  void _animateDragBack() {
    final controller = _reboundController;
    if (controller == null) {
      if (mounted) setState(() => _verticalDragOffset = 0);
      return;
    }

    _reboundAnimation = Tween<double>(
      begin: _verticalDragOffset,
      end: 0,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOutCubic));

    controller
      ..stop()
      ..reset()
      ..forward();
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details, Size viewportSize) {
    if (!widget.enableSwipeDismiss || _isZoomed || _isPinching) return;
    _reboundController?.stop();

    final threshold = _dismissThreshold(viewportSize);
    final nextOffset = (_verticalDragOffset + details.delta.dy).clamp(
      -threshold * 0.45,
      threshold * 1.7,
    );

    setState(() {
      _verticalDragOffset = nextOffset;
    });
  }

  void _handleVerticalDragEnd(DragEndDetails details, Size viewportSize) {
    if (!widget.enableSwipeDismiss || _isZoomed || _isPinching) return;

    final velocity = details.primaryVelocity ?? 0;
    final shouldDismiss =
        _verticalDragOffset > _dismissThreshold(viewportSize) ||
        velocity > _dismissVelocity;
    if (shouldDismiss) {
      Navigator.of(context).maybePop();
      return;
    }

    _animateDragBack();
  }

  @override
  Widget build(BuildContext context) {
    final hasLocal = widget.localPath != null && widget.localPath!.isNotEmpty;

    Widget image = hasLocal
        ? Image.file(
            File(widget.localPath!),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          )
        : CachedNetworkImage(
            imageUrl: widget.imageUrl,
            fit: BoxFit.contain,
            fadeInDuration: const Duration(milliseconds: 180),
            placeholder: (context, url) => const _ImageLoadingPlaceholder(),
            errorWidget: (context, url, error) =>
                const _ImageErrorPlaceholder(),
          );

    if (widget.enableHero) {
      image = Hero(tag: widget.heroTag ?? widget.imageUrl, child: image);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        _viewportSize = viewportSize;
        final dismissThreshold = _dismissThreshold(viewportSize);
        final dragProgress = (_verticalDragOffset.abs() / dismissThreshold)
            .clamp(0.0, 1.0);
        final dragOpacity = widget.enableSwipeDismiss
            ? (1 - (dragProgress * 0.62)).clamp(0.38, 1.0)
            : 1.0;
        final dragScale = widget.enableSwipeDismiss && !_isZoomed
            ? (1 - (dragProgress * 0.08)).clamp(0.9, 1.0)
            : 1.0;
        final canDismissByDrag =
            widget.enableSwipeDismiss &&
            !_isZoomed &&
            !_isPinching &&
            _activePointerIds.length <= 1;

        return Listener(
          onPointerDown: (event) {
            _activePointerIds.add(event.pointer);
            if (_activePointerIds.length > 1) {
              _isPinching = true;
              if (_verticalDragOffset != 0) {
                _animateDragBack();
              }
            }
          },
          onPointerUp: (event) {
            _activePointerIds.remove(event.pointer);
            if (_activePointerIds.length <= 1) {
              _isPinching = false;
            }
          },
          onPointerCancel: (event) {
            _activePointerIds.remove(event.pointer);
            if (_activePointerIds.length <= 1) {
              _isPinching = false;
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onTap,
            onDoubleTapDown: (details) => _doubleTapDetails = details,
            onDoubleTap: () => _handleDoubleTap(viewportSize),
            onVerticalDragUpdate: canDismissByDrag
                ? (details) => _handleVerticalDragUpdate(details, viewportSize)
                : null,
            onVerticalDragEnd: canDismissByDrag
                ? (details) => _handleVerticalDragEnd(details, viewportSize)
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              color: Colors.black.withValues(alpha: dragOpacity),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Transform.translate(
                    offset: Offset(0, _verticalDragOffset),
                    child: Transform.scale(
                      scale: dragScale,
                      child: InteractiveViewer(
                        transformationController: _transformationController,
                        minScale: _minScale,
                        maxScale: _maxScale,
                        panEnabled: _isZoomed,
                        scaleEnabled: true,
                        interactionEndFrictionCoefficient: 0.00008,
                        constrained: false,
                        boundaryMargin: const EdgeInsets.all(260),
                        clipBehavior: Clip.none,
                        onInteractionUpdate: _handleInteractionUpdate,
                        onInteractionEnd: _handleInteractionEnd,
                        child: SizedBox(
                          width: viewportSize.width,
                          height: viewportSize.height,
                          child: Center(
                            child: Semantics(
                              image: true,
                              label: 'Zoomable image preview',
                              child: image,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _ViewerHintOverlay(
                    dragProgress: dragProgress,
                    showDismissHint: widget.enableSwipeDismiss && !_isZoomed,
                    isZoomed: _isZoomed,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ImageLoadingPlaceholder extends StatelessWidget {
  const _ImageLoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1220), Color(0xFF111B2F)],
        ),
      ),
      child: const Center(
        child: SizedBox(
          width: 34,
          height: 34,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _ImageErrorPlaceholder extends StatelessWidget {
  const _ImageErrorPlaceholder();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1220), Color(0xFF111B2F)],
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_rounded, color: Colors.white70, size: 52),
            SizedBox(height: 10),
            Text(
              'Unable to load image',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerHintOverlay extends StatelessWidget {
  final double dragProgress;
  final bool showDismissHint;
  final bool isZoomed;

  const _ViewerHintOverlay({
    required this.dragProgress,
    required this.showDismissHint,
    required this.isZoomed,
  });

  @override
  Widget build(BuildContext context) {
    final topOpacity = isZoomed ? 0.12 : 0.18;
    final hintOpacity = showDismissHint
        ? (1 - dragProgress).clamp(0.0, 1.0).toDouble()
        : 0.0;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: 92,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: topOpacity),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          if (hintOpacity > 0)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: hintOpacity,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.34),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: const Text(
                      'Swipe down to close · Double tap to zoom',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
