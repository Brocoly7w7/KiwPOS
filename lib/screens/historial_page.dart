// lib/screens/historial_page.dart
import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import 'detalle_ticket_page.dart';

class HistorialPage extends StatefulWidget {
  final List<Map<String, dynamic>> ventasHistorial;
  final String nombreNegocio;
  final String direccionNegocio;
  final Function(String, String) onConfigUpdate;
  final VoidCallback onTicketDeleted;
  final TextEditingController
  searchController; // RECIBE EL CONTROLADOR DESDE EL PADRE

  const HistorialPage({
    super.key,
    required this.ventasHistorial,
    required this.nombreNegocio,
    required this.direccionNegocio,
    required this.onConfigUpdate,
    required this.onTicketDeleted,
    required this.searchController, // Requerido aquí
  });

  @override
  State<HistorialPage> createState() => _HistorialPageState();
}

class _HistorialPageState extends State<HistorialPage> {
  List<Map<String, dynamic>> _ventasFiltradas = [];

  @override
  void initState() {
    super.initState();
    _ventasFiltradas = List.from(widget.ventasHistorial);
    widget.searchController.addListener(
      _filtrarVentas,
    ); // Escucha al controlador del padre
  }

  void _filtrarVentas() {
    final query = widget.searchController.text.toLowerCase().trim();
    setState(() {
      final listaBase = widget.ventasHistorial;

      if (query.isEmpty) {
        _ventasFiltradas = List.from(listaBase);
      } else {
        _ventasFiltradas =
            listaBase.where((venta) {
              final id = (venta['id'] ?? '').toString().toLowerCase();
              final cliente = (venta['cliente'] ?? '').toString().toLowerCase();
              final fecha = (venta['fecha'] ?? '').toString().toLowerCase();
              final hora = (venta['hora'] ?? '').toString().toLowerCase();
              final total = '\$${(venta['total'] ?? 0.0).toStringAsFixed(2)}';

              return id.contains(query) ||
                  cliente.contains(query) ||
                  fecha.contains(query) ||
                  hora.contains(query) ||
                  total.contains(query);
            }).toList();
      }
    });
  }

  @override
  void didUpdateWidget(covariant HistorialPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ventasHistorial != oldWidget.ventasHistorial) {
      _ventasFiltradas = List.from(widget.ventasHistorial);
    }
    _filtrarVentas();
  }

  @override
  void dispose() {
    // Nota: No eliminamos el controlador aquí con .dispose() ya que pertenece al padre
    widget.searchController.removeListener(_filtrarVentas);
    super.dispose();
  }

  void _abrirDetalleTicket(Map<String, dynamic> ticketSeleccionado) async {
    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => DetalleTicketPage(
              venta: ticketSeleccionado,
              nombreNegocioInicial: widget.nombreNegocio,
              direccionInicial: widget.direccionNegocio,
              onConfigGuardada: (nombre, direccion) {
                widget.onConfigUpdate(nombre, direccion);
              },
              catalogoGlobal: const [],
            ),
      ),
    );

    if (resultado != null) {
      if (resultado['borrar'] == true) {
        await DatabaseHelper().deleteTicket(resultado['id']);
        widget.onTicketDeleted();
      } else {
        await DatabaseHelper().updateTicket(resultado);
        widget.onTicketDeleted();
        final datosFrescosDeBD = await DatabaseHelper().getTickets();
        setState(() {
          _ventasFiltradas = List.from(datosFrescosDeBD);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          // SE ELIMINÓ EL TEXTFIELD DE AQUÍ PARA EVITAR LA DOBLE BARRA DUPLICADA
          Expanded(
            child:
                _ventasFiltradas.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 60,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.searchController.text.isEmpty
                                ? 'No se han registrado ventas hoy'
                                : 'No se encontraron tickets coincidentes',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      itemCount: _ventasFiltradas.length,
                      itemBuilder: (context, index) {
                        final venta = _ventasFiltradas[index];

                        return InkWell(
                          onTap: () => _abrirDetalleTicket(venta),
                          onLongPress: () => _abrirDetalleTicket(venta),
                          child: Card(
                            margin: const EdgeInsets.symmetric(vertical: 6.0),
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14.0),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.receipt,
                                      color: Colors.blue,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          venta['cliente'] ??
                                              'Cliente sin nombre',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Folio: ${venta['id']}',
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${venta['fecha']} a las ${venta['hora']} • ${venta['articulos'] ?? 0} art.',
                                          style: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        '\$${(venta['total'] ?? 0.0).toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.chevron_right,
                                        color: Colors.grey,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
