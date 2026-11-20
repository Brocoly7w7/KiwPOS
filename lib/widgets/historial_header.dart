// lib/widgets/historial_header.dart
import 'package:flutter/material.dart';

class HistorialHeader extends StatelessWidget implements PreferredSizeWidget {
  final TextEditingController searchController;

  const HistorialHeader({super.key, required this.searchController});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.menu, color: Colors.black87),
        onPressed: () {},
      ),
      title: const Text(
        'Historial', // Cambiado a Historial
        style: TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
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
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: AnimatedBuilder(
            animation: searchController,
            builder: (context, child) {
              return TextField(
                controller:
                    searchController, // Vinculamos tu controlador original
                decoration: InputDecoration(
                  hintText: 'Buscar por folio, cliente, fecha o total...',
                  prefixIcon: const Icon(Icons.search, color: Colors.blue),
                  suffixIcon:
                      searchController.text.isNotEmpty
                          ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.grey),
                            onPressed: () => searchController.clear(),
                          )
                          : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(116);
}
