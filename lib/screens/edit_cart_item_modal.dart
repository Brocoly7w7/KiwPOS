// lib/screens/edit_cart_item_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/product_category.dart';

Future<Map<String, dynamic>?> showEditCartItemModal({
  required BuildContext context,
  required String nombre,
  required double precioInicial,
  required double kgInicial,
  String categoria = ProductCategory.fresh,
  double? totalInicial,
}) {
  return showGeneralDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Editar artículo',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return MediaQuery.removeViewInsets(
        context: dialogContext,
        removeBottom: true,
        child: SafeArea(
          child: Align(
            alignment: const Alignment(0, -0.85),
            child: Material(
              color: Colors.transparent,
              child: _EditCartItemForm(
                nombre: nombre,
                precioInicial: precioInicial,
                kgInicial: kgInicial,
                categoria: categoria,
                totalInicial: totalInicial,
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(curvedAnimation),
          child: child,
        ),
      );
    },
  );
}

class _EditCartItemForm extends StatefulWidget {
  final String nombre;
  final double precioInicial;
  final double kgInicial;
  final String categoria;
  final double? totalInicial;

  const _EditCartItemForm({
    required this.nombre,
    required this.precioInicial,
    required this.kgInicial,
    required this.categoria,
    this.totalInicial,
  });

  @override
  State<_EditCartItemForm> createState() => _EditCartItemFormState();
}

class _EditCartItemFormState extends State<_EditCartItemForm> {
  late final TextEditingController _precioController;
  late final TextEditingController _cantidadController;
  late final TextEditingController _totalController;

  final FocusNode _precioFocusNode = FocusNode();
  final FocusNode _cantidadFocusNode = FocusNode();
  final FocusNode _totalFocusNode = FocusNode();

  late double _precio;
  late double _cantidad;
  late double _total;

  bool get _esAbarrote => ProductCategory.isGrocery(widget.categoria);

  @override
  void initState() {
    super.initState();

    _precio = widget.precioInicial;
    _cantidad = ProductCategory.normalizeQuantity(
      widget.kgInicial,
      widget.categoria,
    );
    _total = widget.totalInicial ?? (_precio * _cantidad);

    _precioController = TextEditingController(text: _precio.toStringAsFixed(2));
    _cantidadController = TextEditingController(
      text: ProductCategory.formatEditableQuantity(_cantidad, widget.categoria),
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

  double? _parseNumero(String value) {
    return double.tryParse(value.replaceAll(',', '.').trim());
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

  void _actualizarTexto(TextEditingController controller, String texto) {
    controller.value = TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }

  void _restaurarPrecio() {
    final value = _parseNumero(_precioController.text);
    if (value == null || value <= 0) {
      _actualizarTexto(_precioController, _precio.toStringAsFixed(2));
    }
  }

  void _restaurarCantidad() {
    final value = _parseNumero(_cantidadController.text);
    if (value == null || value <= 0) {
      _actualizarTexto(
        _cantidadController,
        ProductCategory.formatEditableQuantity(_cantidad, widget.categoria),
      );
    }
  }

  void _restaurarTotal() {
    final value = _parseNumero(_totalController.text);
    if (value == null || value <= 0) {
      _actualizarTexto(_totalController, _total.toStringAsFixed(2));
    }
  }

  void _actualizarDesdePrecio(String value) {
    final parsed = _parseNumero(value);
    if (parsed == null || parsed <= 0) return;

    _precio = parsed;
    _total = _precio * _cantidad;
    _actualizarTexto(_totalController, _total.toStringAsFixed(2));
  }

  void _actualizarDesdeCantidad(String value) {
    final parsed = _parseNumero(value);
    if (parsed == null || parsed <= 0) return;

    _cantidad = ProductCategory.normalizeQuantity(
      parsed,
      widget.categoria,
      fallback: _cantidad,
    );
    _total = _precio * _cantidad;
    _actualizarTexto(_totalController, _total.toStringAsFixed(2));
  }

  void _actualizarDesdeTotal(String value) {
    final parsed = _parseNumero(value);
    if (parsed == null || parsed <= 0 || _precio <= 0) return;

    _cantidad = ProductCategory.normalizeQuantity(
      parsed / _precio,
      widget.categoria,
      fallback: _cantidad,
    );
    _total = _esAbarrote ? _precio * _cantidad : parsed;

    _actualizarTexto(
      _cantidadController,
      ProductCategory.formatEditableQuantity(_cantidad, widget.categoria),
    );

    if (_esAbarrote) {
      _actualizarTexto(_totalController, _total.toStringAsFixed(2));
    }
  }

  void _guardarCambios() {
    _restaurarPrecio();
    _restaurarCantidad();
    _restaurarTotal();

    Navigator.pop(context, {
      'eliminar': false,
      'nombre': widget.nombre,
      'precio': _precio,
      'kg': _cantidad,
      'total': _total,
      'categoria': ProductCategory.normalize(widget.categoria),
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

  InputDecoration _decoracionCampo({
    required String label,
    String? prefixText,
  }) {
    return InputDecoration(
      labelText: label,
      prefixText: prefixText,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade400),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.blue, width: 1.8),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430, maxHeight: 560),
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
                padding: const EdgeInsets.fromLTRB(20, 16, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Editar ${widget.nombre}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Eliminar artículo',
                      onPressed: () {
                        Navigator.pop(context, {'eliminar': true});
                      },
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.blue,
                        size: 30,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.grey,
                        size: 31,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
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
                        decoration: _decoracionCampo(
                          label: 'Precio de venta',
                          prefixText: '\$ ',
                        ),
                        onChanged: _actualizarDesdePrecio,
                      ),
                      const SizedBox(height: 14),
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
                        decoration: _decoracionCampo(
                          label:
                              _esAbarrote
                                  ? 'Cantidad en piezas'
                                  : 'Cantidad en kg',
                        ),
                        onChanged: _actualizarDesdeCantidad,
                      ),
                      const SizedBox(height: 14),
                      Icon(
                        Icons.swap_vert_rounded,
                        color: Colors.grey.shade500,
                        size: 30,
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _totalController,
                        focusNode: _totalFocusNode,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.done,
                        decoration: _decoracionCampo(
                          label: 'Precio total',
                          prefixText: '\$ ',
                        ),
                        onChanged: _actualizarDesdeTotal,
                        onSubmitted: (_) => _guardarCambios(),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _esAbarrote
                            ? 'Este producto se vende por piezas enteras.'
                            : 'Este producto se vende por peso en kilogramos.',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
                child: ElevatedButton(
                  onPressed: _guardarCambios,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    elevation: 4,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  child: const Text(
                    'Actualizar artículo',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
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
