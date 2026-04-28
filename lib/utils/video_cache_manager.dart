import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'dart:async';

class VideoCacheManager {
  static const key = 'videoCacheKey';
  static CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 100,
      repo: JsonCacheInfoRepository(databaseName: key),
      fileService: HttpFileService(),
    ),
  );

  static final StreamController<void> _stopPlaybackController =
      StreamController<void>.broadcast();

  static Stream<void> get stopPlaybackStream => _stopPlaybackController.stream;

  static void stopAllPlayback() {
    if (!_stopPlaybackController.isClosed) {
      _stopPlaybackController.add(null);
    }
  }
}
