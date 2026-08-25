import 'dart:io';

import 'package:archive/archive_io.dart';

class BkmvArchiveSource {
  final Directory directory;
  final File bkmvFile;
  final File iniFile;

  const BkmvArchiveSource({
    required this.directory,
    required this.bkmvFile,
    required this.iniFile,
  });
}

class BkmvArchiveService {
  static Future<File> buildOpenFrmtBundle({
    required List<BkmvArchiveSource> sources,
    required String stamp,
    required Directory tempRoot,
  }) async {
    if (sources.isEmpty) {
      throw ArgumentError.value(sources, 'sources', 'Must not be empty.');
    }

    final stagingRoot = Directory(
      '${tempRoot.path}${Platform.pathSeparator}openfrmt_export_$stamp',
    );
    if (await stagingRoot.exists()) {
      await stagingRoot.delete(recursive: true);
    }

    final openFrmtRoot = Directory(
      '${stagingRoot.path}${Platform.pathSeparator}OPENFRMT',
    );
    await openFrmtRoot.create(recursive: true);

    try {
      for (final source in sources) {
        final relativeSegments = _relativeSegmentsAfterOpenFrmt(
          source.directory,
        );
        final targetDirectory = Directory(
          [openFrmtRoot.path, ...relativeSegments].join(Platform.pathSeparator),
        );
        await targetDirectory.create(recursive: true);

        await source.iniFile.copy(
          '${targetDirectory.path}${Platform.pathSeparator}INI.TXT',
        );

        final bkmvArchive = File(
          '${targetDirectory.path}${Platform.pathSeparator}BKMVDATA.ZIP',
        );
        final bkmvEncoder = ZipFileEncoder();
        bkmvEncoder.create(bkmvArchive.path);
        await bkmvEncoder.addFile(source.bkmvFile, 'BKMVDATA.TXT');
        bkmvEncoder.close();
      }

      final zipFile = File(
        '${tempRoot.path}${Platform.pathSeparator}OPENFRMT_$stamp.zip',
      );
      if (await zipFile.exists()) {
        await zipFile.delete();
      }

      final encoder = ZipFileEncoder();
      encoder.create(zipFile.path);
      await encoder.addDirectory(openFrmtRoot);
      encoder.close();
      return zipFile;
    } finally {
      if (await stagingRoot.exists()) {
        await stagingRoot.delete(recursive: true);
      }
    }
  }

  static List<String> _relativeSegmentsAfterOpenFrmt(Directory directory) {
    final segments = directory.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    final markerIndex = segments.lastIndexWhere(
      (segment) => segment.toUpperCase() == 'OPENFRMT',
    );
    if (markerIndex < 0 || markerIndex == segments.length - 1) {
      throw StateError(
        'The BKMV export directory must be below an OPENFRMT directory.',
      );
    }
    return segments.sublist(markerIndex + 1);
  }
}
