import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';

class LocalDbService {
  static final LocalDbService instance = LocalDbService._init();
  static Database? _database;

  LocalDbService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('jodeals_cache.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    debugPrint('LocalDbService: Initializing database at $path');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    debugPrint('LocalDbService: Creating tables...');
    
    // Deals table
    await db.execute('''
      CREATE TABLE deals (
        id INTEGER PRIMARY KEY,
        title_en TEXT,
        title_ar TEXT,
        description_en TEXT,
        description_ar TEXT,
        price TEXT,
        discount TEXT,
        image_url TEXT,
        category TEXT,
        city TEXT,
        created_at TEXT,
        expires_at TEXT,
        is_saved INTEGER,
        is_featured INTEGER,
        merchant_name TEXT,
        views INTEGER,
        location_en TEXT,
        location_ar TEXT
      )
    ''');

    // Categories table
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY,
        name_en TEXT,
        name_ar TEXT,
        icon TEXT
      )
    ''');

    // User profile table
    await db.execute('''
      CREATE TABLE user_profile (
        id INTEGER PRIMARY KEY,
        name TEXT,
        email TEXT,
        phone TEXT,
        address TEXT,
        logo TEXT,
        cover_image TEXT,
        profile_image TEXT
      )
    ''');

    // Sync metadata table
    await db.execute('''
      CREATE TABLE sync_metadata (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  // --- Sync Metadata Helpers ---
  Future<void> saveMetadata(String key, String value) async {
    final db = await database;
    await db.insert(
      'sync_metadata',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getMetadata(String key) async {
    final db = await database;
    final maps = await db.query(
      'sync_metadata',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (maps.isNotEmpty) {
      return maps.first['value'] as String?;
    }
    return null;
  }

  // --- Categories Helpers ---
  Future<void> saveCategories(List<Map<String, dynamic>> categories) async {
    final db = await database;
    final batch = db.batch();
    
    // Optional: Clear existing categories
    batch.delete('categories');
    
    for (var cat in categories) {
      batch.insert(
        'categories',
        {
          'id': cat['id'],
          'name_en': cat['name_en'],
          'name_ar': cat['name_ar'],
          'icon': cat['icon'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    debugPrint('LocalDbService: Saved ${categories.length} categories.');
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    final db = await database;
    return await db.query('categories', orderBy: 'id ASC');
  }

  /// Save deals to local cache.
  /// Set [clearFirst] to true for a full refresh (e.g., user triggered pull-to-refresh).
  /// Set [clearFirst] to false during paginated sync to upsert without wiping cache.
  Future<void> saveDeals(List<dynamic> deals, {bool clearFirst = false}) async {
    final db = await database;
    final batch = db.batch();

    if (clearFirst) {
      batch.delete('deals');
    }

    for (var deal in deals) {
      batch.insert(
        'deals',
        {
          'id': int.tryParse(deal['id'].toString()) ?? 0,
          'title_en': deal['title_en'],
          'title_ar': deal['title_ar'],
          'description_en': deal['description_en'],
          'description_ar': deal['description_ar'],
          'price': deal['price']?.toString(),
          'discount': deal['discount']?.toString(),
          'image_url': deal['image_url'] ?? deal['image'],
          'category': deal['category'],
          'city': deal['city'],
          'created_at': deal['created_at'],
          'expires_at': deal['expires_at'],
          'is_saved': (deal['is_saved'] == true || deal['is_saved'] == 1) ? 1 : 0,
          'is_featured': (deal['is_featured'] == true || deal['is_featured'] == 1) ? 1 : 0,
          'merchant_name': deal['merchant_name'],
          'views': int.tryParse(deal['views'].toString()) ?? 0,
          'location_en': deal['location_en'],
          'location_ar': deal['location_ar'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    debugPrint('LocalDbService: Upserted ${deals.length} deals (clearFirst: $clearFirst).');
  }

  Future<List<Map<String, dynamic>>> getDeals({
    String? category,
    String? city,
    String? searchQuery,
    int limit = 20,
    int offset = 0,
  }) async {
    final db = await database;
    final List<String> conditions = [];
    final List<dynamic> args = [];

    if (category != null && category.isNotEmpty) {
      conditions.add('category = ?');
      args.add(category);
    }
    if (city != null && city.isNotEmpty) {
      conditions.add('city = ?');
      args.add(city);
    }
    if (searchQuery != null && searchQuery.isNotEmpty) {
      conditions.add('(title_en LIKE ? OR title_ar LIKE ? OR merchant_name LIKE ?)');
      args.addAll(['%$searchQuery%', '%$searchQuery%', '%$searchQuery%']);
    }

    final where = conditions.isNotEmpty ? conditions.join(' AND ') : null;

    return await db.query(
      'deals',
      where: where,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'is_featured DESC, id DESC',
      limit: limit,
      offset: offset,
    );
  }

  Future<void> clearDeals() async {
    final db = await database;
    await db.delete('deals');
    debugPrint('LocalDbService: All deals cleared.');
  }

  Future<int> getDealsCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM deals');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // --- User Profile Helpers ---
  Future<void> saveUserProfile(Map<String, dynamic> profile) async {
    final db = await database;
    await db.insert(
      'user_profile',
      {
        'id': int.tryParse(profile['id'].toString()) ?? 0,
        'name': profile['name'],
        'email': profile['email'],
        'phone': profile['phone'],
        'address': profile['address'],
        'logo': profile['logo'],
        'cover_image': profile['cover_image'],
        'profile_image': profile['profile_image'],
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint('LocalDbService: User profile saved/updated.');
  }

  Future<Map<String, dynamic>?> getUserProfile() async {
    final db = await database;
    final maps = await db.query('user_profile');
    if (maps.isNotEmpty) {
      return maps.first;
    }
    return null;
  }

  Future<void> clearUserProfile() async {
    final db = await database;
    await db.delete('user_profile');
    debugPrint('LocalDbService: User profile cleared.');
  }
}
