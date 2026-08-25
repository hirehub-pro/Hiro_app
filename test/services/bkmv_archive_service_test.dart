import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/services/bkmv_archive_service.dart';

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('bkmv_archive_test_');
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('puts INI.TXT beside a compressed BKMVDATA archive', () async {
    final sourceDirectory = Directory(
      '${tempRoot.path}${Platform.pathSeparator}source'
      '${Platform.pathSeparator}OPENFRMT'
      '${Platform.pathSeparator}12345678.26'
      '${Platform.pathSeparator}08251430',
    );
    await sourceDirectory.create(recursive: true);
    final iniFile = File(
      '${sourceDirectory.path}${Platform.pathSeparator}INI.TXT',
    );
    final bkmvFile = File(
      '${sourceDirectory.path}${Platform.pathSeparator}BKMVDATA.TXT',
    );
    await iniFile.writeAsBytes(ascii.encode('A000\r\n'));
    await bkmvFile.writeAsBytes(ascii.encode('A100\r\nZ900\r\n'));

    final bundle = await BkmvArchiveService.buildOpenFrmtBundle(
      sources: [
        BkmvArchiveSource(
          directory: sourceDirectory,
          bkmvFile: bkmvFile,
          iniFile: iniFile,
        ),
      ],
      stamp: '20260825_1430',
      tempRoot: tempRoot,
    );

    final outerArchive = ZipDecoder().decodeBytes(await bundle.readAsBytes());
    final files = outerArchive.files.where((entry) => entry.isFile).toList();
    expect(
      files.map((entry) => entry.name),
      containsAll(<String>[
        'OPENFRMT/12345678.26/08251430/INI.TXT',
        'OPENFRMT/12345678.26/08251430/BKMVDATA.ZIP',
      ]),
    );
    expect(
      files.map((entry) => entry.name),
      isNot(contains('OPENFRMT/12345678.26/08251430/BKMVDATA.TXT')),
    );

    final nestedZip = files.singleWhere(
      (entry) => entry.name.endsWith('/BKMVDATA.ZIP'),
    );
    final bkmvArchive = ZipDecoder().decodeBytes(nestedZip.content);
    final bkmvEntry = bkmvArchive.files.single;
    expect(bkmvEntry.name, 'BKMVDATA.TXT');
    expect(ascii.decode(bkmvEntry.content), 'A100\r\nZ900\r\n');
  });
}
