import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/product_category.dart';
import 'add_article_page.dart';

Future<Map<String, dynamic>?> showArticleDetailModal(
  BuildContext context,
  String nombre,
  double precio,
  File? image,
  int index, {
  int? articuloId,
  String codigoBarras = '',
  String categoria = ProductCategory.fresh,
}) async {
  final normalizedCategory = ProductCategory.normalize(
    categoria,
    barcode: codigoBarras,
  );
  final bool isGrocery = ProductCategory.isGrocery(normalizedCategory);

  // CONTROLADORES DE LOS CAMPOS DE TEXTO
  final TextEditingController kgController = TextEditingController(text: '1');
  final TextEditingController totalController = TextEditingController(
    text: precio.toStringAsFixed(2),
  );
  final FocusNode kgFocusNode = FocusNode();
  final FocusNode totalFocusNode = FocusNode();

  Future<void> releaseTextInput() async {
    kgFocusNode.unfocus(disposition: UnfocusDisposition.scope);
    totalFocusNode.unfocus(disposition: UnfocusDisposition.scope);
    FocusManager.instance.primaryFocus?.unfocus(
      disposition: UnfocusDisposition.scope,
    );
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  double cantidadExacta = 1.0;
  double totalExacto = precio;
  bool totalFueElUltimoCampoEditado = false;

  void selectAll(TextEditingController controller) {
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  }

  void configureNumericFocus(
    FocusNode focusNode,
    TextEditingController controller,
    VoidCallback restoreValue,
  ) {
    focusNode.addListener(() {
      if (focusNode.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (focusNode.hasFocus) {
            selectAll(controller);
          }
        });
      } else {
        restoreValue();
      }
    });
  }

  void restoreQuantity() {
    final parsed = double.tryParse(
      kgController.text.replaceAll(',', '.').trim(),
    );

    if (parsed == null || parsed <= 0) {
      kgController.text = ProductCategory.formatEditableQuantity(
        cantidadExacta,
        normalizedCategory,
      );
    }
  }

  void restoreTotal() {
    final parsed = double.tryParse(
      totalController.text.replaceAll(',', '.').trim(),
    );

    if (parsed == null || parsed <= 0) {
      totalController.text = totalExacto.toStringAsFixed(2);
    }
  }

  configureNumericFocus(kgFocusNode, kgController, restoreQuantity);
  configureNumericFocus(totalFocusNode, totalController, restoreTotal);

  double dragStartPos = 0.0;

  final result = await showGeneralDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: true, // Cierra al tocar el fondo
    barrierLabel: 'Cerrar Modal',
    barrierColor: Colors.black.withOpacity(
      0.4,
    ), // Fondo semitransparente premium
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, animation, secondaryAnimation) {
      return const SizedBox.shrink();
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return ScaleTransition(
        scale: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: Align(
              // Alineación vertical constante para que no salte al activar el teclado
              alignment: Alignment(0, image != null ? -0.58 : -0.12),
              child: SingleChildScrollView(
                physics:
                    const NeverScrollableScrollPhysics(), // Totalmente estática contra el teclado
                child: GestureDetector(
                  // CAPTURA DEL GESTO DE DESLIZAMIENTO HACIA ABAJO PARA CERRAR
                  onVerticalDragStart: (details) {
                    dragStartPos = details.globalPosition.dy;
                  },
                  onVerticalDragUpdate: (details) {
                    if (details.globalPosition.dy - dragStartPos > 70) {
                      Navigator.pop(context);
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    // Eliminamos el SizedBox de altura fija para que la tarjeta abrace el contenido orgánicamente
                    child: Material(
                      color: Colors.transparent,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize:
                              MainAxisSize
                                  .min, // Ajuste dinámico exacto al contenido
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // LÍNEA SUPERIOR DE ARRASTRE DE DISEÑO
                            Center(
                              child: Container(
                                width: 45,
                                height: 5,
                                margin: const EdgeInsets.only(bottom: 14),
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),

                            // ENCABEZADO: Título Principal
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                // ENCABEZADO: Título Principal Centrado
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 40,
                                  ), // Evita que choque con el botón
                                  child: Text(
                                    nombre.toUpperCase(),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                      letterSpacing: 0.5,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                // BOTÓN DE BORRADO ROJO (Posicionado a la derecha exacta)
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  bottom: 0,
                                  child: IconButton(
                                    onPressed: () {
                                      // LANZA EL DIÁLOGO DE RECONFIRMACIÓN
                                      showDialog(
                                        context: context,
                                        builder: (BuildContext dialogContext) {
                                          return AlertDialog(
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            title: const Row(
                                              children: [
                                                Icon(
                                                  Icons.warning_amber_rounded,
                                                  color: Colors.red,
                                                ),
                                                SizedBox(width: 8),
                                                Text('Eliminar Artículo'),
                                              ],
                                            ),
                                            content: Text(
                                              '¿Estás seguro que quieres borrar el artículo "$nombre"?',
                                              style: const TextStyle(
                                                fontSize: 16,
                                              ),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed:
                                                    () => Navigator.pop(
                                                      dialogContext,
                                                    ), // Solo cierra la alerta
                                                child: const Text(
                                                  'CANCELAR',
                                                  style: TextStyle(
                                                    color: Colors.grey,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              ElevatedButton(
                                                onPressed: () async {
                                                  Navigator.pop(
                                                    dialogContext,
                                                  ); // Cierra la alerta
                                                  await releaseTextInput();
                                                  if (!context.mounted) return;
                                                  // Cierra este modal de detalle indicando que fue borrado directamente
                                                  Navigator.pop(context, {
                                                    'wasDeletedDirectly': true,
                                                    'index': index,
                                                  });
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.red,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                ),
                                                child: const Text(
                                                  'SÍ, ELIMINAR',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.delete_forever,
                                      color: Colors.redAccent,
                                      size: 26,
                                    ),
                                    tooltip: 'Eliminar Artículo',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Center(
                              child: Chip(
                                avatar: Icon(
                                  isGrocery
                                      ? Icons.inventory_2_outlined
                                      : Icons.eco_outlined,
                                  size: 17,
                                ),
                                label: Text(
                                  ProductCategory.label(normalizedCategory),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            const SizedBox(height: 10),

                            // IMAGEN DINÁMICA (Solo ocupa espacio real si existe)
                            if (image != null) ...[
                              Container(
                                height: 160,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  image: DecorationImage(
                                    image: FileImage(image),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(
                                height: 14,
                              ), // Espaciado orgánico post-imagen
                            ],

                            // TARJETA DE PRECIO UNITARIO BASE
                            Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.blue.withOpacity(0.15),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    isGrocery
                                        ? 'Precio por pieza:'
                                        : 'Precio por kg:',
                                    style: const TextStyle(
                                      color: Colors.blueGrey,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '\$${precio.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Colors.blue,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // SECCIÓN DE ENTRADAS FORMULARIOS LADO A LADO
                            Row(
                              children: [
                                // Campo Kilogramos
                                Expanded(
                                  child: TextField(
                                    controller: kgController,
                                    focusNode: kgFocusNode,
                                    keyboardType:
                                        TextInputType.numberWithOptions(
                                          decimal: !isGrocery,
                                        ),
                                    inputFormatters: isGrocery
                                        ? <TextInputFormatter>[
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                          ]
                                        : null,
                                    textAlign: TextAlign.left,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    decoration: InputDecoration(
                                      labelText: isGrocery ? 'Cantidad PZ' : 'Cantidad KG',
                                      floatingLabelBehavior:
                                          FloatingLabelBehavior.always,
                                      prefixIcon: Icon(
                                        isGrocery
                                            ? Icons.inventory_2_outlined
                                            : Icons.scale,
                                        color: Colors.blue,
                                        size: 20,
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(
                                          color: Colors.blue,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    onChanged: (value) {
                                      final parsed = double.tryParse(
                                        value.replaceAll(',', '.').trim(),
                                      );

                                      if (parsed == null || parsed <= 0) {
                                        return;
                                      }

                                      cantidadExacta =
                                          ProductCategory.normalizeQuantity(
                                            parsed,
                                            normalizedCategory,
                                          );
                                      totalExacto = cantidadExacta * precio;
                                      totalFueElUltimoCampoEditado = false;

                                      totalController.text =
                                          totalExacto.toStringAsFixed(2);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Campo Dinero Total
                                Expanded(
                                  child: TextField(
                                    controller: totalController,
                                    focusNode: totalFocusNode,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    textAlign: TextAlign.left,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.green,
                                    ),
                                    decoration: InputDecoration(
                                      labelText: 'Total \$',
                                      floatingLabelBehavior:
                                          FloatingLabelBehavior.always,
                                      prefixIcon: const Icon(
                                        Icons.attach_money,
                                        color: Colors.green,
                                        size: 20,
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(
                                          color: Colors.green,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    onChanged: (value) {
                                      final dineroTotal = double.tryParse(
                                        value.replaceAll(',', '.').trim(),
                                      );

                                      if (dineroTotal == null ||
                                          dineroTotal <= 0 ||
                                          precio <= 0) {
                                        return;
                                      }

                                      cantidadExacta =
                                          ProductCategory.normalizeQuantity(
                                            dineroTotal / precio,
                                            normalizedCategory,
                                          );

                                      totalExacto = isGrocery
                                          ? cantidadExacta * precio
                                          : dineroTotal;
                                      totalFueElUltimoCampoEditado = true;

                                      kgController.text =
                                          ProductCategory
                                              .formatEditableQuantity(
                                                cantidadExacta,
                                                normalizedCategory,
                                              );
                                    },
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(
                              height: 20,
                            ), // Separación limpia y fija antes de los botones
                            // BOTONES DE ACCIÓN INFERIORES
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    FocusScope.of(context).unfocus();

                                    await Future.delayed(
                                      const Duration(milliseconds: 50),
                                    );

                                    if (!context.mounted) return;
                                    final updated = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (context) => AddArticlePage(
                                              nombreInicial: nombre,
                                              precioInicial: precio,
                                              imagenInicial: image,
                                              articuloId: articuloId,
                                              codigoBarrasInicial:
                                                  codigoBarras,
                                              categoriaInicial:
                                                  normalizedCategory,
                                            ),
                                      ),
                                    );
                                    if (!context.mounted) return;
                                    if (updated != null) {
                                      await releaseTextInput();
                                      if (!context.mounted) return;
                                      Navigator.pop(context, {
                                        'updatedArticle': {
                                          'nombre': updated['nombre'],
                                          'precio': updated['precio'],
                                          'image':
                                              updated['image'] is File
                                                  ? updated['image'].path
                                                  : updated['image']
                                                          ?.toString() ??
                                                      '',
                                          'kg': 1.0,
                                          'id': updated['id'] ?? articuloId,
                                          'codigoBarras':
                                              updated['codigoBarras'] ??
                                              codigoBarras,
                                          'categoria':
                                              updated['categoria'] ??
                                              normalizedCategory,
                                        },
                                        'index': index,
                                        'wasEditedDirectly': true,
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.edit_note, size: 20),
                                  label: const Text('EDITAR'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 14,
                                    ),
                                    side: BorderSide(color: Colors.grey[400]!),
                                    foregroundColor: Colors.grey[700],
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      FocusScope.of(context).unfocus();

                                      await Future.delayed(
                                        const Duration(milliseconds: 50),
                                      );

                                      final cantidad =
                                          totalFueElUltimoCampoEditado
                                          ? cantidadExacta
                                          : ProductCategory.normalizeQuantity(
                                              kgController.text,
                                              normalizedCategory,
                                            );

                                      final totalFinal =
                                          totalFueElUltimoCampoEditado
                                          ? totalExacto
                                          : precio * cantidad;

                                      if (!context.mounted) return;
                                      await releaseTextInput();
                                      if (!context.mounted) return;
                                      Navigator.pop(context, {
                                        'updatedArticle': {
                                          'nombre': nombre,
                                          'precio': precio,
                                          'image': image?.path ?? '',
                                          'kg': cantidad,
                                          'total': totalFinal,
                                          'id': articuloId,
                                          'codigoBarras': codigoBarras,
                                          'categoria': normalizedCategory,
                                        },
                                        'index': index,
                                        'wasEditedDirectly': false,
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.shopping_cart_checkout,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'AGREGAR A CAJA',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      backgroundColor: Colors.blue,
                                      elevation: 1,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      );
    },
  );

  await releaseTextInput();

  // El Future de la ruta se completa antes de que termine la animación de
  // salida. Esperamos a que el modal se desmonte antes de liberar los
  // controladores para evitar errores durante el cierre.
  await Future<void>.delayed(const Duration(milliseconds: 230));
  kgFocusNode.dispose();
  totalFocusNode.dispose();
  kgController.dispose();
  totalController.dispose();

  return result;
}
