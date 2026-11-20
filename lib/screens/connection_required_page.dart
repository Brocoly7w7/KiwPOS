// lib/screens/connection_required_page.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ConnectionRequiredPage extends StatelessWidget {
  const ConnectionRequiredPage({
    super.key,
    required this.onRetry,
  });

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    size: 76,
                    color: Colors.blueGrey,
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Se necesita conexión',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Pasaron más de 24 horas desde la última verificación. Conéctate a internet para validar nuevamente el acceso.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    child: const Text('Cerrar sesión'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
