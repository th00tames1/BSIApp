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
      version: 1,
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
    );
    return _db!;
  }

  Future<int> insert(SurveyRecord r) async {
    final db = await _database;
    return db.insert('surveys', r.toMap());
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
