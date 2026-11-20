// lib/screens/subscription_required_page.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SubscriptionRequiredPage extends StatelessWidget {
  const SubscriptionRequiredPage({
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
                    Icons.workspace_premium_rounded,
                    size: 76,
                    color: Colors.amber,
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Suscripción no activa',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Tu acceso administrativo está activo, pero la suscripción necesita renovarse.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Verificar nuevamente'),
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
