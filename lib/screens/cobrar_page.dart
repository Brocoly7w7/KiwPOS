// lib/screens/cobrar_page.dart
import 'package:flutter/material.dart';

class CobrarPage extends StatefulWidget {
  final double totalAPagar;
  final int siguienteNumeroCliente;
  final String? clienteInicial;

  const CobrarPage({
    super.key,
    required this.totalAPagar,
    required this.siguienteNumeroCliente,
    this.clienteInicial,
  });

  @override
  State<CobrarPage> createState() => _CobrarPageState();
}

class _CobrarPageState extends State<CobrarPage> {
  final TextEditingController _clienteController = TextEditingController();
  final TextEditingController _efectivoController = TextEditingController();

  double _efectivoRecibido = 0.0;
  double _cambio = 0.0;

  // Lista de billetes actualizada incluyendo el billete de $1000
  final List<int> _billetesRapidos = [20, 50, 100, 200, 500, 1000];

  @override
  void initState() {
    super.initState();
    final cliente = widget.clienteInicial?.trim() ?? '';
    if (cliente.isNotEmpty) {
      _clienteController.text = cliente;
    }
    _efectivoController.addListener(_calcularCambioManual);
  }

  void _calcularCambioManual() {
    final texto = _efectivoController.text;
    setState(() {
      if (texto.isEmpty) {
        _efectivoRecibido = 0.0;
      } else {
        _efectivoRecibido = double.tryParse(texto) ?? 0.0;
      }
      _actualizarCambio();
    });
  }

  // LÓGICA ACUMULATIVA: Ahora suma los montos consecutivamente en vez de reemplazarlos
  void _acumularBilleteRapido(int cantidad) {
    setState(() {
      double montoActual = double.tryParse(_efectivoController.text) ?? 0.0;
      double nuevoMonto = montoActual + cantidad;

      _efectivoRecibido = nuevoMonto;
      // Actualiza el texto en pantalla para que el usuario vea la suma reflejada
      _efectivoController.text = nuevoMonto.toStringAsFixed(0);
      _actualizarCambio();
    });
  }

  void _actualizarCambio() {
    if (_efectivoRecibido >= widget.totalAPagar) {
      _cambio = _efectivoRecibido - widget.totalAPagar;
    } else {
      _cambio = 0.0;
    }
  }

  void _finalizarVenta() {
    String nombreCliente = _clienteController.text.trim();
    if (nombreCliente.isEmpty) {
      nombreCliente = 'Cliente #${widget.siguienteNumeroCliente}';
    }

    Navigator.pop(context, {
      'cliente': nombreCliente,
      'exito': true,
      'pago': _efectivoRecibido, // cantidad que pagó el cliente
      'cambio': _cambio, // cambio que debe recibir
    });
  }

  @override
  void dispose() {
    _clienteController.dispose();
    _efectivoController.dispose();
    super.dispose();
  }

  // Colores temáticos estéticos para identificar rápido cada billete en México
  Color skinnerColor(int b) {
    if (b == 50) return Colors.pink.shade400;
    if (b == 100) return Colors.red.shade400;
    if (b == 200) return Colors.green.shade600;
    if (b == 500) return Colors.blue.shade800;
    if (b == 1000) return Colors.purple.shade700;
    return Colors.black87;
  }

  @override
  Widget build(BuildContext context) {
    bool puedeCobrar = _efectivoRecibido >= widget.totalAPagar;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Pagar Orden',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Campo Superior: Nombre del Cliente (Opcional)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 4.0,
                ),
                child: TextField(
                  controller: _clienteController,
                  decoration: InputDecoration(
                    labelText: 'Nombre del cliente (Opcional)',
                    hintText: 'Ej. Cliente #${widget.siguienteNumeroCliente}',
                    border: InputBorder.none,
                    icon: const Icon(Icons.person_outline, color: Colors.blue),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Contenedor del Total a Pagar Grande
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text(
                    'TOTAL A COBRAR',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\$${widget.totalAPagar.round()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 36,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Sección de Dinero Recibido e Input Numérico
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Efectivo Recibido',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                // Botón discreto para limpiar el efectivo acumulado rápidamente si se equivocan
                TextButton.icon(
                  onPressed: () {
                    _efectivoController.clear();
                  },
                  icon: const Icon(
                    Icons.backspace_outlined,
                    size: 16,
                    color: Colors.red,
                  ),
                  label: const Text(
                    'Limpiar',
                    style: TextStyle(color: Colors.red, fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _efectivoController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                prefixText: '\$ ',
                hintText: '0.00',
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // CAMBIO CLAVE: Usamos Wrap en vez de ListView para hacer saltos de línea automáticos
            Wrap(
              spacing: 10.0, // Espacio horizontal entre tarjetas de billetes
              runSpacing:
                  10.0, // Espacio vertical cuando salten a la siguiente línea ($500 y $1000)
              alignment: WrapAlignment.start,
              children:
                  _billetesRapidos.map((billete) {
                    return InkWell(
                      onTap: () => _acumularBilleteRapido(billete),
                      child: Container(
                        // MediaQuery dinámico para que se distribuyan de 3 en 3 perfectamente sin importar la pantalla
                        width: (MediaQuery.of(context).size.width - 52) / 3,
                        height: 55,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.grey.shade300,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          '\$$billete',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: skinnerColor(billete),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
            ),
            const SizedBox(height: 24),

            // Pantalla de Cambio devuelto
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:
                    _cambio > 0 ? Colors.green.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color:
                      _cambio > 0
                          ? Colors.green.shade200
                          : Colors.grey.shade300,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Su Cambio:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '\$${_cambio.round()}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color:
                          _cambio > 0 ? Colors.green.shade700 : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Botón verde para concluir venta
            ElevatedButton(
              onPressed: puedeCobrar ? _finalizarVenta : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                disabledBackgroundColor: Colors.grey.shade300,
                minimumSize: const Size.fromHeight(55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                puedeCobrar ? 'CONCLUIR VENTA' : 'EFECTIVO INSUFICIENTE',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
