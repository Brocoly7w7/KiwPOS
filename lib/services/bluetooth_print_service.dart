import 'dart:async';

import 'package:blue_thermal_printer/blue_thermal_printer.dart';

import '../utils/product_category.dart';

class BluetoothPrintService {
  BluetoothPrintService._internal();

  static final BluetoothPrintService _instance =
      BluetoothPrintService._internal();

  factory BluetoothPrintService() => _instance;

  final BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

  BluetoothDevice? _ultimoDispositivo;
  bool _operacionEnCurso = false;

  BluetoothDevice? get ultimoDispositivo => _ultimoDispositivo;

  Future<List<BluetoothDevice>> obtenerDispositivos() async {
    try {
      return await bluetooth.getBondedDevices();
    } catch (e) {
      print('Error al obtener dispositivos vinculados: $e');
      return [];
    }
  }

  Future<bool> estaConectado() async {
    try {
      return await bluetooth.isConnected ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<T> _ejecutarExclusivo<T>(Future<T> Function() operacion) async {
    while (_operacionEnCurso) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    _operacionEnCurso = true;

    try {
      return await operacion();
    } finally {
      _operacionEnCurso = false;
    }
  }

  Future<void> _desconectarSilenciosamente() async {
    try {
      await bluetooth.disconnect();
    } catch (_) {
      // Puede fallar cuando Android ya cerró el socket Bluetooth.
    }

    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  Future<bool> _conectarInterno(
    BluetoothDevice dispositivo, {
    bool forzarReconexion = false,
  }) async {
    _ultimoDispositivo = dispositivo;

    for (int intento = 1; intento <= 3; intento++) {
      try {
        final conectado = await estaConectado();

        if (conectado && !forzarReconexion) {
          return true;
        }

        // Limpia conexiones fantasma. Esto ocurre cuando Android todavía
        // informa que existe conexión después de salir del alcance.
        if (conectado || forzarReconexion) {
          await _desconectarSilenciosamente();
        }

        await bluetooth.connect(dispositivo);
        await Future<void>.delayed(const Duration(milliseconds: 800));

        if (await estaConectado()) {
          return true;
        }
      } catch (e) {
        print(
          'Intento $intento de conexión Bluetooth falló '
          'con ${dispositivo.name ?? dispositivo.address}: $e',
        );
      }

      await Future<void>.delayed(Duration(milliseconds: 450 * intento));

      // Después del primer fallo siempre limpiamos el socket antes de reintentar.
      forzarReconexion = true;
    }

    return false;
  }

  /// Se conserva para que el resto de la aplicación siga siendo compatible.
  /// Al elegir una impresora, fuerza una conexión nueva para evitar sockets
  /// Bluetooth que Android dejó marcados como conectados.
  Future<bool> conectar(BluetoothDevice dispositivo) {
    return _ejecutarExclusivo(
      () => _conectarInterno(dispositivo, forzarReconexion: true),
    );
  }

  Future<bool> reconectarUltimaImpresora() async {
    final dispositivo = _ultimoDispositivo;
    if (dispositivo == null) return false;

    return _ejecutarExclusivo(
      () => _conectarInterno(dispositivo, forzarReconexion: true),
    );
  }

  Future<void> desconectar() async {
    await _ejecutarExclusivo(() async {
      await _desconectarSilenciosamente();
    });
  }

  /// Conecta o reconecta la impresora seleccionada y después envía el ticket.
  /// Se usa en los botones de impresión para recuperar la conexión sin cerrar
  /// la aplicación cuando el teléfono volvió a estar dentro del alcance.
  Future<bool> imprimirTicketConReconexion({
    required BluetoothDevice dispositivo,
    required Map<String, dynamic> venta,
    required String negocio,
    required String direccion,
  }) {
    return _ejecutarExclusivo(() async {
      final conectado = await _conectarInterno(
        dispositivo,
        forzarReconexion: true,
      );

      if (!conectado) return false;

      try {
        await _enviarTicket(venta, negocio, direccion);
        return true;
      } catch (e) {
        print('Falló el primer envío del ticket: $e');

        final reconectado = await _conectarInterno(
          dispositivo,
          forzarReconexion: true,
        );

        if (!reconectado) return false;

        try {
          await _enviarTicket(venta, negocio, direccion);
          return true;
        } catch (segundoError) {
          print('Falló el segundo envío del ticket: $segundoError');
          return false;
        }
      }
    });
  }

  /// Método compatible con el código anterior. Utiliza la última impresora
  /// elegida dentro de la sesión actual de la aplicación.
  Future<bool> imprimirTicket(
    Map<String, dynamic> venta,
    String negocio,
    String direccion,
  ) async {
    final dispositivo = _ultimoDispositivo;
    if (dispositivo == null) return false;

    return imprimirTicketConReconexion(
      dispositivo: dispositivo,
      venta: venta,
      negocio: negocio,
      direccion: direccion,
    );
  }

  Future<void> _enviarTicket(
    Map<String, dynamic> venta,
    String negocio,
    String direccion,
  ) async {
    final conectado = await estaConectado();
    if (!conectado) {
      throw StateError('La impresora no está conectada.');
    }

    String limpiarTexto(String texto) {
      return texto
          .toUpperCase()
          .replaceAll('Ó', 'O')
          .replaceAll('É', 'E')
          .replaceAll('Á', 'A')
          .replaceAll('Í', 'I')
          .replaceAll('Ú', 'U')
          .replaceAll('Ñ', 'N');
    }

    final negocioLimpio = limpiarTexto(negocio);
    final direccionLimpia = limpiarTexto(direccion);

    bluetooth.printCustom(negocioLimpio, 3, 1);
    bluetooth.printCustom(direccionLimpia, 2, 1);
    bluetooth.printCustom('', 0, 1);

    bluetooth.printCustom('FOLIO: ${venta['id']}', 1, 0);
    bluetooth.printCustom(
      'FECHA: ${venta['fecha']}   HORA: ${venta['hora']}',
      1,
      0,
    );
    bluetooth.printCustom(
      'CLIENTE: ${limpiarTexto((venta['cliente'] ?? 'Cliente Gral').toString())}',
      1,
      0,
    );

    bluetooth.printCustom(
      '------------------------------------------------',
      3,
      1,
    );

    final hCant = 'CANT'.padRight(9);
    final hPrecio = 'PRECIO'.padRight(9);
    final hDesc = 'DESCRIPCION'.padRight(20);
    final hImporte = 'IMPORTE'.padLeft(10);

    bluetooth.printCustom('$hCant$hPrecio$hDesc$hImporte', 1, 0);
    bluetooth.printCustom(
      '------------------------------------------------',
      3,
      1,
    );

    final List<dynamic> items = venta['items'] ?? [];

    for (final item in items) {
      final kgValue = (item['kg'] as num).toDouble();
      final categoria = ProductCategory.normalize(
        item['categoria'],
        barcode: item['codigoBarras'],
      );
      final cantStr = ProductCategory.formatQuantity(
        kgValue,
        categoria,
      ).padRight(9);

      final precioValue = (item['precio'] as num).toDouble();
      final precioStr =
          '\$${precioValue == precioValue.toInt() ? precioValue.toInt().toString() : precioValue.toStringAsFixed(2)}'
              .padRight(9);

      var nombreStr = limpiarTexto((item['nombre'] ?? 'PRODUCTO').toString());

      if (nombreStr.length > 20) {
        nombreStr = nombreStr.substring(0, 20);
      }

      nombreStr = nombreStr.padRight(20);

      final importeValue = precioValue * kgValue;
      final importeStr = '\$${importeValue.toStringAsFixed(2)}'.padLeft(10);

      bluetooth.printCustom('$cantStr$precioStr$nombreStr$importeStr', 1, 0);
    }

    bluetooth.printCustom(
      '------------------------------------------------',
      3,
      1,
    );

    final numeroArticulos =
        items.isEmpty
            ? ((venta['articulos'] ?? 1) as num).toInt()
            : items.length;

    bluetooth.printCustom('No. de productos: $numeroArticulos', 1, 0);

    bluetooth.printCustom(
      '------------------------------------------------',
      3,
      1,
    );

    final subtotalValue =
        (venta['subtotal'] ?? venta['total'] ?? 0.0).toDouble();
    final totalValue = (venta['total'] ?? subtotalValue).toDouble();

    final totalTexto = 'TOTAL: \$${totalValue.round()}';
    bluetooth.printCustom(totalTexto, 2, 1);

    bluetooth.printCustom('', 1, 1);
    bluetooth.printCustom('*** GRACIAS POR SU COMPRA ***', 1, 1);
    bluetooth.printCustom('\n', 0, 1);
    bluetooth.paperCut();

    // Da tiempo al plugin para vaciar el buffer antes de que otra acción
    // Bluetooth intente utilizar el mismo canal.
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}
