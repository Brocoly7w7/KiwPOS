// lib/screens/seleccionar_articulo_ticket_page.dart
import 'package:flutter/material.dart';

import '../utils/product_category.dart';

class SeleccionarArticuloTicketPage extends StatelessWidget {
  final List<Map<String, dynamic>> catalogo;

  const SeleccionarArticuloTicketPage({super.key, required this.catalogo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '¿Qué quiere vender?',
          style: TextStyle(fontSize: 16),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body:
          catalogo.isEmpty
              ? const Center(
                child: Text('No hay artículos cargados en el catálogo.'),
              )
              : GridView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: catalogo.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.75,
                ),
                itemBuilder: (context, index) {
                  final prod = catalogo[index];
                  return Card(
                    elevation: 1,
                    child: InkWell(
                      onTap: () {
                        final precio = prod['precio'] is num
                            ? (prod['precio'] as num).toDouble()
                            : double.tryParse(
                                  prod['precio']?.toString() ?? '',
                                ) ??
                                0.0;
                        final codigoBarras =
                            (prod['codigoBarras'] ?? '').toString();
                        final categoria = ProductCategory.normalize(
                          prod['categoria'],
                          barcode: codigoBarras,
                        );

                        Navigator.pop(context, {
                          'nombre': prod['nombre'],
                          'precio': precio,
                          'kg': 1.0,
                          'total': precio,
                          'articuloId': prod['id'] ?? prod['articuloId'],
                          'codigoBarras': codigoBarras,
                          'categoria': categoria,
                        });
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.insert_photo,
                            size: 40,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            prod['nombre'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '\$${(prod['precio'] as num).toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.blue),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
    );
  }
}
