import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../utils/video_cache_manager.dart'; // Ensure this path is correct

class CachedVideoPlayer extends StatefulWidget {
  final String url;
  final bool play;
  final Widget? thumbnail;

  const CachedVideoPlayer({
    super.key,
    required this.url,
    this.play = false,
    this.thumbnail,
  });

  @override
  State<CachedVideoPlayer> createState() => _CachedVideoPlayerState();
}

class _CachedVideoPlayerState extends State<CachedVideoPlayer>
    with AutomaticKeepAliveClientMixin {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isError = false;

  @override
  bool get wantKeepAlive => true; // Prevents widget from disposing when scrolling

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  Future<void> _initializeController() async {
    try {
      // 1. Check/Download from Cache
      final fileInfo = await VideoCacheManager.instance.getFileFromCache(
        widget.url,
      );
      File videoFile;

      if (fileInfo == null) {
        // Not in cache, download it
        final file = await VideoCacheManager.instance.getSingleFile(widget.url);
        videoFile = file;
      } else {
        videoFile = fileInfo.file;
      }

      // 2. Initialize Controller using local file
      _controller = VideoPlayerController.file(videoFile);
      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
          if (widget.play) _controller!.play();
          _controller!.setLooping(true);
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
    if (widget.play != oldWidget.play) {
      if (widget.play) {
        _controller?.play();
      } else {
        _controller?.pause();
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin

    if (_isError) {
      return const Center(
        child: Icon(Icons.error_outline, color: Colors.white, size: 40),
      );
    }

    if (!_isInitialized) {
      return Stack(
        alignment: Alignment.center,
        children: [
          if (widget.thumbnail != null) widget.thumbnail!,
          const CircularProgressIndicator(strokeWidth: 2),
        ],
      );
    }

    return AspectRatio(
      aspectRatio: _controller!.value.aspectRatio,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          VideoPlayer(_controller!),
          _VideoControls(controller: _controller!),
          VideoProgressIndicator(_controller!, allowScrubbing: true),
        ],
      ),
    );
  }
}

class _VideoControls extends StatelessWidget {
  final VideoPlayerController controller;
  const _VideoControls({required this.controller});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        controller.value.isPlaying ? controller.pause() : controller.play();
      },
      child: ValueListenableBuilder(
        valueListenable: controller,
        builder: (context, VideoPlayerValue value, child) {
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: value.isPlaying
                ? const SizedBox.shrink()
                : Container(
                    color: Colors.black38,
                    child: const Center(
                      child: Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 80,
                      ),
                    ),
                  ),
          );
        },
      ),
    );
  }
}
