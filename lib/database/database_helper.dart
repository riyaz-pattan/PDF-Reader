import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/pdf_document.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('pdfs.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path, 
      version: 3, 
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          // Creating annotations table if it didn't exist
          await db.execute('''
          CREATE TABLE IF NOT EXISTS annotations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT NOT NULL,
            page INTEGER NOT NULL,
            points_json TEXT NOT NULL,
            FOREIGN KEY (path) REFERENCES pdfs (path) ON DELETE CASCADE
          )
          ''');
          
          // Creating reading_sessions table if it didn't exist
          await db.execute('''
          CREATE TABLE IF NOT EXISTS reading_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT NOT NULL,
            date TEXT NOT NULL,
            duration_seconds INTEGER NOT NULL,
            FOREIGN KEY (path) REFERENCES pdfs (path) ON DELETE CASCADE
          )
          ''');
        }
      },
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS pdfs (
  path TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  size INTEGER NOT NULL,
  lastRead INTEGER NOT NULL,
  lastPage INTEGER NOT NULL,
  totalPages INTEGER NOT NULL,
  isFavorite INTEGER NOT NULL
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS annotations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  path TEXT NOT NULL,
  page INTEGER NOT NULL,
  points_json TEXT NOT NULL,
  FOREIGN KEY (path) REFERENCES pdfs (path) ON DELETE CASCADE
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS tags (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  color INTEGER NOT NULL
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS document_tags (
  path TEXT NOT NULL,
  tag_id INTEGER NOT NULL,
  PRIMARY KEY (path, tag_id),
  FOREIGN KEY (path) REFERENCES pdfs (path) ON DELETE CASCADE,
  FOREIGN KEY (tag_id) REFERENCES tags (id) ON DELETE CASCADE
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS reading_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  path TEXT NOT NULL,
  date TEXT NOT NULL,
  duration_seconds INTEGER NOT NULL,
  FOREIGN KEY (path) REFERENCES pdfs (path) ON DELETE CASCADE
)
''');
  }

  Future<void> insertOrUpdate(PdfDocument document) async {
    final db = await instance.database;
    await db.insert(
      'pdfs',
      document.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<PdfDocument?> getDocument(String path) async {
    final db = await instance.database;
    final maps = await db.query(
      'pdfs',
      columns: ['path', 'name', 'size', 'lastRead', 'lastPage', 'totalPages', 'isFavorite'],
      where: 'path = ?',
      whereArgs: [path],
    );

    if (maps.isNotEmpty) {
      return PdfDocument.fromMap(maps.first);
    } else {
      return null;
    }
  }

  Future<List<PdfDocument>> getAllDocuments() async {
    final db = await instance.database;
    final orderBy = 'lastRead DESC';
    final result = await db.query('pdfs', orderBy: orderBy);
    return result.map((json) => PdfDocument.fromMap(json)).toList();
  }

  Future<List<PdfDocument>> getFavorites() async {
    final db = await instance.database;
    final orderBy = 'name ASC';
    final result = await db.query('pdfs', where: 'isFavorite = 1', orderBy: orderBy);
    return result.map((json) => PdfDocument.fromMap(json)).toList();
  }

  Future<void> deleteDocument(String path) async {
    final db = await instance.database;
    await db.delete(
      'pdfs',
      where: 'path = ?',
      whereArgs: [path],
    );
  }

  // Tags
  Future<int> insertTag(String name, int color) async {
    final db = await instance.database;
    return await db.insert('tags', {'name': name, 'color': color}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Map<String, dynamic>>> getAllTags() async {
    final db = await instance.database;
    return await db.query('tags', orderBy: 'name ASC');
  }

  Future<void> deleteTag(int tagId) async {
    final db = await instance.database;
    await db.delete('tags', where: 'id = ?', whereArgs: [tagId]);
  }

  // Document Tags
  Future<void> addTagToDocument(String path, int tagId) async {
    final db = await instance.database;
    await db.insert('document_tags', {'path': path, 'tag_id': tagId}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> removeTagFromDocument(String path, int tagId) async {
    final db = await instance.database;
    await db.delete('document_tags', where: 'path = ? AND tag_id = ?', whereArgs: [path, tagId]);
  }

  Future<List<int>> getTagsForDocument(String path) async {
    final db = await instance.database;
    final result = await db.query('document_tags', columns: ['tag_id'], where: 'path = ?', whereArgs: [path]);
    return result.map((row) => row['tag_id'] as int).toList();
  }

  // Reading Sessions
  Future<void> addReadingSession(String path, int durationSeconds) async {
    final db = await instance.database;
    final dateStr = DateTime.now().toIso8601String().split('T')[0]; // YYYY-MM-DD
    await db.insert('reading_sessions', {
      'path': path,
      'date': dateStr,
      'duration_seconds': durationSeconds,
    });
  }

  Future<List<Map<String, dynamic>>> getReadingSessions() async {
    final db = await instance.database;
    return await db.query('reading_sessions');
  }

  // Annotations
  Future<void> saveAnnotations(String path, List<Map<String, dynamic>> annotations) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete('annotations', where: 'path = ?', whereArgs: [path]);
      for (final ann in annotations) {
        await txn.insert('annotations', {
          'path': path,
          'page': ann['pageNumber'],
          'points_json': ann['points_json'],
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> getAnnotations(String path) async {
    final db = await instance.database;
    return await db.query('annotations', where: 'path = ?', whereArgs: [path]);
  }
}
