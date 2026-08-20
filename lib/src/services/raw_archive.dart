import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/survey.dart';

/// 앱 버전(연구용 원시 데이터에 함께 남긴다 — 어떤 빌드가 만든 값인지 추적).
const String kAppVersion = '0.1.1';

/// 조사목별 **원시 데이터 번들**.
///
/// 나중에 다른 모델·다른 파이프라인으로 같은 사진을 다시 돌려 검증할 수 있도록,
/// 화면에 보이는 것과 무관하게 아래를 기록별 폴더에 모아 둔다.
///   documents/raw/{조사목}_{시각}/
///     {방위}_original.jpg    카메라 원본 그대로(축소·회전 전, EXIF 포함)
///     {방위}_capture.json    촬영 시각·GPS·방위각·기기·앱 버전
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

  /// 카메라 원본(또는 갤러리 원본)을 손대지 않고 번들에 보관한다.
  static Future<String?> keepOriginal(
      String bundleDir, String srcPath, String azCode) async {
    try {
      final dest = p.join(bundleDir, '${azCode}_original.jpg');
      await File(srcPath).copy(dest);
      return dest;
    } catch (_) {
      return null; // 원본 보관 실패가 조사 자체를 막아서는 안 된다
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
