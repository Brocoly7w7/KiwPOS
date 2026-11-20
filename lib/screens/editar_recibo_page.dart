// lib/screens/editar_recibo_page.dart
import 'dart:convert';

import 'package:flutter/material.dart';

import 'modal_editar_articulo_ticket.dart';
import 'articles_page.dart';
import '../db/database_helper.dart';
import '../utils/product_category.dart';

class EditarReciboPage extends StatefulWidget {
  final Map<String, dynamic> ticket;
  final List<Map<String, dynamic>> catalogoProductos;

  const EditarReciboPage({
    super.key,
    required this.ticket,
    required this.catalogoProductos,
  });

  @override
  State<EditarReciboPage> createState() => _EditarReciboPageState();
}

class _EditarReciboPageState extends State<EditarReciboPage> {
  late List<Map<String, dynamic>> _articulosEditados;
  late final String _estadoInicial;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();

    if (widget.ticket['items'] != null) {
      _articulosEditados = List<Map<String, dynamic>>.from(
        (widget.ticket['items'] as List).map(
          (item) => Map<String, dynamic>.from(item),
        ),
      );
    } else {
      _articulosEditados = [];
    }

    _estadoInicial = _serializarArticulos(_articulosEditados);
  }

  String _serializarArticulos(List<Map<String, dynamic>> articulos) {
    final normalizados =
        articulos.map((item) {
          final pRaw = item['precio'];
          final kRaw = item['kg'];

          final double precio =
              pRaw is num
                  ? pRaw.toDouble()
                  : (double.tryParse(pRaw?.toString() ?? '') ?? 0.0);

          final double kg =
              kRaw is num
                  ? kRaw.toDouble()
                  : (double.tryParse(kRaw?.toString() ?? '') ?? 1.0);

          return {
            'nombre': (item['nombre'] ?? '').toString(),
            'precio': double.parse(precio.toStringAsFixed(4)),
            'kg': double.parse(kg.toStringAsFixed(4)),
            'articuloId': item['articuloId'],
            'codigoBarras': (item['codigoBarras'] ?? '').toString(),
            'categoria': ProductCategory.normalize(
              item['categoria'],
              barcode: item['codigoBarras'],
            ),
          };
        }).toList();

    return jsonEncode(normalizados);
  }

  bool get _hayCambiosSinGuardar {
    return _serializarArticulos(_articulosEditados) != _estadoInicial;
  }

  double get totalCalculado => _articulosEditados.fold(0.0, (sum, item) {
    final precioRaw = item['precio'];
    final kgRaw = item['kg'];

    double precio = 0.0;
    if (precioRaw is num) {
      precio = precioRaw.toDouble();
    } else if (precioRaw is String) {
      precio = double.tryParse(precioRaw) ?? 0.0;
    }

    double kg = 0.0;
    if (kgRaw is num) {
      kg = kgRaw.toDouble();
    } else if (kgRaw is String) {
      kg = double.tryParse(kgRaw) ?? 0.0;
    }

    return sum + (precio * kg);
  });

  int get totalArticulos => _articulosEditados.length;

  double _toDouble(dynamic value, {double fallback = 0.0}) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  bool _esMismoProducto(
    Map<String, dynamic> existente,
    Map<String, dynamic> nuevo,
  ) {
    final existingId = existente['articuloId'];
    final newId = nuevo['articuloId'];

    if (existingId != null && newId != null && existingId == newId) {
      return true;
    }

    final existingBarcode =
        (existente['codigoBarras'] ?? '').toString().trim();
    final newBarcode = (nuevo['codigoBarras'] ?? '').toString().trim();

    if (existingBarcode.isNotEmpty &&
        newBarcode.isNotEmpty &&
        existingBarcode == newBarcode) {
      return true;
    }

    final existingName =
        (existente['nombre'] ?? '').toString().trim().toLowerCase();
    final newName = (nuevo['nombre'] ?? '').toString().trim().toLowerCase();

    return existingName.isNotEmpty &&
        newName.isNotEmpty &&
        existingName == newName &&
        (existingId == null || newId == null) &&
        (existingBarcode.isEmpty || newBarcode.isEmpty);
  }

  bool _agregarArticuloConPrecioExistente(
    Map<String, dynamic> seleccionado,
  ) {
    final incomingCategory = ProductCategory.normalize(
      seleccionado['categoria'],
      barcode: seleccionado['codigoBarras'],
    );
    final incomingPrice = _toDouble(seleccionado['precio']);
    final incomingQuantity = ProductCategory.normalizeQuantity(
      seleccionado['kg'],
      incomingCategory,
      fallback: 1.0,
    );

    final normalizedIncoming = <String, dynamic>{
      'nombre': seleccionado['nombre'],
      'precio': incomingPrice,
      'kg': incomingQuantity,
      'total': _toDouble(
        seleccionado['total'],
        fallback: incomingPrice * incomingQuantity,
      ),
      'articuloId': seleccionado['articuloId'],
      'codigoBarras':
          (seleccionado['codigoBarras'] ?? '').toString(),
      'categoria': incomingCategory,
    };

    // Cada producto fresco representa una pesada independiente. Por eso,
    // aunque el artículo ya exista en el recibo, se agrega en otra línea.
    if (!ProductCategory.isGrocery(incomingCategory)) {
      setState(() {
        _articulosEditados.add(normalizedIncoming);
      });
      return false;
    }

    // Los abarrotes sí se agrupan para aumentar sus piezas conservando el
    // precio unitario que ya tenía la línea dentro del recibo.
    final existingIndex = _articulosEditados.indexWhere((item) {
      final itemCategory = ProductCategory.normalize(
        item['categoria'],
        barcode: item['codigoBarras'],
      );

      return ProductCategory.isGrocery(itemCategory) &&
          _esMismoProducto(item, normalizedIncoming);
    });

    setState(() {
      if (existingIndex < 0) {
        _articulosEditados.add(normalizedIncoming);
        return;
      }

      final existing = _articulosEditados[existingIndex];
      final existingCategory = ProductCategory.normalize(
        existing['categoria'] ?? incomingCategory,
        barcode:
            existing['codigoBarras'] ?? normalizedIncoming['codigoBarras'],
      );
      final existingPrice = _toDouble(
        existing['precio'],
        fallback: incomingPrice,
      );
      final existingQuantity = _toDouble(existing['kg']);
      final newQuantity = ProductCategory.normalizeQuantity(
        existingQuantity + incomingQuantity,
        existingCategory,
      );

      final existingTotal = ProductCategory.isGrocery(existingCategory)
          ? existingPrice * existingQuantity
          : _toDouble(
              existing['total'],
              fallback: existingPrice * existingQuantity,
            );

      final newTotal = ProductCategory.isGrocery(existingCategory)
          ? existingPrice * newQuantity
          : existingTotal + (existingPrice * incomingQuantity);

      _articulosEditados[existingIndex] = {
        ...existing,
        'precio': existingPrice,
        'kg': newQuantity,
        'total': newTotal,
        'articuloId':
            existing['articuloId'] ?? normalizedIncoming['articuloId'],
        'codigoBarras':
            (existing['codigoBarras'] ?? '').toString().trim().isNotEmpty
                ? existing['codigoBarras']
                : normalizedIncoming['codigoBarras'],
        'categoria': existingCategory,
      };
    });

    return existingIndex >= 0;
  }

  Future<Map<String, dynamic>> _guardarCambios() async {
    final Map<String, dynamic> ticketActualizado = Map<String, dynamic>.from(
      widget.ticket,
    );

    ticketActualizado['total'] = totalCalculado;
    ticketActualizado['subtotal'] = totalCalculado;
    ticketActualizado['articulos'] = totalArticulos;

    ticketActualizado['items'] =
        _articulosEditados.map((item) {
          final pRaw = item['precio'];
          final kRaw = item['kg'];

          final double p =
              pRaw is num
                  ? pRaw.toDouble()
                  : (double.tryParse(pRaw?.toString() ?? '') ?? 0.0);

          final double k =
              kRaw is num
                  ? kRaw.toDouble()
                  : (double.tryParse(kRaw?.toString() ?? '') ?? 1.0);

          return {
            'nombre': item['nombre'],
            'precio': p,
            'kg': k,
            'articuloId': item['articuloId'],
            'codigoBarras': (item['codigoBarras'] ?? '').toString(),
            'categoria': ProductCategory.normalize(
              item['categoria'],
              barcode: item['codigoBarras'],
            ),
          };
        }).toList();

    await DatabaseHelper().updateTicket(ticketActualizado);

    return ticketActualizado;
  }

  Future<void> _guardarYSalir() async {
    if (_guardando) return;

    setState(() {
      _guardando = true;
    });

    try {
      final ticketActualizado = await _guardarCambios();

      if (!mounted) return;

      Navigator.pop(context, ticketActualizado);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _guardando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar el recibo: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<bool> _confirmarSalidaSinGuardar() async {
    if (!_hayCambiosSinGuardar) {
      return true;
    }

    final String? accion = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange,
              size: 34,
            ),
          ),
          title: const Text(
            'Cambios sin guardar',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text(
            '¿Deseas guardar los cambios antes de salir?',
            textAlign: TextAlign.center,
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('cancelar'),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('descartar'),
              child: const Text(
                'No guardar',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop('guardar'),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (accion == 'guardar') {
      await _guardarYSalir();
      return false;
    }

    if (accion == 'descartar') {
      return true;
    }

    return false;
  }

  Future<void> _salirConValidacion() async {
    final puedeSalir = await _confirmarSalidaSinGuardar();

    if (!mounted) return;

    if (puedeSalir) {
      Navigator.pop(context);
    }
  }

  void _mostrarAvisoProductoAgregado() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Producto agregado correctamente'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hayCambiosSinGuardar,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final puedeSalir = await _confirmarSalidaSinGuardar();

        if (!mounted) return;

        if (puedeSalir) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 1,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back,
              color: Color.fromARGB(255, 0, 0, 0),
            ),
            onPressed: _salirConValidacion,
          ),
          title: const Text(
            'EDITAR RECIBO',
            style: TextStyle(
              color: Color.fromARGB(255, 0, 0, 0),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 10.0,
              ),
              child: ElevatedButton(
                onPressed: _guardando ? null : _guardarYSalir,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  disabledBackgroundColor: Colors.green.shade200,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child:
                    _guardando
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Text(
                          'GUARDAR',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: Colors.white,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _articulosEditados.length,
                  separatorBuilder:
                      (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _articulosEditados[index];
                    final precioRaw = item['precio'];
                    final kgRaw = item['kg'];

                    double precio =
                        precioRaw is num
                            ? precioRaw.toDouble()
                            : (double.tryParse(precioRaw?.toString() ?? '') ??
                                0.0);
                    double cantidad =
                        kgRaw is num
                            ? kgRaw.toDouble()
                            : (double.tryParse(kgRaw?.toString() ?? '') ?? 1.0);
                    final categoria = ProductCategory.normalize(
                      item['categoria'],
                      barcode: item['codigoBarras'],
                    );
                    double itemTotal = precio * cantidad;

                    return ListTile(
                      title: Text(
                        item['nombre'] ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        '${ProductCategory.formatQuantity(cantidad, categoria)} '
                        'x \$${precio.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '\$${itemTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () async {
                              final itemModificado =
                                  await showEditarArticuloTicketDialog(
                                    context: context,
                                    articulo: item,
                                  );

                              if (itemModificado != null) {
                                setState(() {
                                  if (itemModificado['eliminar'] == true) {
                                    _articulosEditados.removeAt(index);
                                  } else {
                                    final pM = itemModificado['precio'];
                                    final kM = itemModificado['kg'];

                                    _articulosEditados[index] = {
                                      ...item,
                                      ...Map<String, dynamic>.from(
                                        itemModificado,
                                      ),
                                      'nombre': itemModificado['nombre'],
                                      'precio':
                                          pM is num
                                              ? pM.toDouble()
                                              : (double.tryParse(
                                                    pM?.toString() ?? '',
                                                  ) ??
                                                  0.0),
                                      'kg':
                                          kM is num
                                              ? kM.toDouble()
                                              : (double.tryParse(
                                                    kM?.toString() ?? '',
                                                  ) ??
                                                  1.0),
                                      'total': itemModificado['total'],
                                      'categoria': ProductCategory.normalize(
                                        itemModificado['categoria'] ??
                                            item['categoria'],
                                        barcode:
                                            itemModificado['codigoBarras'] ??
                                            item['codigoBarras'],
                                      ),
                                    };
                                  }
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final articuloSeleccionado =
                        await Navigator.push<Map<String, dynamic>>(
                          context,
                          MaterialPageRoute(
                            builder:
                                (context) =>
                                    const ArticlesPage(isSelectorMode: true),
                          ),
                        );

                    if (articuloSeleccionado != null) {
                      final yaExistia = _agregarArticuloConPrecioExistente(
                        articuloSeleccionado,
                      );

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              yaExistia
                                  ? 'Cantidad actualizada conservando el precio del recibo.'
                                  : 'Producto agregado correctamente',
                            ),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text(
                    'AÑADIR ARTÍCULO',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total parcial',
                          style: TextStyle(color: Colors.grey, fontSize: 15),
                        ),
                        Text(
                          '\$${totalCalculado.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 15),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total general',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '\$${totalCalculado.roundToDouble().toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
