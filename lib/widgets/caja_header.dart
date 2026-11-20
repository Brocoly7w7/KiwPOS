// lib/widgets/caja_header.dart
import 'package:flutter/material.dart';

class CajaHeader extends StatelessWidget implements PreferredSizeWidget {
  const CajaHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white, // Fondo blanco igual al catálogo
      elevation: 1, // Una ligera sombra divisoria
      automaticallyImplyLeading: false, // Evita flechas de regreso automáticas
      // Icono de menú hamburguesa izquierdo exacto
      leading: IconButton(
        icon: const Icon(Icons.menu, color: Colors.black87),
        onPressed: () {},
      ),

      // Título plano alineado
      title: const Text(
        'Caja',
        style: TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),

      // Los tres iconos del lado derecho tal cual los tienes en Artículos
      actions: [
        IconButton(
          icon: const Icon(Icons.view_module, color: Colors.black87),
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(Icons.person_add, color: Colors.black87),
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(Icons.call, color: Colors.black87),
          onPressed: () {},
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
