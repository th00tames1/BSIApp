import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/survey.dart';

/// 앱 버전(연구용 원시 데이터에 함께 남긴다 — 어떤 빌드가 만든 값인지 추적).
const String kAppVersion = '0.3.3';

/// 조사목별 **원시 데이터 번들**.
///
/// 나중에 다른 모델·다른 파이프라인으로 같은 사진을 다시 돌려 검증할 수 있도록,
/// 화면에 보이는 것과 무관하게 아래를 기록별 폴더에 모아 둔다.
///   documents/raw/{조사목}_{시각}/
///     {방위}_original.jpg    **카메라 원본 그대로**(바이트 동일 — EXIF·해상도 보존)
///     {방위}_original_backlit.jpg  역광이라 다시 찍기 전의 첫 사진(있을 때만)
///     {방위}_photo.jpg       분석용 표준 사진(긴 변 2560, 소프트웨어 밝기 적용본)
///     {방위}_capture.json    촬영 시각(시간대 포함)·GPS·방위각·배율·노출·밝기 변환·
///                            원본/표준 해상도·원본 EXIF(기기·셔터·ISO·초점거리)·앱 버전
///     {방위}_analysis.json   모델명·입력 기하·분할 통계·수고봉 경계점·계측치
///     {방위}_mask_tree.png   수간 마스크(모델 proto 해상도, 0/255)
///     {방위}_mask_soot.png   그을음 마스크
///     reanalysis_{시각}/     개발자 모드 재분석 산출물(원 분석은 덮어쓰지 않는다)
///     record.json            저장 시점의 최종 레코드(BSI·DBH·판정·직접 입력)
/// 내보내기(개발자 모드)는 CSV와 함께 이 번들·사진·오버레이를 ZIP으로 묶는다.
class RawArchive {
  RawArchive._();

  static Future<Directory> _root() async {
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(docs.path, 'raw'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static String _stamp(DateTime t) =>
      '${t.year}${_pad(t.month)}${_pad(t.day)}_${_pad(t.hour)}${_pad(t.minute)}${_pad(t.second)}';
  static String _pad(int v) => v.toString().padLeft(2, '0');

  /// 새 번들 폴더를 만들고 경로를 돌려준다.
  static Future<String> create(String treeId) async {
    final root = await _root();
    final safe = treeId.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
    final d = Directory(p.join(root.path, '${safe}_${_stamp(DateTime.now())}'));
    d.createSync(recursive: true);
    return d.path;
  }

  /// 카메라 원본을 **바이트 그대로** 번들에 복사한다. 표준 사진은 줄이고 밝기를
  /// 굽고 EXIF를 지우므로, 다른 변환으로 다시 만들 수 있는 출발점은 이것뿐이다.
  /// [suffix]로 역광 재촬영 전 사진 같은 보조 원본을 구분한다.
  static Future<String?> keepOriginal(
      String bundleDir, String srcPath, String azCode,
      {String suffix = ''}) async {
    try {
      var ext = p.extension(srcPath).toLowerCase();
      if (ext.isEmpty) ext = '.jpg';
      final dest = p.join(bundleDir, '${azCode}_original$suffix$ext');
      await File(srcPath).copy(dest);
      return dest;
    } catch (_) {
      return null;
    }
  }

  /// 시각을 빠짐없이 남긴다 — 현지 시각(시간대 오프셋 포함)·UTC·epoch ms.
  /// `toIso8601String()`만 쓰면 오프셋이 빠져 다른 시간대에서 읽을 때 모호하다.
  static Map<String, dynamic> timeJson(DateTime t) {
    final local = t.toLocal();
    final off = local.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final mins = off.inMinutes.abs();
    final hh = (mins ~/ 60).toString().padLeft(2, '0');
    final mm = (mins % 60).toString().padLeft(2, '0');
    return {
      'local': '${local.toIso8601String()}$sign$hh:$mm',
      'utc': local.toUtc().toIso8601String(),
      'epochMs': local.millisecondsSinceEpoch,
      'timeZone': local.timeZoneName,
      'utcOffsetMinutes': off.inMinutes,
    };
  }

  /// 원본 JPEG의 EXIF 중 재현·검증에 쓸 항목. 없거나 읽지 못하면 null.
  /// 카메라가 실제로 쓴 셔터·ISO·초점거리는 앱의 노출 슬라이더와 별개라
  /// 여기서만 알 수 있다.
  static Map<String, dynamic>? exifSummary(Uint8List bytes) {
    try {
      final ex = img.decodeJpgExif(bytes);
      if (ex == null) return null;
      final i0 = ex.imageIfd;
      final e = ex.exifIfd;
      final ascii = _exifAscii(bytes);
      String? str(img.IfdDirectory d, int tag) {
        final raw = ascii[tag];
        if (raw != null && raw.isNotEmpty) return raw;
        final v = d[tag]?.toString().replaceAll('\u0000', '').trim();
        return (v == null || v.isEmpty) ? null : v;
      }
      double? real(img.IfdDirectory d, int tag) {
        final v = d[tag];
        if (v == null) return null;
        final x = v.toDouble();
        return x.isFinite ? x : null;
      }
      int? whole(img.IfdDirectory d, int tag) => d[tag]?.toInt();
      final out = <String, dynamic>{
        'make': str(i0, 0x010F),
        'model': str(i0, 0x0110),
        'software': str(i0, 0x0131),
        'orientation': whole(i0, 0x0112),
        'dateTimeOriginal': str(e, 0x9003),
        'subSecTimeOriginal': str(e, 0x9291),
        'offsetTimeOriginal': str(e, 0x9011),
        'exposureTimeS': real(e, 0x829A),
        'fNumber': real(e, 0x829D),
        'iso': whole(e, 0x8827),
        'exposureBiasEv': real(e, 0x9204),
        'exposureProgram': whole(e, 0x8822),
        'exposureMode': whole(e, 0xA402),
        'meteringMode': whole(e, 0x9207),
        'flash': whole(e, 0x9209),
        'whiteBalance': whole(e, 0xA403),
        'focalLengthMm': real(e, 0x920A),
        'focalLength35mm': whole(e, 0xA405),
        'digitalZoomRatio': real(e, 0xA404),
        'pixelWidth': whole(e, 0xA002),
        'pixelHeight': whole(e, 0xA003),
      }..removeWhere((_, v) => v == null);
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  /// EXIF의 문자열(ASCII) 태그를 원문 그대로 읽는다. image 패키지는 마지막 바이트를
  /// 늘 NUL 종료로 보고 버리는데, NUL 없이 쓰는 카메라에서는 **끝 글자가 잘린다**
  /// (에뮬레이터: "Google" → "Googl"). 기기 모델은 기기별 비교에 쓰이므로 정확해야 한다.
  static Map<int, String> _exifAscii(Uint8List b) {
    final out = <int, String>{};
    try {
      var i = 2; // SOI 다음
      while (i + 4 <= b.length && b[i] == 0xFF) {
        final marker = b[i + 1];
        final len = (b[i + 2] << 8) | b[i + 3];
        if (marker == 0xE1 &&
            i + 10 <= b.length &&
            b[i + 4] == 0x45 && // "Exif"
            b[i + 5] == 0x78 &&
            b[i + 6] == 0x69 &&
            b[i + 7] == 0x66) {
          final t = i + 10; // TIFF 헤더
          final le = b[t] == 0x49; // "II" = little endian
          int u16(int o) => le ? b[o] | (b[o + 1] << 8) : (b[o] << 8) | b[o + 1];
          int u32(int o) => le
              ? b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)
              : (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
          void ifd(int off, bool sub) {
            final base = t + off;
            if (base + 2 > b.length) return;
            final n = u16(base);
            for (var k = 0; k < n; k++) {
              final e = base + 2 + k * 12;
              if (e + 12 > b.length) return;
              final tag = u16(e), type = u16(e + 2), count = u32(e + 4);
              if (!sub && tag == 0x8769) {
                ifd(u32(e + 8), true); // EXIF 하위 IFD
                continue;
              }
              if (type != 2 || count == 0) continue;
              final vo = count <= 4 ? e + 8 : t + u32(e + 8);
              if (vo < 0 || vo + count > b.length) continue;
              var v = String.fromCharCodes(b.sublist(vo, vo + count));
              final z = v.indexOf('\u0000');
              if (z >= 0) v = v.substring(0, z);
              out[tag] = v.trim();
            }
          }

          ifd(u32(t + 4), false);
          return out;
        }
        if (marker == 0xDA) break; // 영상 데이터 시작 — 더 볼 머리말 없음
        i += 2 + len;
      }
    } catch (_) {}
    return out;
  }

  /// 분석용 표준 사진(정규화 완료본)을 번들에 복사한다 — 내보내기 ZIP이
  /// 기록 폴더 없이도 자체 완결이 되도록.
  static Future<String?> keepPhoto(
      String bundleDir, String normalizedPath, String azCode) async {
    try {
      final dest = p.join(bundleDir, '${azCode}_photo.jpg');
      await File(normalizedPath).copy(dest);
      return dest;
    } catch (_) {
      return null; // 보관 실패가 조사 자체를 막아서는 안 된다
    }
  }

  static Future<void> writeJson(
      String dir, String name, Map<String, dynamic> json) async {
    try {
      Directory(dir).createSync(recursive: true);
      await File(p.join(dir, name))
          .writeAsString(const JsonEncoder.withIndent('  ').convert(json), flush: true);
    } catch (_) {}
  }

  /// 기기·앱 정보(촬영·분석 JSON에 공통으로 들어간다).
  static Map<String, dynamic> environment() => {
        'app': kAppVersion,
        'os': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
      };

  /// 개발자 모드 내보내기: CSV + 각 기록의 원시 번들·사진·오버레이를 ZIP으로.
  /// 번들이 없는 기록(구버전·예시)은 사진·오버레이만 들어간다.
  static Future<File> exportZip(List<SurveyRecord> recs, File csv) async {
    final docs = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(docs.path, 'export'));
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    final zipPath =
        p.join(outDir.path, 'bsi_export_${_stamp(DateTime.now())}.zip');
    final enc = ZipFileEncoder()..create(zipPath);
    await enc.addFile(csv, p.basename(csv.path));
    final seen = <String>{};
    for (final r in recs) {
      final key = '${r.dbId ?? r.treeId}_${r.treeId}';
      final dir = r.rawDir;
      if (dir != null && Directory(dir).existsSync()) {
        await enc.addDirectory(Directory(dir),
            includeDirName: true, followLinks: false);
      }
      for (final f in r.faces) {
        for (final path in [f.imagePath, f.overlayPath]) {
          if (path == null || !File(path).existsSync() || !seen.add(path)) continue;
          await enc.addFile(File(path), 'photos/$key/${p.basename(path)}');
        }
      }
    }
    await enc.close();
    return File(zipPath);
  }
}
