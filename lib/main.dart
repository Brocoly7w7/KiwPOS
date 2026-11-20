// lib/main.dart
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/login_page.dart';
import 'services/catalog_intent_service.dart';
import 'services/device_session_service.dart';
import 'widgets/access_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await CatalogIntentService.initialize();

  // Configuración de Firebase inyectada localmente con --dart-define-from-file.
  // Evitamos publicar datos del proyecto de producción en este repositorio.
  const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  const firebaseSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  if (firebaseApiKey.isEmpty || firebaseProjectId.isEmpty ||
      firebaseSenderId.isEmpty || firebaseAppId.isEmpty) {
    throw StateError('Falta configuración local de Firebase. Consulta README.md.');
  }

  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: firebaseApiKey,
      projectId: firebaseProjectId,
      messagingSenderId: firebaseSenderId,
      appId: firebaseAppId,
    ),
  );

  runApp(const AppVenta());
}

class AppVenta extends StatelessWidget {
  const AppVenta({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KiwPOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  final DeviceSessionService _sessionService = DeviceSessionService();
  StreamSubscription<User?>? _authSubscription;
  String? _loginMessage;

  @override
  void initState() {
    super.initState();

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((
      User? user,
    ) {
      if (user == null) {
        unawaited(_sessionService.clearLocalSession());
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _handleForcedSignOut(String message) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _loginMessage = message;
    });

    await _sessionService.clearLocalSession();
    await FirebaseAuth.instance.signOut();
  }

  void _clearLoginMessage() {
    if (!mounted || _loginMessage == null) {
      return;
    }

    setState(() {
      _loginMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final User? user = snapshot.data;
        if (user == null) {
          return LoginPage(
            initialMessage: _loginMessage,
            onLoginSuccess: _clearLoginMessage,
          );
        }

        return AccessGate(user: user, onBlocked: _handleForcedSignOut);
      },
    );
  }
}
