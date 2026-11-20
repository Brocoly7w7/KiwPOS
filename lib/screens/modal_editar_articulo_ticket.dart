// lib/screens/modal_editar_articulo_ticket.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/product_category.dart';

Future<Map<String, dynamic>?> showEditarArticuloTicketDialog({
  required BuildContext context,
  required Map<String, dynamic> articulo,
}) {
  return showGeneralDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Editar artículo del recibo',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return MediaQuery.removeViewInsets(
        context: dialogContext,
        removeBottom: true,
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 70),
              child: Material(
                color: Colors.transparent,
                child: ModalEditarArticuloTicket(articulo: articulo),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class ModalEditarArticuloTicket extends StatefulWidget {
  final Map<String, dynamic> articulo;

  const ModalEditarArticuloTicket({super.key, required this.articulo});

  @override
  State<ModalEditarArticuloTicket> createState() =>
      _ModalEditarArticuloTicketState();
}

class _ModalEditarArticuloTicketState extends State<ModalEditarArticuloTicket> {
  late final TextEditingController _precioController;
  late final TextEditingController _cantidadController;
  late final TextEditingController _totalController;

  final FocusNode _precioFocusNode = FocusNode();
  final FocusNode _cantidadFocusNode = FocusNode();
  final FocusNode _totalFocusNode = FocusNode();

  late double _precio;
  late double _cantidad;
  late double _total;
  late String _categoria;

  bool get _esAbarrote => ProductCategory.isGrocery(_categoria);

  @override
  void initState() {
    super.initState();

    _precio = _toDouble(widget.articulo['precio']);
    _categoria = ProductCategory.normalize(
      widget.articulo['categoria'],
      barcode: widget.articulo['codigoBarras'],
    );
    _cantidad = ProductCategory.normalizeQuantity(
      widget.articulo['kg'],
      _categoria,
    );
    _total = _toDouble(widget.articulo['total']);
    if (_total <= 0) {
      _total = _precio * _cantidad;
    }

    _precioController = TextEditingController(text: _precio.toStringAsFixed(2));
    _cantidadController = TextEditingController(
      text: ProductCategory.formatEditableQuantity(_cantidad, _categoria),
    );
    _totalController = TextEditingController(text: _total.toStringAsFixed(2));

    _configurarCampo(_precioFocusNode, _precioController, _restaurarPrecio);
    _configurarCampo(
      _cantidadFocusNode,
      _cantidadController,
      _restaurarCantidad,
    );
    _configurarCampo(_totalFocusNode, _totalController, _restaurarTotal);
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(
          value?.toString().replaceAll(',', '.').trim() ?? '',
        ) ??
        0.0;
  }

  void _seleccionarTodo(TextEditingController controller) {
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  }

  void _configurarCampo(
    FocusNode focusNode,
    TextEditingController controller,
    VoidCallback restoreValue,
  ) {
    focusNode.addListener(() {
      if (focusNode.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && focusNode.hasFocus) {
            _seleccionarTodo(controller);
          }
        });
      } else {
        restoreValue();
      }
    });
  }

  void _setText(TextEditingController controller, String text) {
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _restaurarPrecio() {
    final parsed = _toDouble(_precioController.text);
    if (parsed <= 0) {
      _setText(_precioController, _precio.toStringAsFixed(2));
    }
  }

  void _restaurarCantidad() {
    final parsed = _toDouble(_cantidadController.text);
    if (parsed <= 0) {
      _setText(
        _cantidadController,
        ProductCategory.formatEditableQuantity(_cantidad, _categoria),
      );
    }
  }

  void _restaurarTotal() {
    final parsed = _toDouble(_totalController.text);
    if (parsed <= 0) {
      _setText(_totalController, _total.toStringAsFixed(2));
    }
  }

  void _recalcularConPrecio(String value) {
    final parsed = _toDouble(value);
    if (parsed <= 0) return;

    _precio = parsed;
    _total = _precio * _cantidad;
    _setText(_totalController, _total.toStringAsFixed(2));
  }

  void _recalcularConCantidad(String value) {
    final parsed = _toDouble(value);
    if (parsed <= 0) return;

    _cantidad = ProductCategory.normalizeQuantity(
      parsed,
      _categoria,
      fallback: _cantidad,
    );
    _total = _precio * _cantidad;
    _setText(_totalController, _total.toStringAsFixed(2));
  }

  void _recalcularConTotal(String value) {
    final parsed = _toDouble(value);
    if (parsed <= 0 || _precio <= 0) return;

    _cantidad = ProductCategory.normalizeQuantity(
      parsed / _precio,
      _categoria,
      fallback: _cantidad,
    );
    _total = _esAbarrote ? _precio * _cantidad : parsed;

    _setText(
      _cantidadController,
      ProductCategory.formatEditableQuantity(_cantidad, _categoria),
    );

    if (_esAbarrote) {
      _setText(_totalController, _total.toStringAsFixed(2));
    }
  }

  void _guardar() {
    _restaurarPrecio();
    _restaurarCantidad();
    _restaurarTotal();

    Navigator.pop(context, {
      'nombre': widget.articulo['nombre'],
      'precio': _precio,
      'kg': _cantidad,
      'total': _total,
      'articuloId': widget.articulo['articuloId'],
      'codigoBarras': widget.articulo['codigoBarras'] ?? '',
      'categoria': _categoria,
    });
  }

  @override
  void dispose() {
    _precioFocusNode.dispose();
    _cantidadFocusNode.dispose();
    _totalFocusNode.dispose();
    _precioController.dispose();
    _cantidadController.dispose();
    _totalController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, {String? prefixText}) {
    return InputDecoration(
      labelText: label,
      prefixText: prefixText,
      border: const OutlineInputBorder(),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430, maxHeight: 455),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.22),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Editar ${widget.articulo['nombre']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Eliminar artículo',
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.red,
                        size: 29,
                      ),
                      onPressed: () {
                        Navigator.pop(context, {'eliminar': true});
                      },
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.grey,
                        size: 29,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.grey.shade300),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: _precioController,
                        focusNode: _precioFocusNode,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.next,
                        decoration: _decoration(
                          'Precio de venta',
                          prefixText: '\$ ',
                        ),
                        onChanged: _recalcularConPrecio,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _cantidadController,
                        focusNode: _cantidadFocusNode,
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: !_esAbarrote,
                        ),
                        inputFormatters:
                            _esAbarrote
                                ? <TextInputFormatter>[
                                  FilteringTextInputFormatter.digitsOnly,
                                ]
                                : null,
                        textInputAction: TextInputAction.next,
                        decoration: _decoration(
                          _esAbarrote ? 'Cantidad en piezas' : 'Cantidad en kg',
                        ),
                        onChanged: _recalcularConCantidad,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _totalController,
                        focusNode: _totalFocusNode,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.done,
                        decoration: _decoration(
                          'Precio total',
                          prefixText: '\$ ',
                        ),
                        onChanged: _recalcularConTotal,
                        onSubmitted: (_) => _guardar(),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton(
                        onPressed: _guardar,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Actualizar artículo',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
