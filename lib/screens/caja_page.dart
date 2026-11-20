// lib/screens/caja_page.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/database_helper.dart';
import '../utils/product_category.dart';
import 'cobrar_page.dart';
import 'edit_cart_item_modal.dart';
import 'exito_page.dart';

class CajaPage extends StatelessWidget {
  final List<Map<String, dynamic>> cartItems;
  final List<Map<String, dynamic>> cajasClientes;
  final int cajaActivaIndex;
  final VoidCallback onIrAlCatalogo;
  final Future<void> Function(List<Map<String, dynamic>>) onActualizarCarrito;
  final Future<void> Function() onNuevaCaja;
  final Future<void> Function(int index) onSeleccionarCaja;
  final Future<void> Function(int index) onEliminarCaja;
  final Future<void> Function(String nuevoNombre) onRenombrarCajaActiva;
  final int siguienteNumeroCliente;
  final Future<void> Function(Map<String, dynamic>) onVentaExitosa;
  final bool scannerEnabled;

  const CajaPage({
    super.key,
    required this.cartItems,
    required this.cajasClientes,
    required this.cajaActivaIndex,
    required this.onIrAlCatalogo,
    required this.onActualizarCarrito,
    required this.onNuevaCaja,
    required this.onSeleccionarCaja,
    required this.onEliminarCaja,
    required this.onRenombrarCajaActiva,
    required this.siguienteNumeroCliente,
    required this.onVentaExitosa,
    this.scannerEnabled = true,
  });

  String get nombreCajaActiva {
    if (cajasClientes.isEmpty || cajaActivaIndex >= cajasClientes.length) {
      return 'Cliente #$siguienteNumeroCliente';
    }

    final nombre =
        (cajasClientes[cajaActivaIndex]['nombre'] ?? '').toString().trim();
    return nombre.isEmpty ? 'Cliente #$siguienteNumeroCliente' : nombre;
  }

  double get subtotal {
    return cartItems.fold<double>(0, (sum, item) {
      final double precio =
          item['precio'] is num ? (item['precio'] as num).toDouble() : 0.0;
      final double kg =
          item['kg'] is num ? (item['kg'] as num).toDouble() : 0.0;
      final String categoria = ProductCategory.normalize(
        item['categoria'],
        barcode: item['codigoBarras'],
      );

      final double itemTotal =
          ProductCategory.isGrocery(categoria)
              ? precio * kg
              : (item['total'] is num
                  ? (item['total'] as num).toDouble()
                  : precio * kg);

      return sum + itemTotal;
    });
  }

  int get totalDeArticulos => cartItems.length;

  Future<void> _editarNombreCliente(BuildContext context) async {
    final String? nuevoNombre = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar edición del cliente',
      barrierColor: Colors.black.withOpacity(0.48),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        // Ignoramos el viewInsets del teclado para que la tarjeta permanezca
        // siempre en la misma altura y no sea empujada hacia arriba.
        return MediaQuery.removeViewInsets(
          context: dialogContext,
          removeBottom: true,
          child: Align(
            alignment: const Alignment(0, -0.38),
            child: _EditarNombreClienteDialog(nombreInicial: nombreCajaActiva),
          ),
        );
      },
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return FadeTransition(
          opacity: curvedAnimation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curvedAnimation),
            child: child,
          ),
        );
      },
    );

    if (nuevoNombre == null) {
      return;
    }

    final limpio = nuevoNombre.trim();

    if (limpio.isEmpty) {
      await onRenombrarCajaActiva('Cliente #$siguienteNumeroCliente');
    } else {
      await onRenombrarCajaActiva(limpio);
    }
  }

  Future<void> _confirmarEliminarCaja(BuildContext context, int index) async {
    if (index < 0 || index >= cajasClientes.length) {
      return;
    }

    if (cajasClientes.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe quedar al menos una caja abierta.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final caja = cajasClientes[index];
    final String nombre = (caja['nombre'] ?? 'Cliente').toString();
    final List items = caja['items'] is List ? caja['items'] as List : [];

    final bool confirmar =
        await showDialog<bool>(
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
                  color: Colors.redAccent.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.redAccent,
                  size: 34,
                ),
              ),
              title: const Text(
                'Cerrar caja',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Text(
                items.isEmpty
                    ? '¿Deseas cerrar la caja de $nombre?'
                    : 'La caja de $nombre tiene ${items.length} producto(s).\n\n¿Seguro que deseas cerrarla y eliminar sus productos?',
                textAlign: TextAlign.center,
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(false);
                  },
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.of(dialogContext).pop(true);
                  },
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Cerrar caja'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmar || !context.mounted) {
      return;
    }

    await onEliminarCaja(index);

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Se cerró la caja de $nombre'),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmarEliminarTodos(BuildContext context) async {
    if (cartItems.isEmpty) {
      return;
    }

    final bool confirmar =
        await showDialog<bool>(
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
                  color: Colors.redAccent.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_sweep_rounded,
                  color: Colors.redAccent,
                  size: 32,
                ),
              ),
              title: const Text(
                'Vaciar caja',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: const Text(
                '¿Estás seguro de que quieres eliminar todos los productos?\n\n'
                'Esta acción vaciará por completo la lista de la caja activa.',
                textAlign: TextAlign.center,
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(false);
                  },
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.of(dialogContext).pop(true);
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Eliminar todos'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmar || !context.mounted) {
      return;
    }

    await onActualizarCarrito(<Map<String, dynamic>>[]);

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Se vació la caja de $nombreCajaActiva'),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildTabsClientes(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cajasClientes.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == cajasClientes.length) {
            return InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onNuevaCaja,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.add, color: Colors.blue, size: 19),
                    SizedBox(width: 4),
                    Text(
                      'Nueva',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final caja = cajasClientes[index];
          final bool activa = index == cajaActivaIndex;
          final String nombre = (caja['nombre'] ?? 'Cliente').toString();
          final List items = caja['items'] is List ? caja['items'] as List : [];

          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => onSeleccionarCaja(index),
            onLongPress: activa ? () => _editarNombreCliente(context) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: activa ? Colors.blue : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: activa ? Colors.blue : Colors.grey.shade300,
                ),
                boxShadow:
                    activa
                        ? [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.18),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                        : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 18,
                    color: activa ? Colors.white : Colors.black54,
                  ),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 96),
                    child: Text(
                      nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: activa ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color:
                          activa
                              ? Colors.white.withOpacity(0.22)
                              : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '${items.length}',
                      style: TextStyle(
                        color: activa ? Colors.white : Colors.black54,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (cajasClientes.length > 1) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      borderRadius: BorderRadius.circular(99),
                      onTap: () => _confirmarEliminarCaja(context, index),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: activa ? Colors.white : Colors.redAccent,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildClienteActivo(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _editarNombreCliente(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.withOpacity(0.12)),
          ),
          child: Row(
            children: [
              const Icon(Icons.person, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  nombreCajaActiva,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              const Icon(Icons.edit_outlined, color: Colors.blue, size: 19),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTabsClientes(context),
        _buildClienteActivo(context),

        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: ListView.builder(
              itemCount: cartItems.length + 1,
              itemBuilder: (context, index) {
                if (index == cartItems.length) {
                  return Card(
                    color: const Color(0xFFEAF4FF),
                    surfaceTintColor: Colors.transparent,
                    child: InkWell(
                      onTap: onIrAlCatalogo,
                      child: Container(
                        height: 60,
                        alignment: Alignment.center,
                        child: const Text(
                          'Añadir artículo nuevo',
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  );
                }

                final Map<String, dynamic> item = cartItems[index];
                final double precio =
                    item['precio'] is num
                        ? (item['precio'] as num).toDouble()
                        : 0.0;
                final double kg =
                    item['kg'] is num ? (item['kg'] as num).toDouble() : 0.0;
                final String categoria = ProductCategory.normalize(
                  item['categoria'],
                  barcode: item['codigoBarras'],
                );
                final double itemTotal =
                    ProductCategory.isGrocery(categoria)
                        ? precio * kg
                        : (item['total'] is num
                            ? (item['total'] as num).toDouble()
                            : precio * kg);

                return Card(
                  color: index.isEven ? Colors.white : const Color(0xFFF3F4F6),
                  surfaceTintColor: Colors.transparent,
                  child: ListTile(
                    leading:
                        item['image'] != null &&
                                item['image'].toString().isNotEmpty
                            ? Image.file(
                              File(item['image'].toString()),
                              width: 50,
                              height: 50,
                              fit: BoxFit.cover,
                            )
                            : Container(
                              width: 50,
                              height: 50,
                              color: Colors.grey.shade200,
                              child: const Icon(
                                Icons.insert_photo,
                                color: Colors.grey,
                              ),
                            ),
                    title: Text(
                      (item['nombre'] ?? '').toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: ProductCategory.formatEditableQuantity(
                              kg,
                              categoria,
                            ),
                            style: const TextStyle(
                              color: Color(0xFF16A34A),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          TextSpan(
                            text: ' ${ProductCategory.unit(categoria)}',
                            style: const TextStyle(
                              color: Color(0xFF15803D),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const TextSpan(
                            text: '  ×  ',
                            style: TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextSpan(
                            text: '\$${precio.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Color(0xFF2563EB),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () async {
                            final result = await showEditCartItemModal(
                              context: context,
                              nombre: (item['nombre'] ?? '').toString(),
                              precioInicial: precio,
                              kgInicial: kg,
                              categoria: categoria,
                              totalInicial: itemTotal,
                            );

                            if (result != null) {
                              final List<Map<String, dynamic>> copiaCarrito =
                                  List<Map<String, dynamic>>.from(cartItems);

                              if (result['eliminar'] == true) {
                                copiaCarrito.removeAt(index);
                              } else {
                                copiaCarrito[index] = {
                                  ...item,
                                  'precio': result['precio'],
                                  'kg': result['kg'],
                                  'total': result['total'],
                                };
                              }

                              await onActualizarCarrito(copiaCarrito);
                            }
                          },
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '\$${itemTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Row(
            children: [
              const Icon(
                Icons.inventory_2_outlined,
                color: Colors.blue,
                size: 19,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'No. de productos: $totalDeArticulos',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed:
                    cartItems.isEmpty
                        ? null
                        : () => _confirmarEliminarTodos(context),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  disabledForegroundColor: Colors.grey.shade400,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                label: const Text(
                  'Eliminar todos',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Subtotal',
                    style: TextStyle(fontSize: 15, color: Colors.grey),
                  ),
                  Text(
                    '\$${subtotal.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total general',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    '\$${subtotal.round()}',
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

        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: ElevatedButton(
            onPressed:
                cartItems.isEmpty
                    ? null
                    : () async {
                      final resultadoCobro = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) => CobrarPage(
                                totalAPagar: subtotal,
                                siguienteNumeroCliente: siguienteNumeroCliente,
                                clienteInicial: nombreCajaActiva,
                              ),
                        ),
                      );

                      if (resultadoCobro != null &&
                          resultadoCobro['exito'] == true) {
                        final String clienteFinal = resultadoCobro['cliente'];

                        final DateTime ahora = DateTime.now();

                        final String folioUnico =
                            'REC-${ahora.millisecondsSinceEpoch.toString().substring(7)}';

                        final String fechaStr =
                            '${ahora.day.toString().padLeft(2, '0')}/'
                            '${ahora.month.toString().padLeft(2, '0')}/'
                            '${ahora.year}';

                        final String horaStr =
                            '${ahora.hour.toString().padLeft(2, '0')}:'
                            '${ahora.minute.toString().padLeft(2, '0')}';

                        final Map<String, dynamic> nuevoTicket = {
                          'id': folioUnico,
                          'cliente': clienteFinal,
                          'subtotal': subtotal,
                          'total': subtotal,
                          'pago': resultadoCobro['pago'],
                          'cambio': resultadoCobro['cambio'],
                          'articulos': totalDeArticulos,
                          'fecha': fechaStr,
                          'hora': horaStr,
                          'items':
                              cartItems.map((i) {
                                return {
                                  'nombre': i['nombre'],
                                  'precio': i['precio'],
                                  'kg': i['kg'],
                                  'total':
                                      i['total'] is num
                                          ? (i['total'] as num).toDouble()
                                          : ((i['precio'] as num).toDouble() *
                                              (i['kg'] as num).toDouble()),
                                  'articuloId': i['articuloId'],
                                  'codigoBarras':
                                      (i['codigoBarras'] ?? '').toString(),
                                  'categoria': ProductCategory.normalize(
                                    i['categoria'],
                                    barcode: i['codigoBarras'],
                                  ),
                                };
                              }).toList(),
                        };

                        final List<Map<String, dynamic>> itemsParaDB =
                            List<Map<String, dynamic>>.from(
                              nuevoTicket['items'] ?? [],
                            );

                        final Map<String, dynamic> ticketLimpioParaDB =
                            Map<String, dynamic>.from(nuevoTicket);

                        ticketLimpioParaDB.remove('items');
                        ticketLimpioParaDB.remove('articulos');

                        await DatabaseHelper().insertTicket(
                          ticketLimpioParaDB,
                          itemsParaDB,
                        );

                        if (context.mounted) {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => ExitoPage(
                                    ticketId: folioUnico,
                                    cliente: clienteFinal,
                                    total: subtotal,
                                    totalArticulos: totalDeArticulos,
                                    fechaHora: '$fechaStr $horaStr',
                                    venta: nuevoTicket,
                                    onLimpiarCaja: () async {
                                      await onVentaExitosa(nuevoTicket);
                                    },
                                  ),
                            ),
                          );
                        }
                      }
                    },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: Text(
              'Cobrar: \$${subtotal.round()}',
              style: const TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EditarNombreClienteDialog extends StatefulWidget {
  final String nombreInicial;

  const _EditarNombreClienteDialog({required this.nombreInicial});

  @override
  State<_EditarNombreClienteDialog> createState() =>
      _EditarNombreClienteDialogState();
}

class _EditarNombreClienteDialogState
    extends State<_EditarNombreClienteDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  bool _seleccionarTodoEnSiguienteToque = true;
  bool _cerrando = false;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(text: widget.nombreInicial);
    _focusNode = FocusNode(debugLabel: 'nombreCliente');
    _focusNode.addListener(_manejarCambioDeFoco);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _focusNode.requestFocus();
      _seleccionarTodo();
    });
  }

  void _manejarCambioDeFoco() {
    if (!_focusNode.hasFocus) {
      _seleccionarTodoEnSiguienteToque = true;
    }
  }

  void _seleccionarTodo() {
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  void _manejarTapEnCampo() {
    if (!_seleccionarTodoEnSiguienteToque) {
      // Desde el segundo toque, Flutter conserva la posición exacta elegida
      // por el usuario y muestra el cursor donde haya tocado.
      return;
    }

    _seleccionarTodoEnSiguienteToque = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus) {
        return;
      }

      _seleccionarTodo();
    });
  }

  Future<void> _cerrar({String? valor}) async {
    if (_cerrando) {
      return;
    }

    _cerrando = true;
    _focusNode.unfocus(disposition: UnfocusDisposition.scope);
    FocusManager.instance.primaryFocus?.unfocus(
      disposition: UnfocusDisposition.scope,
    );
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await Future<void>.delayed(const Duration(milliseconds: 70));

    if (mounted) {
      Navigator.of(context).pop(valor);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_manejarCambioDeFoco);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double ancho =
        (MediaQuery.sizeOf(context).width - 48).clamp(280.0, 360.0).toDouble();

    return Material(
      color: Colors.transparent,
      child: Container(
        width: ancho,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Nombre del cliente',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: Color(0xFF20242B),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: TextInputType.name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              autocorrect: true,
              enableSuggestions: true,
              onTap: _manejarTapEnCampo,
              onSubmitted: (value) {
                _cerrar(valor: value);
              },
              decoration: const InputDecoration(
                labelText: 'Cliente',
                hintText: 'Ej. Juan Pérez',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    _cerrar();
                  },
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    _cerrar(valor: _controller.text);
                  },
                  child: const Text('Guardar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
