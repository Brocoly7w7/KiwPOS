import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../utils/product_category.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  // Versión 7: agrega categorías y unidades por producto.
  static const _databaseVersion = 7;
  static const String cajaDefaultId = 'caja_1';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('tickets.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tickets (
        id TEXT PRIMARY KEY,
        cliente TEXT,
        subtotal REAL,
        total REAL,
        pago REAL,
        cambio REAL,
        fecha TEXT,
        hora TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE articulos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT,
        precio REAL,
        descripcion TEXT,
        image TEXT,
        codigoBarras TEXT DEFAULT '',
        categoria TEXT DEFAULT 'productos_frescos'
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS '
      'idx_articulos_codigo_barras '
      'ON articulos(codigoBarras)',
    );

    await db.execute('''
      CREATE TABLE items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ticketId TEXT,
        nombre TEXT,
        precio REAL,
        kg REAL,
        articuloId INTEGER,
        codigoBarras TEXT DEFAULT '',
        categoria TEXT DEFAULT 'productos_frescos',
        FOREIGN KEY(ticketId) REFERENCES tickets(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE cajas (
        id TEXT PRIMARY KEY,
        nombre TEXT,
        createdAt INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE carrito (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cajaId TEXT DEFAULT '$cajaDefaultId',
        nombre TEXT,
        precio REAL,
        kg REAL,
        image TEXT,
        articuloId INTEGER,
        codigoBarras TEXT DEFAULT '',
        categoria TEXT DEFAULT 'productos_frescos',
        FOREIGN KEY(cajaId) REFERENCES cajas(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE factura_config (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        nombreNegocio TEXT NOT NULL,
        direccionNegocio TEXT NOT NULL
      )
    ''');

    await db.insert('factura_config', {
      'id': 1,
      'nombreNegocio': 'Nombre del negocio',
      'direccionNegocio': 'Dirección del negocio',
    });

    await db.insert('cajas', {
      'id': cajaDefaultId,
      'nombre': 'Cliente #1',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        ALTER TABLE articulos ADD COLUMN image TEXT DEFAULT ''
      ''');
    }

    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE carrito (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nombre TEXT,
          precio REAL,
          kg REAL,
          image TEXT
        )
      ''');
    }

    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cajas (
          id TEXT PRIMARY KEY,
          nombre TEXT,
          createdAt INTEGER
        )
      ''');

      await db.insert('cajas', {
        'id': cajaDefaultId,
        'nombre': 'Cliente #1',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      final columns = await db.rawQuery("PRAGMA table_info(carrito)");
      final hasCajaId = columns.any((column) => column['name'] == 'cajaId');

      if (!hasCajaId) {
        await db.execute(
          "ALTER TABLE carrito ADD COLUMN cajaId TEXT DEFAULT '$cajaDefaultId'",
        );
      }

      await db.update(
        'carrito',
        {'cajaId': cajaDefaultId},
        where: 'cajaId IS NULL OR cajaId = ?',
        whereArgs: [''],
      );
    }

    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS factura_config (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          nombreNegocio TEXT NOT NULL,
          direccionNegocio TEXT NOT NULL
        )
      ''');

      await db.insert('factura_config', {
        'id': 1,
        'nombreNegocio': 'Nombre del negocio',
        'direccionNegocio': 'Dirección del negocio',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    if (oldVersion < 6) {
      final articleColumns = await db.rawQuery(
        "PRAGMA table_info(articulos)",
      );

      final hasBarcode = articleColumns.any(
        (column) => column['name'] == 'codigoBarras',
      );

      if (!hasBarcode) {
        await db.execute(
          "ALTER TABLE articulos "
          "ADD COLUMN codigoBarras TEXT DEFAULT ''",
        );
      }

      final cartColumns = await db.rawQuery(
        "PRAGMA table_info(carrito)",
      );

      final hasArticleId = cartColumns.any(
        (column) => column['name'] == 'articuloId',
      );

      final cartHasBarcode = cartColumns.any(
        (column) => column['name'] == 'codigoBarras',
      );

      if (!hasArticleId) {
        await db.execute(
          'ALTER TABLE carrito ADD COLUMN articuloId INTEGER',
        );
      }

      if (!cartHasBarcode) {
        await db.execute(
          "ALTER TABLE carrito "
          "ADD COLUMN codigoBarras TEXT DEFAULT ''",
        );
      }

      await db.execute(
        'CREATE INDEX IF NOT EXISTS '
        'idx_articulos_codigo_barras '
        'ON articulos(codigoBarras)',
      );
    }

    if (oldVersion < 7) {
      Future<void> addColumnIfMissing(
        String table,
        String column,
        String definition,
      ) async {
        final columns = await db.rawQuery('PRAGMA table_info($table)');
        final exists = columns.any((item) => item['name'] == column);

        if (!exists) {
          await db.execute('ALTER TABLE $table ADD COLUMN $definition');
        }
      }

      await addColumnIfMissing(
        'articulos',
        'categoria',
        "categoria TEXT DEFAULT '${ProductCategory.fresh}'",
      );
      await addColumnIfMissing(
        'carrito',
        'categoria',
        "categoria TEXT DEFAULT '${ProductCategory.fresh}'",
      );
      await addColumnIfMissing(
        'items',
        'articuloId',
        'articuloId INTEGER',
      );
      await addColumnIfMissing(
        'items',
        'codigoBarras',
        "codigoBarras TEXT DEFAULT ''",
      );
      await addColumnIfMissing(
        'items',
        'categoria',
        "categoria TEXT DEFAULT '${ProductCategory.fresh}'",
      );

      await db.execute('''
        UPDATE articulos
        SET categoria = CASE
          WHEN TRIM(COALESCE(codigoBarras, '')) <> ''
            THEN '${ProductCategory.groceries}'
          ELSE '${ProductCategory.fresh}'
        END
      ''');

      await db.execute('''
        UPDATE carrito
        SET categoria = COALESCE(
          (
            SELECT a.categoria
            FROM articulos a
            WHERE
              (carrito.articuloId IS NOT NULL AND a.id = carrito.articuloId)
              OR (
                TRIM(COALESCE(carrito.codigoBarras, '')) <> ''
                AND a.codigoBarras = carrito.codigoBarras
              )
              OR LOWER(TRIM(a.nombre)) = LOWER(TRIM(carrito.nombre))
            LIMIT 1
          ),
          CASE
            WHEN TRIM(COALESCE(codigoBarras, '')) <> ''
              THEN '${ProductCategory.groceries}'
            ELSE '${ProductCategory.fresh}'
          END
        )
      ''');

      await db.execute('''
        UPDATE items
        SET categoria = COALESCE(
          (
            SELECT a.categoria
            FROM articulos a
            WHERE LOWER(TRIM(a.nombre)) = LOWER(TRIM(items.nombre))
            LIMIT 1
          ),
          '${ProductCategory.fresh}'
        )
      ''');
    }
  }

  // =========================================================
  // CONFIGURACIÓN DE FACTURA
  // =========================================================

  Future<Map<String, String>> getFacturaConfig() async {
    final db = await database;

    final result = await db.query(
      'factura_config',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );

    if (result.isEmpty) {
      const configDefault = {
        'nombreNegocio': 'Nombre del negocio',
        'direccionNegocio': 'Dirección del negocio',
      };

      await guardarFacturaConfig(
        configDefault['nombreNegocio']!,
        configDefault['direccionNegocio']!,
      );

      return configDefault;
    }

    return {
      'nombreNegocio':
          (result.first['nombreNegocio'] ?? 'Mi negocio')
              .toString(),
      'direccionNegocio':
          (result.first['direccionNegocio'] ?? 'Dirección del negocio')
              .toString(),
    };
  }

  Future<void> guardarFacturaConfig(
    String nombreNegocio,
    String direccionNegocio,
  ) async {
    final db = await database;

    await db.insert('factura_config', {
      'id': 1,
      'nombreNegocio': nombreNegocio.trim(),
      'direccionNegocio': direccionNegocio.trim(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // =========================================================
  // ARTÍCULOS
  // =========================================================

  Future<void> insertArticulo(Map<String, dynamic> articulo) async {
    final db = await database;
    final data = Map<String, dynamic>.from(articulo);
    final barcode = _normalizarCodigoBarras(data['codigoBarras']);

    if (barcode.isNotEmpty && await codigoBarrasExiste(barcode)) {
      throw StateError('Ese código de barras ya pertenece a otro artículo.');
    }

    data['codigoBarras'] = barcode;
    data['categoria'] = ProductCategory.normalize(
      data['categoria'],
      barcode: barcode,
    );
    await db.insert('articulos', data);
  }

  Future<List<Map<String, dynamic>>> getArticulos() async {
    final db = await database;
    return await db.query('articulos', orderBy: 'categoria ASC, nombre COLLATE NOCASE ASC');
  }

  Future<Map<String, dynamic>?> getArticuloPorCodigoBarras(
    String codigoBarras,
  ) async {
    final db = await database;
    final barcode = _normalizarCodigoBarras(codigoBarras);

    if (barcode.isEmpty) return null;

    final result = await db.query(
      'articulos',
      where: 'codigoBarras = ?',
      whereArgs: [barcode],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return Map<String, dynamic>.from(result.first);
  }

  Future<bool> codigoBarrasExiste(
    String codigoBarras, {
    int? excluirId,
  }) async {
    final db = await database;
    final barcode = _normalizarCodigoBarras(codigoBarras);

    if (barcode.isEmpty) return false;

    final result = await db.query(
      'articulos',
      columns: const ['id'],
      where: excluirId == null
          ? 'codigoBarras = ?'
          : 'codigoBarras = ? AND id != ?',
      whereArgs: excluirId == null
          ? [barcode]
          : [barcode, excluirId],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  Future<void> deleteArticulo(int id) async {
    final db = await database;
    await db.delete('articulos', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateArticulo(Map<String, dynamic> articulo) async {
    final db = await database;
    final id = articulo['id'];

    if (id is! int) {
      throw ArgumentError('El artículo no contiene un ID válido.');
    }

    final existingRows = await db.query(
      'articulos',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final existing = existingRows.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(existingRows.first);

    final data = Map<String, dynamic>.from(articulo)..remove('id');

    final barcode = data.containsKey('codigoBarras')
        ? _normalizarCodigoBarras(data['codigoBarras'])
        : _normalizarCodigoBarras(existing['codigoBarras']);

    if (barcode.isNotEmpty &&
        await codigoBarrasExiste(barcode, excluirId: id)) {
      throw StateError(
        'Ese código de barras ya pertenece a otro artículo.',
      );
    }

    data['codigoBarras'] = barcode;
    data['categoria'] = ProductCategory.normalize(
      data['categoria'] ?? existing['categoria'],
      barcode: barcode,
    );

    await db.update(
      'articulos',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, int>> importarArticulos(
    List<Map<String, dynamic>> articulos, {
    required String modo,
  }) async {
    final db = await database;

    return db.transaction((transaction) async {
      int insertados = 0;
      int actualizados = 0;
      int omitidos = 0;

      if (modo == 'reemplazar') {
        await transaction.delete('articulos');

        final usedBarcodes = <String>{};

        for (final articulo in articulos) {
          final nombre = (articulo['nombre'] ?? '').toString().trim();
          final barcode = _normalizarCodigoBarras(
            articulo['codigoBarras'],
          );

          if (nombre.isEmpty ||
              (barcode.isNotEmpty && !usedBarcodes.add(barcode))) {
            omitidos++;
            continue;
          }

          await transaction.insert('articulos', {
            'nombre': nombre,
            'precio': _toDatabaseDouble(articulo['precio']),
            'descripcion': (articulo['descripcion'] ?? '').toString(),
            'image': (articulo['image'] ?? '').toString(),
            'codigoBarras': barcode,
            'categoria': ProductCategory.normalize(
              articulo['categoria'],
              barcode: barcode,
            ),
          });

          insertados++;
        }

        return {
          'insertados': insertados,
          'actualizados': actualizados,
          'omitidos': omitidos,
        };
      }

      final existentes = await transaction.query('articulos');
      final articulosPorNombre = <String, Map<String, dynamic>>{};
      final articulosPorCodigo = <String, Map<String, dynamic>>{};

      for (final articuloExistente in existentes) {
        final item = Map<String, dynamic>.from(articuloExistente);
        final nombreNormalizado = _normalizarNombreArticulo(
          (item['nombre'] ?? '').toString(),
        );
        final barcode = _normalizarCodigoBarras(item['codigoBarras']);

        articulosPorNombre[nombreNormalizado] = item;

        if (barcode.isNotEmpty) {
          articulosPorCodigo[barcode] = item;
        }
      }

      for (final articulo in articulos) {
        final nombre = (articulo['nombre'] ?? '').toString().trim();
        final barcode = _normalizarCodigoBarras(
          articulo['codigoBarras'],
        );

        if (nombre.isEmpty) {
          omitidos++;
          continue;
        }

        final nombreNormalizado = _normalizarNombreArticulo(nombre);
        final articuloExistente = barcode.isNotEmpty
            ? articulosPorCodigo[barcode] ??
                articulosPorNombre[nombreNormalizado]
            : articulosPorNombre[nombreNormalizado];

        final idExistente = articuloExistente?['id'];
        final nuevaImagen = (articulo['image'] ?? '').toString();

        final datos = <String, dynamic>{
          'nombre': nombre,
          'precio': _toDatabaseDouble(articulo['precio']),
          'descripcion': (articulo['descripcion'] ?? '').toString(),
          'image': nuevaImagen.isNotEmpty
              ? nuevaImagen
              : (articuloExistente?['image'] ?? '').toString(),
          'codigoBarras': barcode.isNotEmpty
              ? barcode
              : (articuloExistente?['codigoBarras'] ?? '').toString(),
          'categoria': ProductCategory.normalize(
            articulo['categoria'] ?? articuloExistente?['categoria'],
            barcode: barcode.isNotEmpty
                ? barcode
                : articuloExistente?['codigoBarras'],
          ),
        };

        if (idExistente is! int) {
          final nuevoId = await transaction.insert('articulos', datos);
          final nuevo = {...datos, 'id': nuevoId};

          articulosPorNombre[nombreNormalizado] = nuevo;

          final nuevoBarcode =
              _normalizarCodigoBarras(nuevo['codigoBarras']);

          if (nuevoBarcode.isNotEmpty) {
            articulosPorCodigo[nuevoBarcode] = nuevo;
          }

          insertados++;
          continue;
        }

        if (modo == 'actualizar') {
          await transaction.update(
            'articulos',
            datos,
            where: 'id = ?',
            whereArgs: [idExistente],
          );

          final actualizado = {...datos, 'id': idExistente};
          articulosPorNombre[nombreNormalizado] = actualizado;

          final updatedBarcode =
              _normalizarCodigoBarras(actualizado['codigoBarras']);

          if (updatedBarcode.isNotEmpty) {
            articulosPorCodigo[updatedBarcode] = actualizado;
          }

          actualizados++;
        } else {
          omitidos++;
        }
      }

      return {
        'insertados': insertados,
        'actualizados': actualizados,
        'omitidos': omitidos,
      };
    });
  }

  String _normalizarNombreArticulo(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalizarCodigoBarras(dynamic value) {
    return value?.toString().trim() ?? '';
  }

  double _toDatabaseDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  // =========================================================
  // CAJAS / CLIENTES TEMPORALES
  // =========================================================

  Future<List<Map<String, dynamic>>> getCajasConCarrito() async {
    final db = await database;

    List<Map<String, dynamic>> cajas = await db.query(
      'cajas',
      orderBy: 'createdAt ASC',
    );

    if (cajas.isEmpty) {
      await crearCaja(nombre: 'Cliente #1');
      cajas = await db.query('cajas', orderBy: 'createdAt ASC');
    }

    final List<Map<String, dynamic>> resultado = [];

    for (final caja in cajas) {
      final items = await db.query(
        'carrito',
        where: 'cajaId = ?',
        whereArgs: [caja['id']],
        orderBy: 'id ASC',
      );

      resultado.add({
        'id': caja['id'],
        'nombre': caja['nombre'] ?? 'Cliente',
        'createdAt': caja['createdAt'],
        'items':
            items.map((item) {
              final double precio =
                  item['precio'] is num
                      ? (item['precio'] as num).toDouble()
                      : 0.0;
              final double kg =
                  item['kg'] is num ? (item['kg'] as num).toDouble() : 0.0;

              return {
                'nombre': item['nombre'],
                'precio': precio,
                'kg': kg,
                'image': item['image'] ?? '',
                'articuloId': item['articuloId'],
                'codigoBarras': item['codigoBarras'] ?? '',
                'categoria': ProductCategory.normalize(
                  item['categoria'],
                  barcode: item['codigoBarras'],
                ),
                'total': precio * kg,
              };
            }).toList(),
      });
    }

    return resultado;
  }

  Future<String> crearCaja({required String nombre}) async {
    final db = await database;
    final String id = 'caja_${DateTime.now().millisecondsSinceEpoch}';

    await db.insert('cajas', {
      'id': id,
      'nombre': nombre,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });

    return id;
  }

  Future<void> actualizarNombreCaja(String cajaId, String nombre) async {
    final db = await database;
    await db.update(
      'cajas',
      {'nombre': nombre},
      where: 'id = ?',
      whereArgs: [cajaId],
    );
  }

  Future<void> eliminarCaja(String cajaId) async {
    final db = await database;
    await db.delete('carrito', where: 'cajaId = ?', whereArgs: [cajaId]);
    await db.delete('cajas', where: 'id = ?', whereArgs: [cajaId]);
  }

  Future<void> guardarCarritoDeCaja(
    String cajaId,
    List<Map<String, dynamic>> carrito,
  ) async {
    final db = await database;

    await db.delete('carrito', where: 'cajaId = ?', whereArgs: [cajaId]);

    for (final item in carrito) {
      await db.insert('carrito', {
        'cajaId': cajaId,
        'nombre': item['nombre'],
        'precio': item['precio'],
        'kg': item['kg'],
        'image': item['image'] ?? '',
        'articuloId': item['articuloId'],
        'codigoBarras': (item['codigoBarras'] ?? '').toString(),
        'categoria': ProductCategory.normalize(
          item['categoria'],
          barcode: item['codigoBarras'],
        ),
      });
    }
  }

  Future<void> limpiarCarritoDeCaja(String cajaId) async {
    final db = await database;
    await db.delete('carrito', where: 'cajaId = ?', whereArgs: [cajaId]);
  }

  // Métodos antiguos conservados para no romper otras partes del proyecto.
  Future<List<Map<String, dynamic>>> getCarrito() async {
    final db = await database;
    return await db.query(
      'carrito',
      where: 'cajaId = ?',
      whereArgs: [cajaDefaultId],
      orderBy: 'id ASC',
    );
  }

  Future<void> guardarCarrito(List<Map<String, dynamic>> carrito) async {
    await guardarCarritoDeCaja(cajaDefaultId, carrito);
  }

  Future<void> limpiarCarrito() async {
    await limpiarCarritoDeCaja(cajaDefaultId);
  }

  Future<int> getSiguienteNumeroCliente() async {
    final db = await database;

    final result = await db.rawQuery('SELECT COUNT(*) AS total FROM tickets');

    final Object? total = result.isNotEmpty ? result.first['total'] : 0;

    if (total is int) {
      return total + 1;
    }

    if (total is num) {
      return total.toInt() + 1;
    }

    return 1;
  }

  // =========================================================
  // TICKETS
  // =========================================================

  Future<void> insertTicket(
    Map<String, dynamic> ticket,
    List<Map<String, dynamic>> items,
  ) async {
    final db = await database;

    await db.insert('tickets', ticket);

    for (var item in items) {
      await db.insert('items', {
        'ticketId': ticket['id'],
        'nombre': item['nombre'],
        'precio': item['precio'],
        'kg': item['kg'],
        'articuloId': item['articuloId'],
        'codigoBarras': (item['codigoBarras'] ?? '').toString(),
        'categoria': ProductCategory.normalize(
          item['categoria'],
          barcode: item['codigoBarras'],
        ),
      });
    }
  }

  Future<List<Map<String, dynamic>>> getTickets() async {
    final db = await database;
    final tickets = await db.query('tickets', orderBy: 'rowid DESC');

    List<Map<String, dynamic>> ticketsConItems = [];

    for (var ticket in tickets) {
      final items = await db.query(
        'items',
        where: 'ticketId = ?',
        whereArgs: [ticket['id']],
      );

      ticketsConItems.add({
        ...ticket,
        'items': items,
        'articulos': items.length,
      });
    }

    return ticketsConItems;
  }

  Future<void> updateTicket(Map<String, dynamic> ticket) async {
    final db = await database;

    await db.update(
      'tickets',
      {
        'cliente': ticket['cliente'],
        'subtotal': ticket['subtotal'],
        'total': ticket['total'],
        'pago': ticket['pago'],
        'cambio': ticket['cambio'],
        'fecha': ticket['fecha'],
        'hora': ticket['hora'],
      },
      where: 'id = ?',
      whereArgs: [ticket['id']],
    );

    await db.delete('items', where: 'ticketId = ?', whereArgs: [ticket['id']]);

    if (ticket['items'] != null) {
      for (var item in ticket['items']) {
        await db.insert('items', {
          'ticketId': ticket['id'],
          'nombre': item['nombre'],
          'precio': item['precio'],
          'kg': item['kg'],
          'articuloId': item['articuloId'],
          'codigoBarras': (item['codigoBarras'] ?? '').toString(),
          'categoria': ProductCategory.normalize(
            item['categoria'],
            barcode: item['codigoBarras'],
          ),
        });
      }
    }
  }

  Future<void> deleteTicket(String id) async {
    final db = await database;

    await db.delete('items', where: 'ticketId = ?', whereArgs: [id]);
    await db.delete('tickets', where: 'id = ?', whereArgs: [id]);
  }
}
