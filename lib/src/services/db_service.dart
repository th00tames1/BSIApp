import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/survey.dart';

/// Offline SQLite store for survey records (offline-first per the spec).
class DbService {
  DbService._();
  static final DbService instance = DbService._();
  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'bsi_field.db');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE surveys (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            treeId TEXT NOT NULL,
            site TEXT,
            address TEXT,
            lat REAL,
            lon REAL,
            species TEXT,
            dbhCm REAL,
            heightM REAL,
            sootMaxM REAL,
            memo TEXT,
            modelName TEXT,
            poleLengthM REAL,
            faces TEXT,
            bsi REAL,
            mortalityProb REAL,
            verdict TEXT,
            createdAt TEXT
          )
        ''');
      },
      onUpgrade: (db, from, to) async {
        if (from < 2) {
          // 조사목 상세에서 수정 가능한 수고·그을음 높이(레코드 단위) 열 추가.
          await db.execute('ALTER TABLE surveys ADD COLUMN heightM REAL');
          await db.execute('ALTER TABLE surveys ADD COLUMN sootMaxM REAL');
        }
      },
    );
    return _db!;
  }

  Future<int> insert(SurveyRecord r) async {
    final db = await _database;
    return db.insert('surveys', r.toMap());
  }

  /// 조사목 상세에서 수정한 값(수종·흉고직경·수고·그을음 높이 등)을 반영한다.
  Future<void> update(SurveyRecord r) async {
    if (r.dbId == null) return;
    final db = await _database;
    await db.update('surveys', r.toMap(), where: 'id = ?', whereArgs: [r.dbId]);
  }

  Future<List<SurveyRecord>> all() async {
    final db = await _database;
    final rows = await db.query('surveys', orderBy: 'createdAt DESC');
    return rows.map(SurveyRecord.fromMap).toList();
  }

  Future<void> delete(int id) async {
    final db = await _database;
    await db.delete('surveys', where: 'id = ?', whereArgs: [id]);
  }

  /// Re-key saved records when a project (조사지) is renamed, so its trees stay
  /// linked to the (mutable) site name the map filters on.
  Future<void> renameSite(String oldSite, String newSite) async {
    if (oldSite == newSite) return;
    final db = await _database;
    await db.update('surveys', {'site': newSite},
        where: 'site = ?', whereArgs: [oldSite]);
  }

  Future<int> count() async {
    final db = await _database;
    final r = await db.rawQuery('SELECT COUNT(*) c FROM surveys');
    return (r.first['c'] as int?) ?? 0;
  }
}
