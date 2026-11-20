import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../db/database_helper.dart';
import '../utils/product_category.dart';

class AddArticlePage extends StatefulWidget {
  final String? nombreInicial;
  final double? precioInicial;
  final File? imagenInicial;
  final int? articuloId;
  final String? codigoBarrasInicial;
  final String? categoriaInicial;

  const AddArticlePage({
    super.key,
    this.nombreInicial,
    this.precioInicial,
    this.imagenInicial,
    this.articuloId,
    this.codigoBarrasInicial,
    this.categoriaInicial,
  });

  @override
  State<AddArticlePage> createState() => _AddArticlePageState();
}

class _AddArticlePageState extends State<AddArticlePage> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  late final TextEditingController _nombreController;
  late final TextEditingController _precioController;
  late final TextEditingController _codigoBarrasController;

  final FocusNode _nombreFocusNode = FocusNode(
    debugLabel: 'articleName',
  );
  final FocusNode _precioFocusNode = FocusNode(
    debugLabel: 'articlePrice',
  );
  final FocusNode _codigoBarrasFocusNode = FocusNode(
    debugLabel: 'articleBarcode',
  );

  File? _image;
  late String _categoria;
  late bool _categoriaEditadaManualmente;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();

    _nombreController = TextEditingController(text: widget.nombreInicial ?? '');
    _precioController = TextEditingController(
      text: widget.precioInicial?.toString() ?? '',
    );
    _codigoBarrasController = TextEditingController(
      text: widget.codigoBarrasInicial ?? '',
    );
    _image = widget.imagenInicial;

    _categoria = ProductCategory.normalize(
      widget.categoriaInicial,
      barcode: widget.codigoBarrasInicial,
    );
    _categoriaEditadaManualmente = widget.categoriaInicial != null;

    _codigoBarrasController.addListener(_actualizarCategoriaAutomatica);
  }

  void _actualizarCategoriaAutomatica() {
    if (_categoriaEditadaManualmente || !mounted) return;

    final nuevaCategoria = ProductCategory.normalize(
      null,
      barcode: _codigoBarrasController.text,
    );

    if (nuevaCategoria != _categoria) {
      setState(() => _categoria = nuevaCategoria);
    }
  }

  @override
  void dispose() {
    _codigoBarrasController.removeListener(_actualizarCategoriaAutomatica);
    _nombreFocusNode.dispose();
    _precioFocusNode.dispose();
    _codigoBarrasFocusNode.dispose();
    _nombreController.dispose();
    _precioController.dispose();
    _codigoBarrasController.dispose();
    super.dispose();
  }

  Future<void> _seleccionarImagen() async {
    try {
      final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null && mounted) {
        setState(() => _image = File(pickedFile.path));
      }
    } catch (error) {
      debugPrint('Error al seleccionar imagen: $error');
    }
  }

  Future<void> _cerrarEntradaAntesDeSalir() async {
    _nombreFocusNode.unfocus(disposition: UnfocusDisposition.scope);
    _precioFocusNode.unfocus(disposition: UnfocusDisposition.scope);
    _codigoBarrasFocusNode.unfocus(
      disposition: UnfocusDisposition.scope,
    );
    FocusManager.instance.primaryFocus?.unfocus(
      disposition: UnfocusDisposition.scope,
    );
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  Future<void> _cerrarPagina() async {
    await _cerrarEntradaAntesDeSalir();

    if (mounted) {
      Navigator.maybePop(context);
    }
  }

  Future<void> _guardarArticulo() async {
    if (_guardando || !(_formKey.currentState?.validate() ?? false)) return;

    await _cerrarEntradaAntesDeSalir();
    if (!mounted) return;

    setState(() => _guardando = true);

    final nombre = _nombreController.text.trim();
    final precio = double.tryParse(_precioController.text) ?? 0.0;
    final imagePath = _image?.path ?? '';
    final codigoBarras = _codigoBarrasController.text.trim();
    final helper = DatabaseHelper();

    int? articuloId = widget.articuloId;

    try {
      if (articuloId == null && widget.nombreInicial != null) {
        final db = await helper.database;
        final existing = await db.query(
          'articulos',
          columns: const ['id'],
          where: 'nombre = ?',
          whereArgs: [widget.nombreInicial],
          limit: 1,
        );

        if (existing.isNotEmpty && existing.first['id'] is int) {
          articuloId = existing.first['id'] as int;
        }
      }

      final duplicate = await helper.codigoBarrasExiste(
        codigoBarras,
        excluirId: articuloId,
      );

      if (duplicate) {
        throw StateError(
          'Ese código de barras ya está asignado a otro artículo.',
        );
      }

      final articulo = <String, dynamic>{
        'nombre': nombre,
        'precio': precio,
        'descripcion': '',
        'image': imagePath,
        'codigoBarras': codigoBarras,
        'categoria': _categoria,
      };

      if (articuloId != null) {
        await helper.updateArticulo({'id': articuloId, ...articulo});

        await _cerrarEntradaAntesDeSalir();

        if (mounted) {
          Navigator.pop(context, {
            'id': articuloId,
            'nombre': nombre,
            'precio': precio,
            'image': _image,
            'codigoBarras': codigoBarras,
            'categoria': _categoria,
          });
        }
      } else {
        await helper.insertArticulo(articulo);
        await _cerrarEntradaAntesDeSalir();

        if (mounted) {
          Navigator.pop(context, true);
        }
      }
    } on StateError catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar el artículo: $error'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Widget _buildCategorySelector() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Categoría del producto',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _categoria,
            isExpanded: true,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.category_outlined),
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
            ),
            items: const [
              DropdownMenuItem(
                value: ProductCategory.groceries,
                child: Text(
                  'Abarrotes',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DropdownMenuItem(
                value: ProductCategory.fresh,
                child: Text(
                  'Productos frescos',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _categoria = value;
                _categoriaEditadaManualmente = true;
              });
            },
          ),
          const SizedBox(height: 8),
          Text(
            ProductCategory.description(_categoria),
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageSection() {
    if (_image == null) {
      return GestureDetector(
        onTap: _seleccionarImagen,
        child: Container(
          height: 180,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[300]!, width: 1.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_a_photo_outlined,
                size: 42,
                color: Colors.grey[500],
              ),
              const SizedBox(height: 8),
              Text(
                'Presiona para añadir una imagen',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        GestureDetector(
          onTap: _seleccionarImagen,
          child: Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(_image!, fit: BoxFit.cover),
            ),
          ),
        ),
        Positioned(
          top: 10,
          right: 10,
          child: IconButton.filledTonal(
            onPressed: () => setState(() => _image = null),
            icon: const Icon(Icons.delete_outline_rounded),
            color: Colors.redAccent,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Regresar',
          onPressed: _cerrarPagina,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          widget.nombreInicial != null ? 'Editar Artículo' : 'Nuevo Artículo',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SelectAllOnFirstTapFormField(
                  controller: _nombreController,
                  focusNode: _nombreFocusNode,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Nombre del artículo *',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Campo requerido'
                      : null,
                ),
                const SizedBox(height: 16),
                _SelectAllOnFirstTapFormField(
                  controller: _precioController,
                  focusNode: _precioFocusNode,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Precio de venta *',
                    prefixText: '\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    final price = double.tryParse(value ?? '');
                    return price == null || price < 0
                        ? 'Ingresa un precio válido'
                        : null;
                  },
                ),
                const SizedBox(height: 16),
                _SelectAllOnFirstTapFormField(
                  controller: _codigoBarrasController,
                  focusNode: _codigoBarrasFocusNode,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Código de barras',
                    hintText: 'Toca aquí y escanea con el lector',
                    prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
                    suffixIcon: IconButton(
                      tooltip: 'Limpiar código',
                      onPressed: _codigoBarrasController.clear,
                      icon: const Icon(Icons.close_rounded),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
                ),
                const SizedBox(height: 8),
                const Text(
                  'El lector Bluetooth HID funciona como teclado: coloca el '
                  'cursor en este campo y escanea.',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 12.5,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 18),
                _buildCategorySelector(),
                const SizedBox(height: 24),
                _buildImageSection(),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _guardando ? null : _guardarArticulo,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: _guardando
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Guardar Artículo',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectAllOnFirstTapFormField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final TextCapitalization textCapitalization;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final InputDecoration decoration;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onFieldSubmitted;

  const _SelectAllOnFirstTapFormField({
    required this.controller,
    required this.focusNode,
    required this.decoration,
    this.textCapitalization = TextCapitalization.none,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onFieldSubmitted,
  });

  @override
  State<_SelectAllOnFirstTapFormField> createState() =>
      _SelectAllOnFirstTapFormFieldState();
}

class _SelectAllOnFirstTapFormFieldState
    extends State<_SelectAllOnFirstTapFormField> {
  bool _selectAllOnNextTap = true;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _SelectAllOnFirstTapFormField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChanged);
      widget.focusNode.addListener(_handleFocusChanged);
      _selectAllOnNextTap = true;
    }
  }

  void _handleFocusChanged() {
    if (!widget.focusNode.hasFocus) {
      _selectAllOnNextTap = true;
    }
  }

  void _handleTap() {
    if (!_selectAllOnNextTap) {
      // A partir del segundo toque, Flutter deja el cursor exactamente
      // en la posición seleccionada por el usuario.
      return;
    }

    _selectAllOnNextTap = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.focusNode.hasFocus) {
        return;
      }

      widget.controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      textCapitalization: widget.textCapitalization,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      decoration: widget.decoration,
      validator: widget.validator,
      onFieldSubmitted: widget.onFieldSubmitted,
      onTap: _handleTap,
    );
  }
}

