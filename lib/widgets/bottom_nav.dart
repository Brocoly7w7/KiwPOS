// lib/widgets/bottom_nav.dart
import 'package:flutter/material.dart';

class BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const BottomNav({super.key, required this.currentIndex, required this.onTap});

  int get _visibleIndex {
    // Los índices internos de ArticlesPage siguen siendo:
    // 1 = Historial, 2 = Caja, 3 = Artículos.
    // El footer visible usa:
    // 0 = Historial, 1 = Caja, 2 = Artículos.
    switch (currentIndex) {
      case 1:
        return 0;
      case 2:
        return 1;
      case 3:
        return 2;
      default:
        return 1;
    }
  }

  void _handleTap(int visibleIndex) {
    // Convierte el índice del footer al índice interno existente.
    onTap(visibleIndex + 1);
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: _visibleIndex,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: Colors.blue,
      unselectedItemColor: Colors.grey,
      showUnselectedLabels: true,
      onTap: _handleTap,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.calendar_today),
          label: 'Historial',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.point_of_sale), label: 'Caja'),
        BottomNavigationBarItem(
          icon: Icon(Icons.grid_view),
          label: 'Artículos',
        ),
      ],
    );
  }
}
