import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDatabase {
  static Database? _db;

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    _db = await openDatabase(
      join(await getDatabasesPath(), 'hpl_offline.db'),
      version: 1,
      onCreate: (db, version) async {
        // Offline GPS Routes table (Start, checkpoints, End)
        await db.execute('''
          CREATE TABLE offline_gps_trail (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            lat TEXT, lng TEXT, log_time TEXT, is_synced INTEGER
          )
        ''');
        // Offline DPR Submissions table
        await db.execute('''
          CREATE TABLE offline_dpr (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            gp_id INTEGER,
            serial_data TEXT,
            photos_data TEXT,
            created_at TEXT
          )
        ''');
      },
    );
    return _db!;
  }
}