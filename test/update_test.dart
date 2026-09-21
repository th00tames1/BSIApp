import 'dart:io';

import 'package:bsi_field/src/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _release(List<String> apks, {String tag = 'v0.3.9'}) => {
      'tag_name': tag,
      'name': 'BSI_app $tag',
      'body': '빨강/흰 폴 인식',
      'published_at': '2026-09-22T01:02:03Z',
      'assets': [
        for (final n in apks)
          {'name': n, 'browser_download_url': 'https://example.com/$n', 'size': 1234},
        {'name': 'notes.txt', 'browser_download_url': 'https://example.com/n', 'size': 1},
      ],
    };

void main() {
  group('버전 비교', () {
    test('자리마다 숫자로 비교한다', () {
      expect(UpdateService.compareVersions('0.3.10', '0.3.9'), 1);
      expect(UpdateService.compareVersions('0.3.4', '0.3.5'), -1);
      expect(UpdateService.compareVersions('1.0', '0.9.9'), 1);
    });
    test('앞의 v와 뒤의 빌드 번호는 무시한다', () {
      expect(UpdateService.compareVersions('v0.3.5', '0.3.5'), 0);
      expect(UpdateService.compareVersions('0.3.5+11', '0.3.5'), 0);
    });
  });

  group('릴리스에서 설치 파일 고르기', () {
    test('기기 ABI에 맞는 APK를 고른다', () {
      final r = UpdateService.parseRelease(
          _release(['bsi_app-v0.3.9-arm64.apk', 'bsi_app-v0.3.9.apk']),
          ['arm64-v8a', 'armeabi-v7a'])!;
      expect(r.apkName, 'bsi_app-v0.3.9-arm64.apk');
      expect(r.version, '0.3.9');
      expect(r.apkBytes, 1234);
      expect(r.notes, '빨강/흰 폴 인식');
    });
    test('맞는 ABI가 없으면 ABI 표시 없는(모든 기기용) 파일', () {
      final r = UpdateService.parseRelease(
          _release(['bsi_app-v0.3.9-arm64.apk', 'bsi_app-v0.3.9.apk']), ['x86']);
      expect(r!.apkName, 'bsi_app-v0.3.9.apk');
    });
    test('APK가 없으면 null', () {
      expect(UpdateService.parseRelease(_release([]), ['arm64-v8a']), isNull);
    });
    test('설치된 버전보다 높을 때만 새 버전', () {
      expect(UpdateService.parseRelease(_release(['a.apk'], tag: 'v99.0.0'), [])!.isNewer, isTrue);
      expect(UpdateService.parseRelease(_release(['a.apk'], tag: 'v0.0.1'), [])!.isNewer, isFalse);
    });
  });

  group('내려받기', () {
    late HttpServer server;
    late Directory tmp;
    final payload = List<int>.generate(300 * 1024, (i) => i % 251);
    var dropFirst = false; // 첫 요청은 절반만 보내고 연결을 끊는다(현장 끊김 흉내)
    final ranges = <String?>[];
    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('bsi_upd_');
      dropFirst = false;
      ranges.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final range = req.headers.value(HttpHeaders.rangeHeader);
        ranges.add(range);
        final res = req.response;
        if (range != null) {
          final from = int.parse(range.substring(6, range.length - 1)); // "bytes=N-"
          res
            ..statusCode = HttpStatus.partialContent
            ..headers.set(HttpHeaders.contentRangeHeader,
                'bytes $from-${payload.length - 1}/${payload.length}')
            ..contentLength = payload.length - from
            ..add(payload.sublist(from));
          await res.close();
          return;
        }
        res.contentLength = payload.length;
        if (dropFirst && ranges.length == 1) {
          // 머리말(전체 길이)만 보내고 몸통 절반 뒤에 연결을 끊는다
          final sock = await res.detachSocket(writeHeaders: true);
          sock.add(payload.sublist(0, payload.length ~/ 2));
          await sock.flush();
          sock.destroy();
          return;
        }
        res.add(payload);
        await res.close();
      });
    });
    tearDown(() async {
      await server.close(force: true);
      tmp.deleteSync(recursive: true);
    });

    ReleaseInfo info(int bytes) => ReleaseInfo(
        version: '9.9.9',
        title: '',
        notes: '',
        publishedAt: null,
        apkName: 'app.apk',
        apkUrl: 'http://127.0.0.1:${server.port}/app.apk',
        apkBytes: bytes);

    test('끝까지 받고 진행률을 알린다', () async {
      final seen = <int>[];
      final f = await UpdateService.download(info(payload.length),
          into: tmp, onProgress: (got, total) => seen.add(got));
      expect(f.readAsBytesSync(), payload);
      expect(seen.last, payload.length);
    });

    test('중간에 끊기면 받은 데서부터 이어 받는다', () async {
      dropFirst = true;
      final f = await UpdateService.download(info(payload.length),
          into: tmp, retryDelay: Duration.zero);
      expect(f.readAsBytesSync(), payload);
      expect(ranges.length, 2);
      expect(ranges.last, startsWith('bytes=')); // 두 번째는 이어 받기 요청
      expect(ranges.last, isNot('bytes=0-'));
    });

    test('끝내 크기가 안 맞으면 알리고, 받은 부분은 남겨 둔다', () async {
      await expectLater(
          UpdateService.download(info(payload.length + 1),
              into: tmp, attempts: 2, retryDelay: Duration.zero),
          throwsA(isA<UpdateException>()));
      expect(File('${tmp.path}/app.apk').existsSync(), isTrue);
    });

    test('이미 다 받은 파일이 있으면 다시 받지 않는다', () async {
      File('${tmp.path}/app.apk').writeAsBytesSync(payload);
      await UpdateService.download(info(payload.length), into: tmp);
      expect(ranges, isEmpty);
    });
  });
}
