import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../utils/video_cache_manager.dart';

class CachedVideoPlayer extends StatefulWidget {
  final String url;
  final bool play;
  final Widget? thumbnail;
  final BoxFit fit;
  final bool showControls;
  final bool allowFullscreen;
  final bool isFullscreen;
  final double borderRadius;
  final double placeholderAspectRatio;
  final String? fullscreenTitle;
  final Duration? initialPosition;
  final bool? initialMuted;

  const CachedVideoPlayer({
    super.key,
    required this.url,
    this.play = false,
    this.thumbnail,
    this.fit = BoxFit.cover,
    this.showControls = true,
    this.allowFullscreen = true,
    this.isFullscreen = false,
    this.borderRadius = 0,
    this.placeholderAspectRatio = 16 / 9,
    this.fullscreenTitle,
    this.initialPosition,
    this.initialMuted,
  });

  @override
  State<CachedVideoPlayer> createState() => _CachedVideoPlayerState();
}

class _CachedVideoPlayerState extends State<CachedVideoPlayer>
    with AutomaticKeepAliveClientMixin {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isError = false;
  bool _showControls = false;
  bool _isMuted = false;
  Timer? _controlsTimer;
  StreamSubscription<void>? _stopPlaybackSubscription;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _stopPlaybackSubscription = VideoCacheManager.stopPlaybackStream.listen((
      _,
    ) {
      final controller = _controller;
      if (controller == null || !controller.value.isInitialized) return;
      if (controller.value.isPlaying) {
        controller.pause();
      }
      _controlsTimer?.cancel();
      if (mounted) {
        setState(() => _showControls = true);
      }
    });
    _initializeController();
  }

  Future<void> _initializeController() async {
    final currentUrl = widget.url;

    setState(() {
      _isInitialized = false;
      _isError = false;
      _showControls = !widget.play;
    });

    try {
      final fileInfo = await VideoCacheManager.instance.getFileFromCache(
        currentUrl,
      );
      File videoFile;

      if (fileInfo == null) {
        final file = await VideoCacheManager.instance.getSingleFile(currentUrl);
        videoFile = file;
      } else {
        videoFile = fileInfo.file;
      }

      final controller = VideoPlayerController.file(videoFile);
      await controller.initialize();
      await controller.setLooping(true);

      if (widget.initialPosition != null) {
        final safePosition = widget.initialPosition! > controller.value.duration
            ? controller.value.duration
            : widget.initialPosition!;
        await controller.seekTo(safePosition);
      }

      final muted = widget.initialMuted ?? _isMuted;
      await controller.setVolume(muted ? 0 : 1);

      if (!mounted || widget.url != currentUrl) {
        await controller.dispose();
        return;
      }

      final previousController = _controller;
      _controller = controller;
      await previousController?.dispose();

      if (widget.play) {
        await _controller!.play();
        _startControlsHideTimer();
      }

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isMuted = muted;
        });
      }
    } catch (e) {
      debugPrint("Video Cache Error: $e");
      if (mounted) setState(() => _isError = true);
    }
  }

  @override
  void didUpdateWidget(CachedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url) {
      _controlsTimer?.cancel();
      _controller?.dispose();
      _controller = null;
      _initializeController();
      return;
    }

    if (widget.play != oldWidget.play) {
      if (widget.play) {
        _controller?.play();
        _startControlsHideTimer();
      } else {
        _controller?.pause();
        _controlsTimer?.cancel();
        if (mounted) {
          setState(() => _showControls = true);
        }
      }
    }
  }

  void _togglePlayback() {
    final controller = _controller;
    if (controller == null) return;

    if (controller.value.position >= controller.value.duration &&
        controller.value.duration > Duration.zero) {
      controller.seekTo(Duration.zero);
    }

    if (controller.value.isPlaying) {
      controller.pause();
      _controlsTimer?.cancel();
      setState(() => _showControls = true);
    } else {
      controller.play();
      setState(() => _showControls = true);
      _startControlsHideTimer();
    }
  }

  Future<void> _seekRelative(Duration offset) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final duration = controller.value.duration;
    final position = controller.value.position;
    final target = position + offset;
    final clamped = target < Duration.zero
        ? Duration.zero
        : target > duration
        ? duration
        : target;
    await controller.seekTo(clamped);
    if (controller.value.isPlaying) {
      _startControlsHideTimer();
    }
  }

  Future<void> _seekTo(Duration position) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final duration = controller.value.duration;
    final clamped = position < Duration.zero
        ? Duration.zero
        : position > duration
        ? duration
        : position;
    await controller.seekTo(clamped);
    if (controller.value.isPlaying) {
      _startControlsHideTimer();
    }
  }

  Future<void> _toggleMute() async {
    final controller = _controller;
    if (controller == null) return;

    final nextMuted = !_isMuted;
    await controller.setVolume(nextMuted ? 0 : 1);
    if (mounted) {
      setState(() => _isMuted = nextMuted);
    }
    if (controller.value.isPlaying) {
      _startControlsHideTimer();
    }
  }

  void _toggleControlsVisibility() {
    if (!widget.showControls) return;

    final shouldShow = !_showControls;
    setState(() => _showControls = shouldShow);

    if (shouldShow && (_controller?.value.isPlaying ?? false)) {
      _startControlsHideTimer();
    } else {
      _controlsTimer?.cancel();
    }
  }

  void _startControlsHideTimer() {
    _controlsTimer?.cancel();
    if (!widget.showControls) return;
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || !(_controller?.value.isPlaying ?? false)) return;
      setState(() => _showControls = false);
    });
  }

  Future<void> _toggleFullscreen() async {
    final controller = _controller;
    if (controller == null) return;

    if (widget.isFullscreen) {
      Navigator.of(context).maybePop();
      return;
    }

    final wasPlaying = controller.value.isPlaying;
    final currentPosition = controller.value.position;

    await controller.pause();

    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _VideoPlayerFullscreenPage(
          url: widget.url,
          title: widget.fullscreenTitle,
          startAt: currentPosition,
          isMuted: _isMuted,
        ),
      ),
    );

    if (!mounted) return;

    await controller.seekTo(currentPosition);
    if (wasPlaying || widget.play) {
      await controller.play();
      _startControlsHideTimer();
    }
  }

  @override
  void dispose() {
    _stopPlaybackSubscription?.cancel();
    _controlsTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin

    if (_isError) {
      return _VideoFrame(
        aspectRatio: widget.placeholderAspectRatio,
        borderRadius: widget.borderRadius,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white70, size: 40),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _initializeController,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text(
                  'Retry',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return _VideoFrame(
        aspectRatio: widget.placeholderAspectRatio,
        borderRadius: widget.borderRadius,
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            if (widget.thumbnail != null) widget.thumbnail!,
            Container(color: Colors.black26),
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
        ),
      );
    }

    return _VideoFrame(
      aspectRatio: _controller!.value.aspectRatio,
      borderRadius: widget.borderRadius,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControlsVisibility,
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.bottomCenter,
          children: [
            FittedBox(
              fit: widget.fit,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            ),
            if (widget.showControls)
              _VideoControls(
                controller: _controller!,
                isVisible: _showControls || !_controller!.value.isPlaying,
                isMuted: _isMuted,
                onPlayPause: _togglePlayback,
                onSeekBack: () => _seekRelative(const Duration(seconds: -5)),
                onSeekForward: () => _seekRelative(const Duration(seconds: 5)),
                onSeekTo: _seekTo,
                onMuteToggle: _toggleMute,
                onFullscreenToggle: widget.allowFullscreen
                    ? _toggleFullscreen
                    : null,
                isFullscreen: widget.isFullscreen,
              ),
          ],
        ),
      ),
    );
  }
}

class _VideoFrame extends StatelessWidget {
  final double aspectRatio;
  final double borderRadius;
  final Widget child;

  const _VideoFrame({
    required this.aspectRatio,
    required this.borderRadius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final safeAspectRatio = aspectRatio > 0 ? aspectRatio : 16 / 9;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        color: Colors.black,
        child: AspectRatio(aspectRatio: safeAspectRatio, child: child),
      ),
    );
  }
}

class _VideoControls extends StatelessWidget {
  final VideoPlayerController controller;
  final bool isVisible;
  final bool isMuted;
  final VoidCallback onPlayPause;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekForward;
  final ValueChanged<Duration> onSeekTo;
  final VoidCallback onMuteToggle;
  final VoidCallback? onFullscreenToggle;
  final bool isFullscreen;

  const _VideoControls({
    required this.controller,
    required this.isVisible,
    required this.isMuted,
    required this.onPlayPause,
    required this.onSeekBack,
    required this.onSeekForward,
    required this.onSeekTo,
    required this.onMuteToggle,
    required this.onFullscreenToggle,
    required this.isFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, VideoPlayerValue value, child) {
        final isFinished =
            value.duration > Duration.zero &&
            value.position >= value.duration &&
            !value.isPlaying;

        return IgnorePointer(
          ignoring: !isVisible,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: isVisible ? 1 : 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x66000000),
                    Color(0x22000000),
                    Color(0x88000000),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SeekControlButton(
                          icon: Icons.replay_rounded,
                          directionLabel: '-5s',
                          onPressed: onSeekBack,
                        ),
                        const SizedBox(width: 12),
                        _ControlButton(
                          icon: isFinished
                              ? Icons.replay_rounded
                              : value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 34,
                          buttonSize: 64,
                          onPressed: onPlayPause,
                        ),
                        const SizedBox(width: 12),
                        _SeekControlButton(
                          icon: Icons.forward_rounded,
                          directionLabel: '+5s',
                          onPressed: onSeekForward,
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (onFullscreenToggle != null)
                          _ControlButton(
                            icon: isFullscreen
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                            onPressed: onFullscreenToggle!,
                          )
                        else
                          const SizedBox(width: 48, height: 48),
                        _ControlButton(
                          icon: isMuted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          onPressed: onMuteToggle,
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 10,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 7,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14,
                            ),
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: const Color(0x55FFFFFF),
                            thumbColor: Colors.white,
                            overlayColor: const Color(0x44FFFFFF),
                          ),
                          child: Slider(
                            min: 0,
                            max: value.duration.inMilliseconds > 0
                                ? value.duration.inMilliseconds.toDouble()
                                : 1,
                            value: value.position.inMilliseconds
                                .clamp(
                                  0,
                                  value.duration.inMilliseconds > 0
                                      ? value.duration.inMilliseconds
                                      : 1,
                                )
                                .toDouble(),
                            onChanged: (ms) =>
                                onSeekTo(Duration(milliseconds: ms.round())),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(value.position),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              _formatDuration(value.duration),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final double buttonSize;

  const _ControlButton({
    required this.icon,
    required this.onPressed,
    this.size = 24,
    this.buttonSize = 48,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: Icon(icon, color: Colors.white, size: size),
        ),
      ),
    );
  }
}

class _SeekControlButton extends StatelessWidget {
  final IconData icon;
  final String directionLabel;
  final VoidCallback onPressed;

  const _SeekControlButton({
    required this.icon,
    required this.directionLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: SizedBox(
          width: 58,
          height: 58,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(height: 2),
              Text(
                directionLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoPlayerFullscreenPage extends StatefulWidget {
  final String url;
  final String? title;
  final Duration startAt;
  final bool isMuted;

  const _VideoPlayerFullscreenPage({
    required this.url,
    required this.title,
    required this.startAt,
    required this.isMuted,
  });

  @override
  State<_VideoPlayerFullscreenPage> createState() =>
      _VideoPlayerFullscreenPageState();
}

class _VideoPlayerFullscreenPageState
    extends State<_VideoPlayerFullscreenPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(widget.title ?? 'Video'),
      ),
      body: Center(
        child: CachedVideoPlayer(
          url: widget.url,
          play: true,
          fit: BoxFit.contain,
          isFullscreen: true,
          fullscreenTitle: widget.title,
          borderRadius: 0,
          initialPosition: widget.startAt,
          initialMuted: widget.isMuted,
        ),
      ),
    );
  }
}
