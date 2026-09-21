import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:bsi_field/src/models/survey.dart';
import 'package:bsi_field/src/services/backup_service.dart';
import 'package:bsi_field/src/services/photo_normalizer.dart';
import 'package:bsi_field/src/services/raw_archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// 원래 폰의 문서 폴더를 흉내 낸다: 사진·원시 번들(원본 포함)·오버레이·경계.
Directory _phoneA(Directory tmp) {
  final docs = Directory(p.join(tmp.path, 'phoneA', 'app_flutter'))..createSync(recursive: true);
  void put(String rel, List<int> bytes) {
    final f = File(p.join(docs.path, rel));
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes);
  }

  put('photos/001_E_1787700000000.jpg', List.filled(1000, 1));
  put('raw/001_20260826_085627/E_original.jpg', List.filled(1000, 2));
  put('raw/001_20260826_085627/E_capture.json', utf8.encode('{"azimuth":"E"}'));
  put('overlays/001_E_overlay.png', List.filled(1000, 3));
  put('overlays/현장검증.json', utf8.encode('[]'));
  return docs;
}

Map<String, dynamic> _row(Directory docs) => {
      'id': 7,
      'treeId': '001',
      'site': '현장검증',
      'createdAt': '2026-08-26T09:07:05.117317',
      'rawDir': p.join(docs.path, 'raw', '001_20260826_085627'),
      'poleGapM': 1.0,
      'faces': jsonEncode([
        {
          'azimuth': 'E',
          'imagePath': p.join(docs.path, 'photos', '001_E_1787700000000.jpg'),
          'overlayPath': p.join(docs.path, 'overlays', '001_E_overlay.png'),
          'analysed': true,
        }
      ]),
    };

Map<String, dynamic> _prefs(Directory docs) => {
      'projects': [
        {'site': '현장검증', 'location': '산청군', 'treeSeq': 14}
      ],
      'activeSite': '현장검증',
      'settings': {'poleGapM': 0.2},
      'activeDraft': jsonEncode({
        'treeId': '015',
        'rawDir': p.join(docs.path, 'raw', '015_x'),
        'photos': {'north': p.join(docs.path, 'photos', '015_N_1.jpg')},
      }),
    };

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('bsi_backup_'));
  tearDown(() {
    BackupService.partLimitBytes = 3500 * 1024 * 1024;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<List<File>> packA(Directory docs) => BackupService.pack(
        docs: docs,
        surveys: [_row(docs)..remove('id')],
        prefs: _prefs(docs),
        outDir: Directory(p.join(tmp.path, 'out')),
        now: DateTime(2026, 9, 21, 14, 5, 9),
      );

  group('백업 → 새 폰에 복원', () {
    test('파일이 그대로 옮겨지고 기록 경로가 새 문서 폴더를 가리킨다', () async {
      final a = _phoneA(tmp);
      final parts = await packA(a);
      expect(parts.map((f) => p.basename(f.path)), ['bsi_backup_20260921_140509.zip']);

      final b = Directory(p.join(tmp.path, 'phoneB', 'Documents'))..createSync(recursive: true);
      final c = await BackupService.unpack(zipPaths: [parts.single.path], docs: b);
      expect(c.filesWritten, 5);
      for (final rel in [
        'photos/001_E_1787700000000.jpg',
        'raw/001_20260826_085627/E_original.jpg',
        'overlays/001_E_overlay.png',
        'overlays/현장검증.json',
      ]) {
        expect(File(p.join(b.path, rel)).readAsBytesSync(),
            File(p.join(a.path, rel)).readAsBytesSync(),
            reason: rel);
      }

      final row = c.surveys.single;
      expect(row.containsKey('id'), isFalse);
      expect(row['rawDir'], p.join(b.path, 'raw', '001_20260826_085627'));
      final rec = SurveyRecord.fromMap(row); // 앱이 그대로 읽을 수 있는 행이다
      expect(rec.faces.single.imagePath,
          p.join(b.path, 'photos', '001_E_1787700000000.jpg'));
      expect(File(rec.faces.single.overlayPath!).existsSync(), isTrue);

      final draft = jsonDecode(c.prefs['activeDraft'] as String) as Map<String, dynamic>;
      expect(draft['rawDir'], p.join(b.path, 'raw', '015_x'));
      expect((draft['photos'] as Map)['north'], p.join(b.path, 'photos', '015_N_1.jpg'));
      expect(c.meta['records'], 1);
      expect((c.meta['createdAt'] as Map)['local'], startsWith('2026-09-21T14:05:09'));
    });

    test('같은 백업을 두 번 불러와도 파일을 겹쳐 쓰지 않는다', () async {
      final a = _phoneA(tmp);
      final zip = (await packA(a)).single.path;
      final b = Directory(p.join(tmp.path, 'phoneB'))..createSync();
      await BackupService.unpack(zipPaths: [zip], docs: b);
      final again = await BackupService.unpack(zipPaths: [zip], docs: b);
      expect(again.filesWritten, 0);
      expect(again.filesSkipped, 5);
    });

    test('이름이 같은데 내용이 다른 파일은 지키고, 복원본은 새 이름으로 가리킨다', () async {
      final a = _phoneA(tmp);
      final zip = (await packA(a)).single.path;
      final b = Directory(p.join(tmp.path, 'phoneB'))..createSync();
      final mine = File(p.join(b.path, 'photos', '001_E_1787700000000.jpg'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([9, 9, 9]);
      final c = await BackupService.unpack(zipPaths: [zip], docs: b);
      expect(mine.readAsBytesSync(), [9, 9, 9]); // 이 폰의 파일은 그대로
      final rec = SurveyRecord.fromMap(c.surveys.single);
      expect(p.basename(rec.faces.single.imagePath!), '001_E_1787700000000 (복원 2).jpg');
      expect(File(rec.faces.single.imagePath!).lengthSync(), 1000);
      expect(c.filesRenamed, 1);
    });
  });

  group('큰 백업은 조각으로 나눈다', () {
    test('한도를 넘으면 여러 파일이 되고, 모두 있어야 복원된다', () async {
      final a = _phoneA(tmp);
      BackupService.partLimitBytes = 1500; // 1000바이트 파일마다 새 조각
      final parts = await packA(a);
      expect(parts.length, greaterThan(1));
      expect(p.basename(parts.first.path), endsWith('_1of${parts.length}.zip'));

      final b = Directory(p.join(tmp.path, 'b'))..createSync();
      final c = await BackupService.unpack(
          zipPaths: [for (final f in parts.reversed) f.path], docs: b); // 순서 무관
      expect(c.filesWritten, 5);

      // 메타가 든 마지막 조각이 빠지면
      await expectLater(
          BackupService.unpack(
              zipPaths: [for (final f in parts.take(parts.length - 1)) f.path],
              docs: Directory(p.join(tmp.path, 'c'))..createSync()),
          throwsA(isA<BackupException>()));
      // 중간 조각이 빠지면
      await expectLater(
          BackupService.unpack(
              zipPaths: [parts.last.path],
              docs: Directory(p.join(tmp.path, 'd'))..createSync()),
          throwsA(isA<BackupException>()
              .having((e) => e.message, 'message', contains('빠졌습니다'))));
    });
  });

  test('문서 폴더 밖을 가리키는 항목은 쓰지 않는다', () async {
    final zipPath = p.join(tmp.path, 'evil.zip');
    final enc = ZipFileEncoder()..create(zipPath);
    enc.addArchiveFile(ArchiveFile.string('part.json', jsonEncode({'backupId': 'x', 'index': 1})));
    enc.addArchiveFile(ArchiveFile.string('backup.json',
        jsonEncode({'format': BackupService.format, 'formatVersion': 1, 'backupId': 'x', 'parts': 1})));
    enc.addArchiveFile(ArchiveFile.string('surveys.json', '[]'));
    enc.addArchiveFile(ArchiveFile.string('docs/../evil.txt', 'x'));
    enc.addArchiveFile(ArchiveFile.string('docs/photos/ok.jpg', 'x'));
    await enc.close();
    final docs = Directory(p.join(tmp.path, 'docs'))..createSync();
    final c = await BackupService.unpack(zipPaths: [zipPath], docs: docs);
    expect(File(p.join(tmp.path, 'evil.txt')).existsSync(), isFalse);
    expect(File(p.join(docs.path, 'photos', 'ok.jpg')).existsSync(), isTrue);
    expect(c.filesRejected, 1);
  });

  test('BSI 백업이 아닌 ZIP은 거부한다', () async {
    final zipPath = p.join(tmp.path, 'other.zip');
    final enc = ZipFileEncoder()..create(zipPath);
    enc.addArchiveFile(ArchiveFile.string('backup.json', jsonEncode({'format': 'x'})));
    enc.addArchiveFile(ArchiveFile.string('surveys.json', '[]'));
    await enc.close();
    await expectLater(
        BackupService.unpack(zipPaths: [zipPath], docs: tmp), throwsA(isA<BackupException>()));
  });

  test('이미 있는 기록(조사지·번호·저장 시각이 같음)은 건너뛴다', () {
    Map<String, dynamic> r(String tree, String at) =>
        {'site': 'S', 'treeId': tree, 'createdAt': at};
    final fresh = BackupService.newRecords(
      [r('001', 'a'), r('002', 'b'), r('002', 'b'), r('003', 'c')],
      [r('001', 'a')],
    );
    expect(fresh.map((m) => m['treeId']), ['002', '003']);
  });

  group('기록 세부', () {
    test('시각은 시간대 오프셋·UTC·epoch ms까지 남긴다', () {
      final t = DateTime(2026, 8, 26, 9, 7, 5, 124);
      final j = RawArchive.timeJson(t);
      expect(j['local'], matches(RegExp(r'^2026-08-26T09:07:05\.124[0-9]*[+-]\d\d:\d\d$')));
      expect(j['utc'], endsWith('Z'));
      expect(j['epochMs'], t.millisecondsSinceEpoch);
      expect(j['utcOffsetMinutes'], t.timeZoneOffset.inMinutes);
    });

    test('원본 EXIF에서 기기·촬영 조건을 읽는다', () {
      final im = img.Image(width: 16, height: 12);
      im.exif.imageIfd['Make'] = 'samsung';
      im.exif.imageIfd['Model'] = 'SM-S921N';
      final jpg = img.encodeJpg(im);
      final ex = RawArchive.exifSummary(Uint8List.fromList(jpg))!;
      expect(ex['make'], 'samsung');
      expect(ex['model'], 'SM-S921N');
      expect(RawArchive.exifSummary(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('NUL 없이 쓴 EXIF 문자열도 끝 글자까지 읽는다(에뮬레이터 카메라 원본)', () {
      // image 패키지만 쓰면 "Googl"·"sdk_gphone64_x86_6"으로 한 글자씩 잘린다.
      final ex = RawArchive.exifSummary(
          File('test/fixtures/exif_no_nul_emulator.jpg').readAsBytesSync())!;
      expect(ex['make'], 'Google');
      expect(ex['model'], 'sdk_gphone64_x86_64');
      expect(ex['iso'], 100);
      expect(ex['dateTimeOriginal'], '2026:09:21 14:19:39');
    });

    test('표준화 기록에 해상도 배율과 밝기 변환식을 남긴다', () {
      const info = NormalizeInfo(true, 4000, 3000, 2560, 1920);
      final j = info.toJson(gain: 1.5);
      expect(j['scale'], closeTo(0.64, 1e-9));
      expect(j['softwareGainApplied'], isTrue);
      expect(j['gainFormula'], contains('gain'));
      expect(const NormalizeInfo(false, null, null, null, null).toJson(gain: 1.5)['softwareGainApplied'],
          isFalse);
    });
  });
}
