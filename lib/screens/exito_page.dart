// lib/screens/exito_page.dart
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/material.dart';

import '../services/bluetooth_print_service.dart';
import 'detalle_ticket_page.dart';

class ExitoPage extends StatefulWidget {
  final String ticketId;
  final String cliente;
  final double total;
  final int totalArticulos;
  final String fechaHora;
  final Map<String, dynamic> venta;

  /// Ejecuta exactamente la misma limpieza utilizada para iniciar
  /// una nueva venta, pero sin obligar a salir de esta pantalla.
  final Future<void> Function()? onLimpiarCaja;

  const ExitoPage({
    super.key,
    required this.ticketId,
    required this.cliente,
    required this.total,
    required this.totalArticulos,
    required this.fechaHora,
    required this.venta,
    this.onLimpiarCaja,
  });

  @override
  State<ExitoPage> createState() => _ExitoPageState();
}

class _ExitoPageState extends State<ExitoPage> {
  bool _cajaYaFueLimpiada = false;
  bool _limpiandoCaja = false;

  Future<bool> _limpiarCajaUnaSolaVez() async {
    if (_cajaYaFueLimpiada) {
      return true;
    }

    if (_limpiandoCaja) {
      return false;
    }

    setState(() {
      _limpiandoCaja = true;
    });

    try {
      await widget.onLimpiarCaja?.call();

      if (mounted) {
        setState(() {
          _cajaYaFueLimpiada = true;
        });
      }

      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'La venta fue guardada, pero no se pudo limpiar la caja: $error',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }

      return false;
    } finally {
      if (mounted) {
        setState(() {
          _limpiandoCaja = false;
        });
      }
    }
  }

  void _navegarADetalle(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => DetalleTicketPage(
              venta: widget.venta,
              nombreNegocioInicial: 'Mi negocio',
              direccionInicial: 'Dirección del negocio',
              onConfigGuardada: (nombre, direccion) {},
              catalogoGlobal: const [],
            ),
      ),
    );
  }

  Future<bool> _imprimirConDispositivo(
    BuildContext context,
    BluetoothPrintService servicio,
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

    final impreso = await servicio.imprimirTicketConReconexion(
      dispositivo: dispositivo,
      venta: widget.venta,
      negocio: 'Mi negocio',
      direccion: 'Dirección del negocio',
    );

    if (!context.mounted) return impreso;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          impreso
              ? 'Recibo enviado correctamente.'
              : 'No fue posible reconectar. Acércate a la impresora e inténtalo nuevamente.',
        ),
        backgroundColor: impreso ? Colors.green : Colors.redAccent,
      ),
    );

    return impreso;
  }

  Future<void> _mostrarSelectorEImprimir(
    BuildContext context,
    BluetoothPrintService servicio,
  ) async {
    final dispositivos = await servicio.obtenerDispositivos();

    if (!context.mounted) return;

    if (dispositivos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No hay impresoras Bluetooth vinculadas. Vincúlala desde los ajustes del teléfono.',
          ),
        ),
      );

      _navegarADetalle(context);
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
                    'Selecciona tu impresora',
                    style: TextStyle(
                      fontSize: 17,
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
                            color: Colors.green,
                          ),
                          title: Text(
                            dispositivo.name ?? 'Impresora Bluetooth',
                          ),
                          subtitle: Text(dispositivo.address ?? ''),
                          onTap: () async {
                            Navigator.pop(bottomSheetContext);

                            await _imprimirConDispositivo(
                              context,
                              servicio,
                              dispositivo,
                            );

                            if (context.mounted) {
                              _navegarADetalle(context);
                            }
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
  }

  Future<void> _obtenerRecibo(BuildContext context) async {
    // Limpia la caja antes de abrir el selector, pero conserva esta pantalla
    // y continúa exactamente con el flujo de impresión y detalle del ticket.
    await _limpiarCajaUnaSolaVez();

    if (!context.mounted) return;

    final servicio = BluetoothPrintService();
    final recordada = servicio.ultimoDispositivo;

    if (recordada != null) {
      final impreso = await _imprimirConDispositivo(
        context,
        servicio,
        recordada,
      );

      if (impreso) {
        if (context.mounted) {
          _navegarADetalle(context);
        }
        return;
      }
    }

    if (context.mounted) {
      await _mostrarSelectorEImprimir(context, servicio);
    }
  }

  Future<void> _nuevaVenta() async {
    await _limpiarCajaUnaSolaVez();

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 24.0,
            vertical: 16.0,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),

              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    size: 100,
                    color: Colors.green,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              const Text(
                '¡Venta Exitosa!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),

              Text(
                'El ticket ha sido generado correctamente.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 32),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    _buildInfoRow(
                      'Folio:',
                      widget.ticketId,
                      isHighlighted: true,
                    ),
                    const Divider(height: 20),
                    _buildInfoRow('Cliente:', widget.cliente),
                    const Divider(height: 20),
                    _buildInfoRow(
                      'Artículos:',
                      '${widget.totalArticulos} pz',
                    ),
                    const Divider(height: 20),
                    _buildInfoRow('Fecha y Hora:', widget.fechaHora),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Pagado:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '\$${widget.total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Spacer(),

              OutlinedButton(
                onPressed:
                    _limpiandoCaja ? null : () => _obtenerRecibo(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(
                    color: Colors.green,
                    width: 2,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child:
                    _limpiandoCaja
                        ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.green,
                          ),
                        )
                        : const Text(
                          'OBTENER RECIBO',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
              ),
              const SizedBox(height: 12),

              ElevatedButton(
                onPressed: _limpiandoCaja ? null : _nuevaVenta,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'NUEVA VENTA',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    bool isHighlighted = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isHighlighted ? 16 : 14,
            fontWeight:
                isHighlighted ? FontWeight.bold : FontWeight.normal,
            color:
                isHighlighted ? Colors.black : Colors.grey.shade800,
          ),
        ),
      ],
    );
  }
}
