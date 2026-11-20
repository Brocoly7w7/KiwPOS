// lib/screens/config_factura_page.dart
import 'package:flutter/material.dart';
import '../db/database_helper.dart';

class ConfigFacturaPage extends StatefulWidget {
  final String nombreActual;
  final String direccionActual;

  const ConfigFacturaPage({
    super.key,
    required this.nombreActual,
    required this.direccionActual,
  });

  @override
  State<ConfigFacturaPage> createState() => _ConfigFacturaPageState();
}

class _ConfigFacturaPageState extends State<ConfigFacturaPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nombreController;
  late TextEditingController _direccionController;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(text: widget.nombreActual);
    _direccionController = TextEditingController(text: widget.direccionActual);
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _direccionController.dispose();
    super.dispose();
  }

  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final nombre = _nombreController.text.trim();
    final direccion = _direccionController.text.trim();

    await DatabaseHelper().guardarFacturaConfig(nombre, direccion);

    if (!mounted) return;

    Navigator.pop(context, {'nombre': nombre, 'direccion': direccion});
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: Colors.blue),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade500),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.blue, width: 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: const Text(
          'Configuración de Factura',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Datos del Encabezado',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Esta información aparecerá impresa en la parte superior de cada boucher generado.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _nombreController,
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration(
                    label: 'Nombre del Negocio',
                    hint: 'Ej. Mi Tiendita S.A de C.V',
                    icon: Icons.storefront,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Por favor ingresa un nombre comercial';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: _direccionController,
                  maxLines: 1,
                  textInputAction: TextInputAction.done,
                  decoration: _inputDecoration(
                    label: 'Dirección Comercial',
                    hint: 'Ej. Av. Revolución #456, Col. Centro',
                    icon: Icons.location_on_outlined,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Por favor ingresa la dirección de la sucursal';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _guardarCambios(),
                ),

                const SizedBox(height: 22),

                ElevatedButton(
                  onPressed: _guardarCambios,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'GUARDAR CAMBIOS',
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
      ),
    );
  }
}
