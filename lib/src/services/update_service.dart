import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'raw_archive.dart';

/// 앱 안 업데이트(안드로이드) — GitHub 릴리스에 올라온 새 APK를 받아 설치 화면으로 넘긴다.
///
/// 릴리스는 GitHub Actions가 **한 키로 서명해** 올린다(.github/workflows/release.yml).
/// 안드로이드는 같은 키로 서명된 APK만 덮어 설치하므로 기록이 그대로 남는다. 키가
/// 다르면 설치 화면이 "앱이 설치되지 않음"으로 거절할 뿐 기존 앱·기록은 그대로다.
class UpdateService {
  UpdateService._();

  static const String repo = 'th00tames1/BSIApp';
  static const MethodChannel _ch = MethodChannel('bsi/update');

  /// 최신 릴리스 주소. 배포 빌드는 GitHub API다. 시험할 때만 빌드 옵션으로 바꾼다
  /// (`--dart-define=BSI_UPDATE_API=http://10.0.2.2:8765/latest.json` — 에뮬레이터에서 PC).
  static const String apiUrl = String.fromEnvironment('BSI_UPDATE_API',
      defaultValue: 'https://api.github.com/repos/$repo/releases/latest');

  /// GitHub의 최신 릴리스. 설치 파일이 없거나 연결이 안 되면 [UpdateException].
  static Future<ReleaseInfo> latest() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client
          .getUrl(Uri.parse(apiUrl));
      req.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'BSI_app/$kAppVersion');
      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 404) {
        throw const UpdateException('아직 게시된 새 버전이 없습니다.');
      }
      if (res.statusCode != 200) {
        throw UpdateException('GitHub 응답 오류(${res.statusCode}). 잠시 뒤 다시 시도하세요.');
      }
      final r = parseRelease(jsonDecode(body) as Map<String, dynamic>, await _abis());
      if (r == null) {
        throw const UpdateException('새 버전에 안드로이드 설치 파일(.apk)이 없습니다.');
      }
      return r;
    } on SocketException {
      throw const UpdateException('인터넷에 연결되어 있지 않습니다.');
    } on HandshakeException {
      throw const UpdateException('GitHub에 안전하게 연결하지 못했습니다.');
    } finally {
      client.close(force: true);
    }
  }

  static Future<List<String>> _abis() async {
    try {
      return [...?(await _ch.invokeListMethod<String>('abis'))];
    } catch (_) {
      return const [];
    }
  }

  /// 릴리스 JSON에서 이 기기에 맞는 APK를 고른다. APK가 없으면 null.
  /// 기기가 지원하는 ABI(예: arm64-v8a)가 이름에 든 파일을 우선하고, 없으면 ABI
  /// 표시가 없는(모든 기기용) 파일, 그것도 없으면 첫 APK.
  static ReleaseInfo? parseRelease(Map<String, dynamic> j, List<String> abis) {
    final apks = [
      for (final a in (j['assets'] as List? ?? const []))
        if (a is Map && '${a['name']}'.toLowerCase().endsWith('.apk')) a
    ];
    if (apks.isEmpty) return null;
    const tokens = {'arm64-v8a': 'arm64', 'armeabi-v7a': 'armv7', 'x86_64': 'x86_64'};
    bool has(Map a, String t) => '${a['name']}'.toLowerCase().contains(t);
    Map? pick;
    for (final abi in abis) {
      final t = tokens[abi];
      if (t == null) continue;
      for (final a in apks) {
        if (has(a, t)) {
          pick = a;
          break;
        }
      }
      if (pick != null) break;
    }
    pick ??= apks.firstWhere((a) => !tokens.values.any((t) => has(a, t)),
        orElse: () => apks.first);
    final tag = '${j['tag_name'] ?? ''}';
    return ReleaseInfo(
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      title: '${j['name'] ?? tag}',
      notes: '${j['body'] ?? ''}'.trim(),
      publishedAt: DateTime.tryParse('${j['published_at'] ?? ''}')?.toLocal(),
      apkName: '${pick['name']}',
      apkUrl: '${pick['browser_download_url']}',
      apkBytes: (pick['size'] as num?)?.toInt() ?? 0,
    );
  }

  /// "0.3.10" > "0.3.9" 처럼 숫자로 비교한다(앞의 v·뒤의 +빌드번호는 무시).
  static int compareVersions(String a, String b) {
    List<int> parts(String v) {
      v = v.trim();
      if (v.startsWith('v')) v = v.substring(1);
      v = v.split('+').first.split('-').first;
      return [for (final s in v.split('.')) int.tryParse(s) ?? 0];
    }

    final x = parts(a), y = parts(b);
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d.sign;
    }
    return 0;
  }

  /// APK를 캐시/updates/에 내려받는다. 현장 이동통신은 자주 끊기므로 **끊긴 데서부터
  /// 이어 받고**(HTTP Range) 몇 번 다시 시도한다. 그래도 안 되면 받은 부분을 남겨 두어
  /// 다시 누르면 이어 받는다. 크기는 릴리스에 적힌 값과 같아야 끝난 것으로 본다.
  static Future<File> download(ReleaseInfo r,
      {void Function(int received, int total)? onProgress,
      Directory? into, // 시험용 — 앱에서는 캐시/updates/(FileProvider가 여기만 내보인다)
      int attempts = 4,
      Duration retryDelay = const Duration(seconds: 2)}) async {
    final dir = into ?? Directory(p.join((await getTemporaryDirectory()).path, 'updates'));
    dir.createSync(recursive: true);
    final out = File(p.join(dir.path, r.apkName));
    for (final f in dir.listSync()) {
      if (f.path != out.path) {
        try {
          f.deleteSync(recursive: true); // 예전에 받은 다른 버전
        } catch (_) {}
      }
    }
    bool complete() => r.apkBytes > 0 && out.existsSync() && out.lengthSync() == r.apkBytes;
    if (complete()) return out;
    for (var i = 0; i < attempts; i++) {
      if (out.existsSync() && r.apkBytes > 0 && out.lengthSync() > r.apkBytes) {
        out.deleteSync(); // 다른 파일이 섞였다 — 처음부터
      }
      try {
        await _fetch(r, out, onProgress);
        if (r.apkBytes <= 0 || complete()) return out;
      } on UpdateException {
        rethrow; // 404 같은 서버 응답은 다시 해도 같다
      } catch (_) {
        // 끊김·멈춤 — 잠시 뒤 이어 받는다
      }
      if (i < attempts - 1) await Future.delayed(retryDelay * (i + 1));
    }
    throw const UpdateException('내려받는 중 연결이 끊겼습니다. 다시 누르면 받은 데서부터 이어 받습니다.');
  }

  static Future<void> _fetch(ReleaseInfo r, File out,
      void Function(int received, int total)? onProgress) async {
    final have = out.existsSync() ? out.lengthSync() : 0;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(r.apkUrl)); // GitHub이 저장소로 넘겨 준다
      req.headers.set(HttpHeaders.userAgentHeader, 'BSI_app/$kAppVersion');
      if (have > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
      final res = await req.close();
      if (res.statusCode == 416) {
        // 요청한 위치가 파일 끝을 넘었다 — 받은 파일을 버리고 처음부터
        await res.drain<void>();
        out.deleteSync();
        throw const _Retry();
      }
      final resume = res.statusCode == 206;
      if (res.statusCode != 200 && !resume) {
        await res.drain<void>();
        throw UpdateException('내려받기 실패(${res.statusCode})');
      }
      final startAt = resume ? have : 0; // 200이면 서버가 이어 받기를 안 해 준 것 — 처음부터
      final total = r.apkBytes > 0
          ? r.apkBytes
          : (res.contentLength > 0 ? startAt + res.contentLength : 0);
      final sink = out.openWrite(mode: resume ? FileMode.append : FileMode.write);
      var got = startAt, lastPct = -1;
      try {
        // 30초 동안 한 바이트도 안 오면 멈춘 것으로 보고 다시 연결한다
        await for (final chunk in res.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          got += chunk.length;
          final pct = total > 0 ? got * 100 ~/ total : 0;
          if (pct != lastPct) {
            lastPct = pct;
            onProgress?.call(got, total);
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
    } finally {
      client.close(force: true);
    }
  }

  /// 설치 화면을 연다. "출처를 알 수 없는 앱" 허용이 아직 없으면 그 설정 화면을 열고
  /// false를 돌려준다(허용하고 돌아와 다시 누르면 된다).
  static Future<bool> install(File apk) async {
    final ok = await _ch.invokeMethod<bool>('canInstall') ?? false;
    if (!ok) {
      await _ch.invokeMethod('openInstallSettings');
      return false;
    }
    await _ch.invokeMethod('install', {'path': apk.path});
    return true;
  }
}

/// 다시 시도할 오류(내부용).
class _Retry implements Exception {
  const _Retry();
}

class UpdateException implements Exception {
  final String message;
  const UpdateException(this.message);
  @override
  String toString() => message;
}

class ReleaseInfo {
  final String version, title, notes, apkName, apkUrl;
  final DateTime? publishedAt;
  final int apkBytes;
  const ReleaseInfo({
    required this.version,
    required this.title,
    required this.notes,
    required this.publishedAt,
    required this.apkName,
    required this.apkUrl,
    required this.apkBytes,
  });

  /// 지금 설치된 앱보다 새 버전인가.
  bool get isNewer => UpdateService.compareVersions(version, kAppVersion) > 0;
}
