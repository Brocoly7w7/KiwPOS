import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Puente entre Android y Flutter para recibir archivos .kiwpos abiertos
/// desde Descargas, WhatsApp, Files u otra aplicación.
class CatalogIntentService {
  CatalogIntentService._();

  static const MethodChannel _channel = MethodChannel(
    'com.kiwpos/catalog_files',
  );

  static final ValueNotifier<String?> pendingCatalogPath =
      ValueNotifier<String?>(null);

  static bool _initialized = false;
  static bool _refreshing = false;

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method != 'catalogFileOpened') return;

      final value = call.arguments;
      if (value is String && value.trim().isNotEmpty) {
        _publishPath(value);
      }
    });

    await refreshPendingCatalog();

    // En arranque en frío Android puede tardar unos milisegundos en copiar
    // el archivo de WhatsApp al caché. Estos reintentos recuperan la ruta
    // aunque el primer getInitialCatalogPath haya ocurrido demasiado pronto.
    _scheduleRecoveryChecks();
  }

  static void _scheduleRecoveryChecks() {
    for (final delay in <Duration>[
      const Duration(milliseconds: 180),
      const Duration(milliseconds: 550),
      const Duration(milliseconds: 1200),
      const Duration(milliseconds: 2400),
    ]) {
      Future<void>.delayed(delay, refreshPendingCatalog);
    }
  }

  static void _publishPath(String rawPath) {
    final path = rawPath.trim();
    if (path.isEmpty) return;

    if (pendingCatalogPath.value != path) {
      pendingCatalogPath.value = path;
    }
  }

  /// Consulta nuevamente a Android por un catálogo pendiente.
  /// Se usa al iniciar, al volver del fondo y cuando ArticlesPage aparece.
  static Future<void> refreshPendingCatalog() async {
    if (!_isAndroid || _refreshing) return;

    _refreshing = true;

    try {
      final path = await _channel.invokeMethod<String>(
        'getPendingCatalogPath',
      );

      if (path != null && path.trim().isNotEmpty) {
        _publishPath(path);
      }
    } on MissingPluginException {
      // No aplica fuera de Android o durante pruebas sin el plugin nativo.
    } on PlatformException {
      // La app continúa normalmente y podrá reintentar al volver a primer plano.
    } finally {
      _refreshing = false;
    }
  }

  static Future<void> consume(String path) async {
    final normalizedPath = path.trim();

    if (pendingCatalogPath.value == normalizedPath) {
      pendingCatalogPath.value = null;
    }

    if (!_isAndroid) return;

    try {
      await _channel.invokeMethod<void>(
        'acknowledgeCatalogPath',
        {'path': normalizedPath},
      );
    } on MissingPluginException {
      // No aplica fuera de Android.
    } on PlatformException {
      // El archivo ya fue consumido en Flutter; no bloqueamos el flujo.
    }
  }
}
