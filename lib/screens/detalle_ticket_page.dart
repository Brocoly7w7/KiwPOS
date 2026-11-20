// lib/screens/detalle_ticket_page.dart
import 'package:flutter/material.dart';
import 'config_factura_page.dart';
import 'editar_recibo_page.dart';
import '../services/bluetooth_print_service.dart';
import '../services/ticket_pdf_service.dart';
import '../db/database_helper.dart';
import '../utils/product_category.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';

class DetalleTicketPage extends StatefulWidget {
  final Map<String, dynamic> venta;
  final String nombreNegocioInicial;
  final String direccionInicial;
  final Function(String, String) onConfigGuardada;
  final List<Map<String, dynamic>> catalogoGlobal;

  const DetalleTicketPage({
    super.key,
    required this.venta,
    required this.nombreNegocioInicial,
    required this.direccionInicial,
    required this.onConfigGuardada,
    this.catalogoGlobal = const [],
  });

  @override
  State<DetalleTicketPage> createState() => _DetalleTicketPageState();
}

class _DetalleTicketPageState extends State<DetalleTicketPage> {
  // Instancia del servicio bluetooth
  final BluetoothPrintService _bluetoothService = BluetoothPrintService();
  bool _generandoArchivo = false;

  Future<bool> _imprimirConDispositivo(
    BluetoothDevice dispositivo,
  ) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Reconectando con ${dispositivo.name ?? 'la impresora'}...',
        ),
        duration: const Duration(seconds: 20),
      ),
    );

    final impreso = await _bluetoothService.imprimirTicketConReconexion(
      dispositivo: dispositivo,
      venta: _ticketLocal,
      negocio: _nombreNegocio,
      direccion: _direccion,
    );

    if (!mounted) return impreso;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          impreso
              ? 'Ticket enviado correctamente.'
              : 'No fue posible reconectar. Acércate a la impresora e inténtalo nuevamente.',
        ),
        backgroundColor: impreso ? Colors.green : Colors.redAccent,
      ),
    );

    return impreso;
  }

  Future<void> _mostrarSelectorImpresora() async {
    try {
      final dispositivos =
          await _bluetoothService.obtenerDispositivos();

      if (!mounted) return;

      if (dispositivos.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No hay impresoras Bluetooth vinculadas. Agrégala desde los ajustes del teléfono.',
            ),
          ),
        );
        return;
      }

      await showModalBottomSheet<void>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (bottomSheetContext) {
          return SafeArea(
            child: SizedBox(
              height: 310,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Selecciona tu impresora POS',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'La aplicación la recordará mientras permanezca abierta.',
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        itemCount: dispositivos.length,
                        itemBuilder: (itemContext, index) {
                          final dispositivo = dispositivos[index];

                          return ListTile(
                            leading: const Icon(
                              Icons.print,
                              color: Colors.blue,
                            ),
                            title: Text(
                              dispositivo.name ??
                                  'Dispositivo desconocido',
                            ),
                            subtitle: Text(dispositivo.address ?? ''),
                            onTap: () async {
                              Navigator.pop(bottomSheetContext);
                              await _imprimirConDispositivo(dispositivo);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error de Bluetooth: $e')),
      );
    }
  }

  Future<void> _imprimirPorBluetooth() async {
    final recordada = _bluetoothService.ultimoDispositivo;

    if (recordada != null) {
      final impreso = await _imprimirConDispositivo(recordada);
      if (impreso) return;
    }

    if (mounted) {
      await _mostrarSelectorImpresora();
    }
  }

  Future<void> _compartirTicket() async {
    if (_generandoArchivo) return;

    setState(() {
      _generandoArchivo = true;
    });

    try {
      await TicketPdfService.shareTicket(
        ticket: _ticketLocal,
        businessName: _nombreNegocio,
        businessAddress: _direccion,
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo compartir el ticket: $error'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _generandoArchivo = false;
        });
      }
    }
  }

  Future<void> _descargarTicket() async {
    if (_generandoArchivo) return;

    setState(() {
      _generandoArchivo = true;
    });

    try {
      final ruta = await TicketPdfService.saveTicket(
        ticket: _ticketLocal,
        businessName: _nombreNegocio,
        businessAddress: _direccion,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ruta.isEmpty
                ? 'Ticket guardado correctamente.'
                : 'Ticket guardado correctamente en:\n$ruta',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar el ticket: $error'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _generandoArchivo = false;
        });
      }
    }
  }

  late String _nombreNegocio;
  late String _direccion;
  // Creamos una copia local reactiva del ticket para manejar la edición síncrona
  late Map<String, dynamic> _ticketLocal;

  @override
  void initState() {
    super.initState();
    _nombreNegocio = widget.nombreNegocioInicial;
    _direccion = widget.direccionInicial;
    _ticketLocal = Map<String, dynamic>.from(widget.venta);
    _cargarConfiguracionFactura();
  }

  Future<void> _cargarConfiguracionFactura() async {
    final config = await DatabaseHelper().getFacturaConfig();

    if (!mounted) return;

    setState(() {
      _nombreNegocio = config['nombreNegocio'] ?? _nombreNegocio;
      _direccion = config['direccionNegocio'] ?? _direccion;
    });
  }

  String _formatCantidad(
    double cantidad, {
    dynamic categoria,
    dynamic codigoBarras,
  }) {
    final normalizedCategory = ProductCategory.normalize(
      categoria,
      barcode: codigoBarras,
    );

    return ProductCategory.formatQuantity(
      cantidad,
      normalizedCategory,
    );
  }

  String _formatDinero(double valor) {
    if (valor == valor.toInt()) {
      return valor.toInt().toString();
    } else {
      return valor.toStringAsFixed(2);
    }
  }

  @override
  Widget build(BuildContext context) {
    double subtotalValue =
        (_ticketLocal['subtotal'] ?? _ticketLocal['total'] ?? 0.0).toDouble();

    double totalValue =
        (_ticketLocal['total'] ?? subtotalValue).roundToDouble();

    double pagoConValue =
        (_ticketLocal['pago'] ?? _ticketLocal['pagoCon'] ?? 0.0).toDouble();

    double cambioValue =
        (_ticketLocal['cambio'] ?? 0.0).toDouble().roundToDouble();

    List<dynamic> items = _ticketLocal['items'] ?? [];

    int numeroArticulos =
        items.isEmpty
            ? ((_ticketLocal['articulos'] ?? 1) as num).toInt()
            : items.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Al usar el botón físico/nativo de atrás del dispositivo, regresamos el ticket actualizado
        Navigator.pop(context, _ticketLocal);
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade200,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 1,
          title: Text(
            'Ticket: ${_ticketLocal['id']}',
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black87),
            onPressed:
                () => Navigator.pop(
                  context,
                  _ticketLocal,
                ), // Retorna el ticket editado al historial
          ),
          actions: [
            IconButton(
              tooltip: 'Compartir ticket en PDF',
              icon: const Icon(Icons.share, color: Colors.blue),
              onPressed: _generandoArchivo ? null : _compartirTicket,
            ),
            IconButton(
              tooltip: 'Guardar ticket en PDF',
              icon: const Icon(Icons.file_download, color: Colors.blue),
              onPressed: _generandoArchivo ? null : _descargarTicket,
            ),
            IconButton(
              icon: const Icon(Icons.print, color: Colors.blue),
              onPressed: _imprimirPorBluetooth, // <--- LISTO CONECTADO
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.black87),
              onSelected: (value) async {
                if (value == 'config') {
                  final resultado = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => ConfigFacturaPage(
                            nombreActual: _nombreNegocio,
                            direccionActual: _direccion,
                          ),
                    ),
                  );

                  if (resultado != null) {
                    setState(() {
                      _nombreNegocio = resultado['nombre'];
                      _direccion = resultado['direccion'];
                    });

                    widget.onConfigGuardada(_nombreNegocio, _direccion);

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Configuración guardada correctamente'),
                          backgroundColor: Colors.green,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                }
              },
              itemBuilder:
                  (BuildContext context) => [
                    const PopupMenuItem<String>(
                      value: 'config',
                      child: Row(
                        children: [
                          Icon(Icons.settings, color: Colors.black54, size: 20),
                          SizedBox(width: 8),
                          Text('Configuración de factura'),
                        ],
                      ),
                    ),
                  ],
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (BuildContext dialogContext) {
                              return AlertDialog(
                                title: const Text('¿Eliminar Ticket?'),
                                content: Text(
                                  '¿Estás seguro de que deseas borrar permanentemente el folio ${_ticketLocal['id']}?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed:
                                        () => Navigator.pop(dialogContext),
                                    child: const Text('CANCELAR'),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(dialogContext);
                                      Navigator.pop(context, {
                                        'borrar': true,
                                        'id': _ticketLocal['id'],
                                      });
                                    },
                                    child: const Text(
                                      'BORRAR',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: const Text(
                          'BORRAR',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () async {
                          Map<String, dynamic> ticketParaEditar = {
                            'id':
                                _ticketLocal['id'], // Preservamos campos originales de auditoría
                            'fecha': _ticketLocal['fecha'],
                            'hora': _ticketLocal['hora'],
                            'cliente':
                                _ticketLocal['cliente'] ?? 'Cliente Gral',
                            'pago': _ticketLocal['pago'],
                            'cambio': _ticketLocal['cambio'],
                            'total': totalValue,
                            'articulos':
                                _ticketLocal['articulos'] ?? items.length,
                            'items':
                                items
                                    .map(
                                      (i) => {
                                        'nombre': i['nombre'],
                                        'precio':
                                            (i['precio'] as num).toDouble(),
                                        'kg': (i['kg'] as num).toDouble(),
                                        'articuloId': i['articuloId'],
                                        'codigoBarras':
                                            (i['codigoBarras'] ?? '')
                                                .toString(),
                                        'categoria': ProductCategory.normalize(
                                          i['categoria'],
                                          barcode: i['codigoBarras'],
                                        ),
                                      },
                                    )
                                    .toList(),
                          };

                          final resultadoEditado =
                              await Navigator.push<Map<String, dynamic>>(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (context) => EditarReciboPage(
                                        ticket: ticketParaEditar,
                                        catalogoProductos:
                                            widget.catalogoGlobal,
                                      ),
                                ),
                              );

                          if (resultadoEditado != null) {
                            setState(() {
                              _ticketLocal['total'] =
                                  (resultadoEditado['total'] as num)
                                      .toDouble()
                                      .roundToDouble();

                              _ticketLocal['subtotal'] =
                                  (resultadoEditado['total'] as num).toDouble();

                              _ticketLocal['articulos'] =
                                  resultadoEditado['articulos'];

                              _ticketLocal['items'] = resultadoEditado['items'];

                              if (resultadoEditado['cambio'] != null) {
                                _ticketLocal['cambio'] =
                                    resultadoEditado['cambio'];
                              }
                            });
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade600,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: const Text(
                          'EDITAR',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  Container(
                    padding: const EdgeInsets.all(20.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          spreadRadius: 2,
                          blurRadius: 5,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _nombreNegocio.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            letterSpacing: 1.1,
                          ),
                        ),

                        const SizedBox(height: 4),

                        Text(
                          _direccion,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                          ),
                        ),

                        const SizedBox(height: 12),

                        Text(
                          'FOLIO: ${_ticketLocal['id']}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),

                        Text(
                          'FECHA: ${_ticketLocal['fecha']}   HORA: ${_ticketLocal['hora']}',
                          style: const TextStyle(fontSize: 12),
                        ),

                        Text(
                          'CLIENTE: ${_ticketLocal['cliente']}',
                          style: const TextStyle(fontSize: 12),
                        ),

                        const SizedBox(height: 12),
                        _buildDottedDivider(),
                        const SizedBox(height: 8),

                        const Row(
                          children: [
                            SizedBox(
                              width: 55,
                              child: Text(
                                'CANT',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 60,
                              child: Text(
                                'PRECIO',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'DESCRIPCIÓN',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 70,
                              child: Text(
                                'IMPORTE',
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 4),
                        _buildDottedDivider(),
                        const SizedBox(height: 8),

                        if (items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 55,
                                  child: Text(
                                    _formatCantidad(
                                      (_ticketLocal['articulos'] ?? 1)
                                          .toDouble(),
                                      categoria:
                                          ProductCategory.groceries,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 60,
                                  child: Text(
                                    '\$${_formatDinero(subtotalValue / (_ticketLocal['articulos'] ?? 1))}',
                                  ),
                                ),
                                const Expanded(
                                  child: Text('Mercancía General'),
                                ),
                                SizedBox(
                                  width: 70,
                                  child: Text(
                                    '\$${_formatDinero(subtotalValue)}',
                                    textAlign: TextAlign.end,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          ...items.map((item) {
                            double precio = (item['precio'] as num).toDouble();
                            double kg = (item['kg'] as num).toDouble();
                            final categoria = ProductCategory.normalize(
                              item['categoria'],
                              barcode: item['codigoBarras'],
                            );
                            double importe = precio * kg;

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4.0,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 55,
                                    child: Text(
                                      _formatCantidad(
                                        kg,
                                        categoria: categoria,
                                        codigoBarras: item['codigoBarras'],
                                      ),
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 60,
                                    child: Text(
                                      '\$${_formatDinero(precio)}',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      item['nombre'] ?? 'Producto',
                                      style: const TextStyle(fontSize: 13),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 70,
                                    child: Text(
                                      '\$${_formatDinero(importe)}',
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),

                        const SizedBox(height: 16),
                        _buildDottedDivider(),
                        const SizedBox(height: 12),

                        Text(
                          'No. de productos: $numeroArticulos',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 6),
                        _buildDottedDivider(),
                        const SizedBox(height: 8),

                        _buildResumenRow('SUBTOTAL', subtotalValue),

                        const SizedBox(height: 6),

                        _buildResumenRow('Pago con', pagoConValue),

                        const SizedBox(height: 6),

                        _buildResumenRow('Cambio', cambioValue),

                        const SizedBox(height: 6),
                        _buildDottedDivider(),
                        const SizedBox(height: 8),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'TOTAL',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              '\$${_formatDinero(totalValue)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        const Text(
                          '*** GRACIAS POR SU COMPRA ***',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            fontStyle: FontStyle.italic,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResumenRow(String label, double monto) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w400,
          ),
        ),
        Text(
          '\$${_formatDinero(monto)}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
        ),
      ],
    );
  }

  Widget _buildDottedDivider() {
    return Row(
      children: List.generate(
        35,
        (index) => Expanded(
          child: Container(
            color: index % 2 == 0 ? Colors.transparent : Colors.grey.shade400,
            height: 1,
          ),
        ),
      ),
    );
  }
}
