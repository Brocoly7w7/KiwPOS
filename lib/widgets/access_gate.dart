// lib/widgets/access_gate.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/articles_page.dart';
import '../screens/connection_required_page.dart';
import '../screens/pending_approval_page.dart';
import '../screens/subscription_required_page.dart';
import '../screens/verify_email_page.dart';
import '../services/device_session_service.dart';
import '../services/user_access_service.dart';

enum _GateState {
  checking,
  emailUnverified,
  allowedOnline,
  allowedOffline,
  pending,
  offlineExpired,
  subscriptionExpired,
  error,
}

class AccessGate extends StatefulWidget {
  const AccessGate({super.key, required this.user, required this.onBlocked});

  final User user;
  final Future<void> Function(String message) onBlocked;

  @override
  State<AccessGate> createState() => _AccessGateState();
}

class _AccessGateState extends State<AccessGate> with WidgetsBindingObserver {
  final UserAccessService _accessService = UserAccessService();
  final DeviceSessionService _sessionService = DeviceSessionService();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _accessSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _sessionSubscription;

  _GateState _state = _GateState.checking;
  String _errorMessage = '';
  bool _signingOut = false;
  Timer? _expirationTimer;
  AccessDecision? _lastDecision;

  User get _currentUser => FirebaseAuth.instance.currentUser ?? widget.user;

  bool _requiresEmailVerification(User user) {
    final bool usesPassword = user.providerData.any(
      (UserInfo provider) => provider.providerId == 'password',
    );

    return usesPassword && !user.emailVerified;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenForAccessChanges();
    unawaited(_verifyAccess(showLoading: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expirationTimer?.cancel();
    _accessSubscription?.cancel();
    _sessionSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_verifyAccess(showLoading: false, reloadUser: true));
    }
  }

  void _listenForAccessChanges() {
    _accessSubscription = _accessService
        .watchUser(widget.user.uid)
        .listen(
          (DocumentSnapshot<Map<String, dynamic>> snapshot) async {
            if (snapshot.metadata.isFromCache) {
              return;
            }

            try {
              await _applyServerSnapshot(snapshot);
            } on SessionReplacedException {
              await _handleSessionReplaced();
            } catch (error) {
              if (!_accessService.isConnectionError(error) && mounted) {
                setState(() {
                  _state = _GateState.error;
                  _errorMessage = error.toString();
                });
              }
            }
          },
          onError: (_) {
            // La verificación activa y el periodo offline controlan este caso.
          },
        );
  }

  void _listenForSessionChanges(DeviceSessionIdentity session) {
    unawaited(_sessionSubscription?.cancel());

    _sessionSubscription = _sessionService
        .watchSession(session.uid)
        .listen(
          (DocumentSnapshot<Map<String, dynamic>> snapshot) async {
            if (snapshot.metadata.isFromCache || _signingOut) {
              return;
            }

            if (!_sessionService.matchesSnapshot(snapshot, session)) {
              await _handleSessionReplaced();
            }
          },
          onError: (_) {
            // Si se pierde internet, el permiso híbrido controla el acceso.
          },
        );
  }

  Future<void> _verifyAccess({
    required bool showLoading,
    bool reloadUser = false,
  }) async {
    if (showLoading && mounted) {
      setState(() {
        _state = _GateState.checking;
        _errorMessage = '';
      });
    }

    try {
      User user = _currentUser;

      if (reloadUser) {
        await user.reload();
        user = FirebaseAuth.instance.currentUser ?? user;
      }

      if (_requiresEmailVerification(user)) {
        await _clearAllLocalAccess();

        if (mounted) {
          setState(() {
            _state = _GateState.emailUnverified;
            _errorMessage = '';
          });
        }
        return;
      }

      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await _accessService.getOrCreateFromServer(user);
      await _applyServerSnapshot(snapshot);
    } on SessionReplacedException {
      await _handleSessionReplaced();
    } catch (error) {
      if (_accessService.isConnectionError(error) ||
          _sessionService.isConnectionError(error)) {
        final DeviceSessionIdentity? localSession = await _sessionService
            .readLocalSession(widget.user.uid);
        final bool canWorkOffline = await _accessService.hasValidOfflineAccess(
          widget.user.uid,
          sessionId: localSession?.sessionId,
        );

        if (!mounted) {
          return;
        }

        setState(() {
          _state =
              canWorkOffline
                  ? _GateState.allowedOffline
                  : _GateState.offlineExpired;
        });
        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _state = _GateState.error;
        _errorMessage = error.toString();
      });
    }
  }

  void _scheduleExpirationCheck(AccessDecision decision) {
    _expirationTimer?.cancel();

    if (!decision.subscriptionRequired || decision.subscriptionEnd == null) {
      return;
    }

    final Duration remaining = decision.subscriptionEnd!.difference(
      DateTime.now().toUtc(),
    );

    if (remaining <= Duration.zero) {
      unawaited(_handleSubscriptionExpired(decision));
      return;
    }

    _expirationTimer = Timer(
      remaining,
      () => unawaited(_handleSubscriptionExpired(decision)),
    );
  }

  Future<void> _handleSubscriptionExpired(AccessDecision decision) async {
    if (_signingOut) {
      return;
    }

    _expirationTimer?.cancel();
    await _clearAllLocalAccess();

    final String plan =
        decision.planName.trim().isEmpty ? 'Tu plan' : decision.planName;

    await _forceSignOut(
      '$plan ha vencido. Tu cuenta quedó pendiente de renovación. '
      'Contacta al administrador para recuperar el acceso.',
    );
  }

  Future<void> _applyServerSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) async {
    final AccessDecision decision = _accessService.evaluate(snapshot);
    _lastDecision = decision;

    if (decision.type == AccessDecisionType.blocked) {
      await _clearAllLocalAccess();
      await _forceSignOut(
        'Su cuenta ha sido inhabilitada. Por favor, contacte al administrador.',
      );
      return;
    }

    if (_requiresEmailVerification(_currentUser)) {
      await _clearAllLocalAccess();
      if (mounted) {
        setState(() {
          _state = _GateState.emailUnverified;
          _errorMessage = '';
        });
      }
      return;
    }

    switch (decision.type) {
      case AccessDecisionType.allowed:
        final DeviceSessionIdentity session = await _sessionService
            .ensureActiveSession(widget.user.uid);

        _listenForSessionChanges(session);

        await _accessService.saveSuccessfulServerVerification(
          widget.user.uid,
          sessionId: session.sessionId,
          subscriptionEnd: decision.subscriptionEnd,
        );

        _scheduleExpirationCheck(decision);

        if (mounted) {
          setState(() {
            _state = _GateState.allowedOnline;
            _errorMessage = '';
          });
        }
        break;

      case AccessDecisionType.pending:
        _expirationTimer?.cancel();
        await _clearAllLocalAccess();
        if (mounted) {
          setState(() => _state = _GateState.pending);
        }
        break;

      case AccessDecisionType.blocked:
        break;

      case AccessDecisionType.subscriptionExpired:
        await _handleSubscriptionExpired(decision);
        break;

      case AccessDecisionType.invalidProfile:
        await _clearAllLocalAccess();
        if (mounted) {
          setState(() {
            _state = _GateState.error;
            _errorMessage = 'El perfil de acceso no tiene un estado válido.';
          });
        }
        break;
    }
  }

  Future<void> _handleSessionReplaced() async {
    await _clearAllLocalAccess();
    await _forceSignOut(
      'Esta cuenta inició sesión en otro dispositivo. Por seguridad, se cerró la sesión en este teléfono.',
    );
  }

  Future<void> _clearAllLocalAccess() async {
    await _sessionSubscription?.cancel();
    _sessionSubscription = null;
    await _accessService.clearOfflineAccess();
    await _sessionService.clearLocalSession();
  }

  Future<bool> _checkEmailVerification() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return false;
    }

    await user.reload();
    final User? refreshedUser = FirebaseAuth.instance.currentUser;

    if (refreshedUser == null || !refreshedUser.emailVerified) {
      return false;
    }

    await _verifyAccess(showLoading: true);
    return true;
  }

  Future<void> _resendVerificationEmail() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('No existe una sesión activa.');
    }

    await FirebaseAuth.instance.setLanguageCode('es');
    await user.sendEmailVerification();
  }

  Future<void> _signOutFromVerification() async {
    await _clearAllLocalAccess();
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _forceSignOut(String message) async {
    if (_signingOut) {
      return;
    }

    _signingOut = true;
    await _accessSubscription?.cancel();
    await _sessionSubscription?.cancel();
    await widget.onBlocked(message);
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _GateState.allowedOnline:
      case _GateState.allowedOffline:
        return ArticlesPage(
          planName:
              _lastDecision?.planName ??
              (_state == _GateState.allowedOffline
                  ? 'Acceso sin conexión'
                  : 'Plan activo'),
          subscriptionEnd: _lastDecision?.subscriptionEnd,
          isOfflineAccess: _state == _GateState.allowedOffline,
        );

      case _GateState.emailUnverified:
        return VerifyEmailPage(
          email: _currentUser.email ?? '',
          onCheckVerification: _checkEmailVerification,
          onResend: _resendVerificationEmail,
          onSignOut: _signOutFromVerification,
        );

      case _GateState.pending:
        return PendingApprovalPage(email: widget.user.email ?? '');

      case _GateState.offlineExpired:
        return ConnectionRequiredPage(
          onRetry: () => _verifyAccess(showLoading: true, reloadUser: true),
        );

      case _GateState.subscriptionExpired:
        return SubscriptionRequiredPage(
          onRetry: () => _verifyAccess(showLoading: true, reloadUser: true),
        );

      case _GateState.error:
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'No fue posible comprobar el acceso.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed:
                        () =>
                            _verifyAccess(showLoading: true, reloadUser: true),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        );

      case _GateState.checking:
        return const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Verificando acceso...'),
              ],
            ),
          ),
        );
    }
  }
}
