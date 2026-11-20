import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_file_saver/flutter_file_saver.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../db/database_helper.dart';
import '../utils/product_category.dart';

enum CatalogImportMode { replace, addOnly, updateAndAdd }

class CatalogExportResult {
  final String savedPath;
  final int productCount;
  final int imageCount;
  final int missingImageCount;

  const CatalogExportResult({
    required this.savedPath,
    required this.productCount,
    required this.imageCount,
    required this.missingImageCount,
  });
}

class CatalogImportPreview {
  final String fileName;
  final List<Map<String, dynamic>> products;
  final int imageCount;

  const CatalogImportPreview({
    required this.fileName,
    required this.products,
    required this.imageCount,
  });

  int get productCount => products.length;
}

class CatalogImportResult {
  final int inserted;
  final int updated;
  final int skipped;

  const CatalogImportResult({
    required this.inserted,
    required this.updated,
    required this.skipped,
  });

  int get affected => inserted + updated;
}

class CatalogBackupService {
  CatalogBackupService._();

  static const String catalogExtension = '.kiwpos';
  static const String catalogMimeType = 'application/vnd.kiwpos.catalog';

  static const MethodChannel _androidChannel = MethodChannel(
    'com.kiwpos/catalog_files',
  );

  static const String _formatName = 'kiwpos_catalog';
  static const int _formatVersion = 2;
  static const int _maxFileSizeBytes = 120 * 1024 * 1024;
  static const int _maxImageSizeBytes = 20 * 1024 * 1024;

  static Future<CatalogExportResult> exportCatalog() async {
    final articles = await DatabaseHelper().getArticulos();

    if (articles.isEmpty) {
      throw StateError('No hay artículos para exportar.');
    }

    final exportedProducts = <Map<String, dynamic>>[];
    int imageCount = 0;
    int missingImageCount = 0;

    for (final article in articles) {
      final imagePath = (article['image'] ?? '').toString().trim();
      String? imageBase64;
      String? imageExtension;

      if (imagePath.isNotEmpty) {
        try {
          final imageFile = File(imagePath);

          if (await imageFile.exists()) {
            final bytes = await imageFile.readAsBytes();

            if (bytes.length <= _maxImageSizeBytes) {
              imageBase64 = base64Encode(bytes);
              imageExtension = _safeExtension(imagePath);
              imageCount++;
            } else {
              missingImageCount++;
            }
          } else {
            missingImageCount++;
          }
        } catch (_) {
          missingImageCount++;
        }
      }

      exportedProducts.add({
        'nombre': (article['nombre'] ?? '').toString(),
        'precio': _toDouble(article['precio']),
        'descripcion': (article['descripcion'] ?? '').toString(),
        'codigoBarras': (article['codigoBarras'] ?? '').toString(),
        'categoria': ProductCategory.normalize(
          article['categoria'],
          barcode: article['codigoBarras'],
        ),
        'imagenBase64': imageBase64,
        'imagenExtension': imageExtension,
      });
    }

    final payload = <String, dynamic>{
      'formato': _formatName,
      'version': _formatVersion,
      'exportadoEn': DateTime.now().toUtc().toIso8601String(),
      'productos': exportedProducts,
    };

    final jsonBytes = utf8.encode(jsonEncode(payload));
    final compressedBytes = Uint8List.fromList(gzip.encode(jsonBytes));
    final fileName = _buildFileName();

    final String savedPath;

    if (Platform.isAndroid) {
      savedPath =
          await _androidChannel.invokeMethod<String>(
            'saveCatalogToDownloads',
            <String, dynamic>{
              'fileName': fileName,
              'bytes': compressedBytes,
              'mimeType': catalogMimeType,
            },
          ) ??
          'Descargas/KiwPOS/$fileName';
    } else {
      savedPath = await FlutterFileSaver().writeFileAsBytes(
        fileName: fileName,
        bytes: compressedBytes,
      );
    }

    return CatalogExportResult(
      savedPath: savedPath,
      productCount: exportedProducts.length,
      imageCount: imageCount,
      missingImageCount: missingImageCount,
    );
  }

  static Future<CatalogImportPreview?> pickCatalog() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final selectedFile = result.files.single;
    final bytes = await _readSelectedFile(selectedFile);

    return _previewFromBytes(
      fileName: selectedFile.name,
      bytes: bytes,
    );
  }

  /// Lee el archivo que Android copió al caché cuando el usuario tocó un
  /// catálogo .kiwpos desde Descargas, WhatsApp o un administrador de archivos.
  static Future<CatalogImportPreview> previewFromFilePath(
    String filePath,
  ) async {
    final normalizedPath = filePath.trim();
    if (normalizedPath.isEmpty) {
      throw const FormatException('No fue posible localizar el catálogo.');
    }

    final file = File(normalizedPath);
    if (!await file.exists()) {
      throw const FormatException(
        'El archivo de catálogo ya no está disponible.',
      );
    }

    final bytes = await file.readAsBytes();
    return _previewFromBytes(
      fileName: path.basename(file.path),
      bytes: bytes,
    );
  }

  static CatalogImportPreview _previewFromBytes({
    required String fileName,
    required Uint8List bytes,
  }) {
    final selectedName = fileName.toLowerCase();

    if (!selectedName.endsWith(catalogExtension)) {
      throw const FormatException(
        'Selecciona un archivo de catálogo con extensión .kiwpos.',
      );
    }

    if (bytes.length > _maxFileSizeBytes) {
      throw const FormatException(
        'El archivo es demasiado grande para importarlo.',
      );
    }

    final decoded = _decodePayload(bytes);

    if (decoded['formato'] != _formatName) {
      throw const FormatException(
        'El archivo seleccionado no es un catálogo válido de KiwPOS.',
      );
    }

    final version = _toInt(decoded['version']);
    if (version < 1 || version > _formatVersion) {
      throw FormatException(
        'La versión del catálogo no es compatible: $version.',
      );
    }

    final rawProducts = decoded['productos'];
    if (rawProducts is! List) {
      throw const FormatException(
        'El catálogo no contiene una lista de productos válida.',
      );
    }

    final uniqueProducts = <String, Map<String, dynamic>>{};
    int imageCount = 0;

    for (final rawProduct in rawProducts) {
      if (rawProduct is! Map) {
        continue;
      }

      final product = Map<String, dynamic>.from(rawProduct);
      final name = (product['nombre'] ?? '').toString().trim();
      final price = _toDouble(product['precio']);

      if (name.isEmpty || price < 0) {
        continue;
      }

      final normalizedName = _normalizeName(name);
      final barcode = (product['codigoBarras'] ?? '').toString().trim();
      final uniqueKey =
          barcode.isNotEmpty ? 'barcode:$barcode' : 'name:$normalizedName';
      final imageData = product['imagenBase64'];

      if (imageData is String && imageData.isNotEmpty) {
        imageCount++;
      }

      uniqueProducts[uniqueKey] = {
        'nombre': name,
        'precio': price,
        'descripcion': (product['descripcion'] ?? '').toString(),
        'codigoBarras': barcode,
        'categoria': ProductCategory.normalize(
          product['categoria'],
          barcode: barcode,
        ),
        'imagenBase64':
            imageData is String && imageData.isNotEmpty ? imageData : null,
        'imagenExtension': _sanitizeExtension(
          product['imagenExtension']?.toString(),
        ),
      };
    }

    if (uniqueProducts.isEmpty) {
      throw const FormatException('El archivo no contiene productos válidos.');
    }

    return CatalogImportPreview(
      fileName: fileName,
      products: uniqueProducts.values.toList(growable: false),
      imageCount: imageCount,
    );
  }

  static Future<CatalogImportResult> importCatalog({
    required CatalogImportPreview preview,
    required CatalogImportMode mode,
  }) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final importFolder = Directory(
      path.join(
        documentsDirectory.path,
        'kiwpos_catalog_images',
        'import_${DateTime.now().millisecondsSinceEpoch}',
      ),
    );

    await importFolder.create(recursive: true);

    final articlesToSave = <Map<String, dynamic>>[];

    for (int index = 0; index < preview.products.length; index++) {
      final product = preview.products[index];
      String imagePath = '';

      final encodedImage = product['imagenBase64'];
      if (encodedImage is String && encodedImage.isNotEmpty) {
        try {
          final imageBytes = base64Decode(encodedImage);

          if (imageBytes.length <= _maxImageSizeBytes) {
            final extension = _sanitizeExtension(
              product['imagenExtension']?.toString(),
            );

            final safeName = _safeFilePart(
              (product['nombre'] ?? 'producto').toString(),
            );

            final imageFile = File(
              path.join(importFolder.path, '${index + 1}_$safeName$extension'),
            );

            await imageFile.writeAsBytes(imageBytes, flush: true);
            imagePath = imageFile.path;
          }
        } catch (_) {
          imagePath = '';
        }
      }

      articlesToSave.add({
        'nombre': (product['nombre'] ?? '').toString().trim(),
        'precio': _toDouble(product['precio']),
        'descripcion': (product['descripcion'] ?? '').toString(),
        'image': imagePath,
        'codigoBarras': (product['codigoBarras'] ?? '').toString().trim(),
        'categoria': ProductCategory.normalize(
          product['categoria'],
          barcode: product['codigoBarras'],
        ),
      });
    }

    final databaseResult = await DatabaseHelper().importarArticulos(
      articlesToSave,
      modo: switch (mode) {
        CatalogImportMode.replace => 'reemplazar',
        CatalogImportMode.addOnly => 'agregar',
        CatalogImportMode.updateAndAdd => 'actualizar',
      },
    );

    return CatalogImportResult(
      inserted: databaseResult['insertados'] ?? 0,
      updated: databaseResult['actualizados'] ?? 0,
      skipped: databaseResult['omitidos'] ?? 0,
    );
  }

  static Future<Uint8List> _readSelectedFile(PlatformFile file) async {
    if (file.bytes != null) {
      return file.bytes!;
    }

    final selectedPath = file.path;
    if (selectedPath == null || selectedPath.isEmpty) {
      throw const FormatException(
        'No fue posible leer el archivo seleccionado.',
      );
    }

    return File(selectedPath).readAsBytes();
  }

  static Map<String, dynamic> _decodePayload(Uint8List bytes) {
    dynamic decoded;

    try {
      final decompressed = gzip.decode(bytes);
      decoded = jsonDecode(utf8.decode(decompressed));
    } catch (_) {
      try {
        decoded = jsonDecode(utf8.decode(bytes));
      } catch (_) {
        throw const FormatException(
          'El archivo está dañado o no pertenece a KiwPOS.',
        );
      }
    }

    if (decoded is! Map) {
      throw const FormatException('El contenido del catálogo no es válido.');
    }

    return Map<String, dynamic>.from(decoded);
  }

  static String _buildFileName() {
    final now = DateTime.now();

    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return 'Catalogo_KiwPOS_'
        '${now.year}${twoDigits(now.month)}${twoDigits(now.day)}_'
        '${twoDigits(now.hour)}${twoDigits(now.minute)}$catalogExtension';
  }

  static String _safeExtension(String filePath) {
    return _sanitizeExtension(path.extension(filePath));
  }

  static String _sanitizeExtension(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();

    const allowed = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.heic'};

    return allowed.contains(normalized) ? normalized : '.jpg';
  }

  static String _safeFilePart(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9áéíóúÁÉÍÓÚñÑ_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');

    if (sanitized.isEmpty) {
      return 'producto';
    }

    return sanitized.length > 45 ? sanitized.substring(0, 45) : sanitized;
  }

  static String _normalizeName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static int _toInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
