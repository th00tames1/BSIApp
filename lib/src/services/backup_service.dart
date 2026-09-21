import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_prefs.dart';
import '../models/survey.dart';
import 'db_service.dart';
import 'raw_archive.dart';

/// 전체 백업·복원 — 폰을 바꾸거나 앱을 지웠다 다시 깔아도 조사를 그대로 잇는다.
///
/// 백업 파일(ZIP) 구성
///   backup.json   형식·앱 버전·만든 시각·원래 문서 폴더·기록/파일 수·조각 수
///   surveys.json  DB의 조사 기록 전부(재분석·간격 정정·직접 입력까지 반영된 현재 값)
///   prefs.json    조사지 목록·설정·작업 중인 조사(있으면)
///   part.json     이 조각이 어느 백업의 몇 번째인지
///   docs/photos/…  docs/raw/…  docs/overlays/…
///                 분석용 사진·원시 번들(표준 사진·촬영/분석 메타·마스크)·오버레이·경계
///
/// 사진은 이미 압축돼 있어 **저장만** 한다(폰에서 수 GB를 다시 압축하면 오래 걸리고
/// 줄지도 않는다). 쓰는 ZIP 라이브러리가 4 GB 넘는 파일을 온전히 쓰지 못하므로
/// [partLimitBytes]마다 조각을 나눈다. json 메타는 마지막 조각에 들어간다.
///
/// 기록 안의 경로는 원래 폰의 절대경로다. 새 폰은 문서 폴더가 다를 수 있으므로
/// (iOS는 설치마다 바뀐다) 복원할 때 [backup.json]의 docsRoot를 새 폴더로 바꾼다.
class BackupService {
  BackupService._();

  static const String format = 'bsi_field-backup';
  static const int formatVersion = 1;

  /// 백업에 담는 문서 폴더 하위 폴더.
  static const List<String> dataDirs = ['photos', 'raw', 'overlays'];

  /// 조각 하나의 최대 크기. ZIP32 한계(4 GiB) 아래로 여유를 둔다.
  @visibleForTesting
  static int partLimitBytes = 3500 * 1024 * 1024;

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  /// [docs] 아래 [dataDirs]의 파일 전부와 기록·설정을 ZIP 조각들로 쓴다.
  static Future<List<File>> pack({
    required Directory docs,
    required List<Map<String, dynamic>> surveys,
    required Map<String, dynamic> prefs,
    required Directory outDir,
    DateTime? now,
    void Function(int done, int total)? onProgress,
  }) async {
    now ??= DateTime.now();
    outDir.createSync(recursive: true);
    final stamp = _stamp(now);
    final id = '${stamp}_${now.microsecondsSinceEpoch}';

    final files = <File>[];
    for (final d in dataDirs) {
      final dir = Directory(p.join(docs.path, d));
      if (!dir.existsSync()) continue;
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        if (e is File) files.add(e);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));

    final parts = <String>[];
    late ZipFileEncoder enc;
    var partBytes = 0;
    var totalBytes = 0;
    void open() {
      final path = p.join(outDir.path, 'bsi_backup_${stamp}_part${parts.length + 1}.zip');
      enc = ZipFileEncoder()..create(path);
      parts.add(path);
      partBytes = 0;
      enc.addArchiveFile(ArchiveFile.string(
          'part.json', jsonEncode({'backupId': id, 'index': parts.length})));
    }

    open();
    var done = 0;
    for (final f in files) {
      final size = f.lengthSync();
      if (partBytes > 0 && partBytes + size > partLimitBytes) {
        await enc.close();
        open();
      }
      final rel = p.relative(f.path, from: docs.path).replaceAll(r'\', '/');
      final input = InputFileStream(f.path);
      final af = ArchiveFile.stream('docs/$rel', input)
        ..compression = CompressionType.none
        ..lastModTime = f.lastModifiedSync().millisecondsSinceEpoch ~/ 1000;
      enc.addArchiveFile(af); // 여기서 스트림을 끝까지 읽어 쓴다
      await input.close();
      partBytes += size;
      totalBytes += size;
      onProgress?.call(++done, files.length);
    }

    final meta = {
      'format': format,
      'formatVersion': formatVersion,
      'backupId': id,
      'app': kAppVersion,
      'createdAt': RawArchive.timeJson(now),
      'environment': RawArchive.environment(),
      'docsRoot': docs.path,
      'records': surveys.length,
      'files': files.length,
      'bytes': totalBytes,
      'parts': parts.length,
    };
    enc.addArchiveFile(ArchiveFile.string('surveys.json', jsonEncode(surveys)));
    enc.addArchiveFile(ArchiveFile.string('prefs.json', jsonEncode(prefs)));
    enc.addArchiveFile(ArchiveFile.string('backup.json', jsonEncode(meta)));
    await enc.close();

    // 조각이 하나면 이름에서 part를 뺀다. 여럿이면 "1of3"처럼 전체 수를 넣는다.
    final out = <File>[];
    for (var i = 0; i < parts.length; i++) {
      final name = parts.length == 1
          ? 'bsi_backup_$stamp.zip'
          : 'bsi_backup_${stamp}_${i + 1}of${parts.length}.zip';
      out.add(File(parts[i]).renameSync(p.join(outDir.path, name)));
    }
    return out;
  }

  /// 백업 조각들을 [docs]에 풀고, 새 폴더 기준으로 경로를 고친 기록·설정을 돌려준다.
  ///
  /// 같은 이름·같은 크기의 파일이 이미 있으면 그대로 둔다(같은 백업을 두 번 불러와도
  /// 안전). 이름만 같고 내용이 다르면 기존 파일을 지키고 새 이름으로 쓴 뒤, 그 파일을
  /// 가리키는 기록 경로를 새 이름으로 바꾼다. 문서 폴더 밖을 가리키는 항목은 버린다.
  static Future<BackupContents> unpack({
    required List<String> zipPaths,
    required Directory docs,
    void Function(int done, int total)? onProgress,
  }) async {
    final opened = <({InputFileStream input, Archive archive})>[];
    try {
      Map<String, dynamic>? meta;
      List<dynamic>? surveys;
      Map<String, dynamic>? prefs;
      final ids = <String>{};
      final indices = <int>{};
      for (final zp in zipPaths) {
        final input = InputFileStream(zp);
        final archive = ZipDecoder().decodeStream(input);
        opened.add((input: input, archive: archive));
        for (final e in archive) {
          if (!e.isFile) continue;
          Object? json() => jsonDecode(utf8.decode(e.readBytes() ?? const []));
          switch (e.name) {
            case 'part.json':
              final m = json() as Map<String, dynamic>;
              ids.add(m['backupId'] as String);
              indices.add((m['index'] as num).toInt());
            case 'backup.json':
              meta = json() as Map<String, dynamic>;
            case 'surveys.json':
              surveys = json() as List<dynamic>;
            case 'prefs.json':
              prefs = json() as Map<String, dynamic>;
          }
        }
      }
      if (meta == null || surveys == null) {
        throw const BackupException(
            '백업 정보(backup.json)가 없습니다. 조각이 여럿이면 모두 함께 고르세요.');
      }
      if (meta['format'] != format) {
        throw const BackupException('BSI 앱 백업 파일이 아닙니다.');
      }
      if (((meta['formatVersion'] as num?)?.toInt() ?? 0) > formatVersion) {
        throw const BackupException('더 새 버전 앱이 만든 백업입니다. 앱을 업데이트하세요.');
      }
      final parts = (meta['parts'] as num?)?.toInt() ?? 1;
      if (ids.length > 1 || (ids.isNotEmpty && !ids.contains(meta['backupId']))) {
        throw const BackupException('서로 다른 백업의 조각이 섞였습니다.');
      }
      final missing = [
        for (var i = 1; i <= parts; i++)
          if (!indices.contains(i)) i
      ];
      if (missing.isNotEmpty) {
        throw BackupException('백업 조각이 빠졌습니다: ${missing.join(', ')}번 (전체 $parts개)');
      }

      final root = p.normalize(docs.path);
      final entries = [
        for (final o in opened)
          for (final e in o.archive)
            if (e.isFile && e.name.startsWith('docs/')) e
      ];
      final renamed = <String, String>{}; // 복원 예정 경로 → 실제로 쓴 경로
      var written = 0, skipped = 0, rejected = 0, done = 0;
      for (final e in entries) {
        final target = p.normalize(p.join(root, e.name.substring(5)));
        if (!p.isWithin(root, target)) {
          rejected++; // "docs/../.." 같은 탈출 경로
          onProgress?.call(++done, entries.length);
          continue;
        }
        var dest = target;
        final f = File(target);
        if (f.existsSync()) {
          if (f.lengthSync() == e.size) {
            skipped++;
            onProgress?.call(++done, entries.length);
            continue;
          }
          dest = _freeName(target);
          renamed[target] = dest;
        }
        Directory(p.dirname(dest)).createSync(recursive: true);
        final out = OutputFileStream(dest);
        e.writeContent(out);
        await out.close();
        written++;
        onProgress?.call(++done, entries.length);
      }

      final oldRoot = meta['docsRoot'] as String? ?? '';
      String? move(String s) {
        if (oldRoot.isEmpty || !s.startsWith(oldRoot)) return null;
        var rest = s.substring(oldRoot.length).replaceAll(r'\', '/');
        while (rest.startsWith('/')) {
          rest = rest.substring(1);
        }
        final moved = p.normalize(p.join(root, rest));
        return renamed[moved] ?? moved;
      }

      final recs = [
        for (final m in surveys) rewriteRecord(Map<String, dynamic>.from(m as Map), move)
      ];
      final pr = Map<String, dynamic>.from(prefs ?? const {});
      final draft = pr['activeDraft'];
      if (draft is String && draft.isNotEmpty) {
        pr['activeDraft'] = jsonEncode(rewriteDeep(jsonDecode(draft), move));
      }
      return BackupContents(
        meta: meta,
        surveys: recs,
        prefs: pr,
        filesWritten: written,
        filesSkipped: skipped,
        filesRejected: rejected,
        filesRenamed: renamed.length,
      );
    } finally {
      for (final o in opened) {
        await o.input.close();
      }
    }
  }

  /// "a.jpg"가 있으면 "a (복원 2).jpg"처럼 비어 있는 이름.
  static String _freeName(String path) {
    final dir = p.dirname(path), base = p.basenameWithoutExtension(path), ext = p.extension(path);
    for (var i = 2;; i++) {
      final c = p.join(dir, '$base (복원 $i)$ext');
      if (!File(c).existsSync()) return c;
    }
  }

  /// JSON 값 안의 문자열 경로를 모두 [move]로 옮긴다(옮길 게 아니면 null을 준다).
  static Object? rewriteDeep(Object? v, String? Function(String) move) {
    if (v is String) return move(v) ?? v;
    if (v is List) return [for (final x in v) rewriteDeep(x, move)];
    if (v is Map) {
      return {for (final e in v.entries) e.key as String: rewriteDeep(e.value, move)};
    }
    return v;
  }

  /// DB 행의 경로(rawDir, faces 안의 사진·오버레이)를 옮긴다. faces는 JSON 문자열이라
  /// 풀어서 고친다 — 문자열 치환은 이스케이프된 경로에서 어긋난다.
  static Map<String, dynamic> rewriteRecord(
      Map<String, dynamic> row, String? Function(String) move) {
    final out = Map<String, dynamic>.from(row)..remove('id');
    final raw = out['rawDir'];
    if (raw is String) out['rawDir'] = move(raw) ?? raw;
    final faces = out['faces'];
    if (faces is String && faces.isNotEmpty) {
      out['faces'] = jsonEncode(rewriteDeep(jsonDecode(faces), move));
    }
    return out;
  }

  /// 같은 조사지·조사목 번호·저장 시각이면 같은 기록이다.
  static String recordKey(Map<String, dynamic> m) =>
      '${m['site'] ?? ''}|${m['treeId']}|${m['createdAt']}';

  /// [incoming] 가운데 [existing]에 없는 기록만.
  static List<Map<String, dynamic>> newRecords(
      List<Map<String, dynamic>> incoming, Iterable<Map<String, dynamic>> existing) {
    final have = {for (final m in existing) recordKey(m)};
    final out = <Map<String, dynamic>>[];
    for (final m in incoming) {
      if (have.add(recordKey(m))) out.add(m); // 백업 안의 중복도 한 번만
    }
    return out;
  }

  // ── 앱에서 쓰는 입구 ───────────────────────────────────────────────

  /// 안드로이드 공용 다운로드 폴더의 백업 위치. **앱을 지워도 남고** 내 파일 앱·
  /// 불러오기 창에서 바로 보인다. 안드로이드 11+는 앱이 만든 파일을 권한 없이 쓸 수
  /// 있다. 쓸 수 없으면(10 이하·iOS) null — 앱 폴더에 만들고 공유로 내보낸다.
  static Directory? publicBackupDir() {
    if (!Platform.isAndroid) return null;
    try {
      final d = Directory('/storage/emulated/0/Download/BSI_backup');
      d.createSync(recursive: true);
      final probe = File(p.join(d.path, '.write_test'));
      probe.writeAsStringSync('ok', flush: true);
      probe.deleteSync();
      return d;
    } catch (_) {
      return null;
    }
  }

  /// 이 폰의 전체 데이터를 백업 파일(조각)로 만든다. 다운로드 폴더에 쓸 수 있으면
  /// 거기에 바로 만든다(두 벌을 만들지 않게). 앱 폴더에 만들 때는 이전 백업을 지운다
  /// (공유로 이미 내보냈을 것이고, 남겨 두면 그만큼 저장 공간을 차지한다).
  static Future<List<File>> exportAll({void Function(int, int)? onProgress}) async {
    final docs = await getApplicationDocumentsDirectory();
    final public = publicBackupDir();
    final outDir = public ?? Directory(p.join(docs.path, 'export'));
    if (public == null && outDir.existsSync()) {
      for (final f in outDir.listSync().whereType<File>()) {
        if (p.basename(f.path).startsWith('bsi_backup_')) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
    }
    final recs = await DbService.instance.all();
    return pack(
      docs: docs,
      surveys: [for (final r in recs) r.toMap()..remove('id')],
      prefs: backupPrefsSnapshot(),
      outDir: outDir,
      onProgress: onProgress,
    );
  }

  /// 백업 조각들을 이 폰에 합친다. 이미 있는 기록은 건너뛴다.
  static Future<RestoreSummary> importFiles(List<String> zipPaths,
      {void Function(int, int)? onProgress}) async {
    final docs = await getApplicationDocumentsDirectory();
    final c = await unpack(zipPaths: zipPaths, docs: docs, onProgress: onProgress);
    final existing = [for (final r in await DbService.instance.all()) r.toMap()];
    final fresh = newRecords(c.surveys, existing);
    for (final m in fresh) {
      await DbService.instance.insert(SurveyRecord.fromMap(m));
    }
    final pr = restorePrefsFromBackup(c.prefs);
    return RestoreSummary(
      recordsAdded: fresh.length,
      recordsSkipped: c.surveys.length - fresh.length,
      filesWritten: c.filesWritten,
      filesSkipped: c.filesSkipped,
      projectsAdded: pr.projectsAdded,
      draftRestored: pr.draftRestored,
      sourceApp: c.meta['app'] as String? ?? '',
      sourceCreatedAt: (c.meta['createdAt'] as Map?)?['local'] as String? ?? '',
    );
  }
}

class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => message;
}

/// [BackupService.unpack] 결과.
class BackupContents {
  final Map<String, dynamic> meta;
  final List<Map<String, dynamic>> surveys; // 경로를 새 폴더로 고친 DB 행
  final Map<String, dynamic> prefs;
  final int filesWritten, filesSkipped, filesRejected, filesRenamed;
  const BackupContents({
    required this.meta,
    required this.surveys,
    required this.prefs,
    required this.filesWritten,
    required this.filesSkipped,
    required this.filesRejected,
    required this.filesRenamed,
  });
}

/// 불러오기 결과(화면 안내용).
class RestoreSummary {
  final int recordsAdded, recordsSkipped, filesWritten, filesSkipped, projectsAdded;
  final bool draftRestored;
  final String sourceApp, sourceCreatedAt;
  const RestoreSummary({
    required this.recordsAdded,
    required this.recordsSkipped,
    required this.filesWritten,
    required this.filesSkipped,
    required this.projectsAdded,
    required this.draftRestored,
    required this.sourceApp,
    required this.sourceCreatedAt,
  });
}
