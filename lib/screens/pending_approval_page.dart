// lib/screens/pending_approval_page.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PendingApprovalPage extends StatelessWidget {
  const PendingApprovalPage({super.key, required this.email});

  final String email;

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
                    Icons.hourglass_top_rounded,
                    size: 76,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Cuenta pendiente de autorización',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tu cuenta $email ya fue registrada. En cuanto el administrador la active, la aplicación entrará automáticamente.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  OutlinedButton.icon(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    icon: const Icon(Icons.logout),
                    label: const Text('Volver al inicio de sesión'),
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
