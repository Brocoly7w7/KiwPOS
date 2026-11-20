// lib/services/user_access_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum AccessDecisionType {
  allowed,
  pending,
  blocked,
  subscriptionExpired,
  invalidProfile,
}

class AccessDecision {
  const AccessDecision(
    this.type, {
    this.subscriptionEnd,
    this.planName = '',
    this.subscriptionStatus = '',
    this.subscriptionRequired = false,
  });

  final AccessDecisionType type;
  final DateTime? subscriptionEnd;
  final String planName;
  final String subscriptionStatus;
  final bool subscriptionRequired;

  bool get isAllowed => type == AccessDecisionType.allowed;
}

class UserAccessService {
  UserAccessService({
    FirebaseFirestore? firestore,
    FlutterSecureStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? const FlutterSecureStorage();

  static const Duration offlineGracePeriod = Duration(hours: 24);

  static const String _cachedUidKey = 'access_cached_uid';
  static const String _offlineValidUntilKey = 'access_offline_valid_until';
  static const String _cachedSessionIdKey = 'access_cached_session_id';

  final FirebaseFirestore _firestore;
  final FlutterSecureStorage _storage;

  DocumentReference<Map<String, dynamic>> userDocument(String uid) {
    return _firestore.collection('usuarios').doc(uid);
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchUser(String uid) {
    return userDocument(uid).snapshots(includeMetadataChanges: true);
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> getFromServer(String uid) {
    return userDocument(uid).get(const GetOptions(source: Source.server));
  }

  /// Crea el perfil inicial del usuario registrado por correo.
  ///
  /// AccessGate no crea perfiles mientras el correo está sin verificar, por lo
  /// que este método conserva el nombre capturado en la pantalla de registro.
  Future<void> createPendingEmailProfile({
    required User user,
    required String name,
  }) async {
    final DocumentReference<Map<String, dynamic>> reference = userDocument(
      user.uid,
    );

    final DocumentSnapshot<Map<String, dynamic>> snapshot = await reference.get(
      const GetOptions(source: Source.server),
    );

    if (snapshot.exists) {
      return;
    }

    await reference.set(<String, dynamic>{
      'uid': user.uid,
      'correo': user.email ?? '',
      'nombre': name.trim(),
      'estadoAcceso': 'pendiente',
      'rol': 'vendedor',
      'suscripcionRequerida': false,
      'estadoSuscripcion': 'no_aplica',
      'fechaFinSuscripcion': null,
      'creadoEn': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    });
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> getOrCreateFromServer(
    User user,
  ) async {
    final DocumentReference<Map<String, dynamic>> reference = userDocument(
      user.uid,
    );

    final DocumentSnapshot<Map<String, dynamic>> snapshot = await reference.get(
      const GetOptions(source: Source.server),
    );

    if (snapshot.exists) {
      return snapshot;
    }

    await reference.set(<String, dynamic>{
      'uid': user.uid,
      'correo': user.email ?? '',
      'nombre': user.displayName ?? '',
      'estadoAcceso': 'pendiente',
      'rol': 'vendedor',
      'suscripcionRequerida': false,
      'estadoSuscripcion': 'no_aplica',
      'fechaFinSuscripcion': null,
      'creadoEn': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    });

    return reference.get(const GetOptions(source: Source.server));
  }

  AccessDecision evaluate(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    if (!snapshot.exists) {
      return const AccessDecision(AccessDecisionType.pending);
    }

    final Map<String, dynamic>? data = snapshot.data();
    if (data == null) {
      return const AccessDecision(AccessDecisionType.invalidProfile);
    }

    final String accessStatus =
        (data['estadoAcceso'] ?? 'pendiente').toString().toLowerCase();

    switch (accessStatus) {
      case 'bloqueado':
        return const AccessDecision(AccessDecisionType.blocked);
      case 'pendiente':
        return const AccessDecision(AccessDecisionType.pending);
      case 'activo':
        break;
      default:
        return const AccessDecision(AccessDecisionType.invalidProfile);
    }

    final bool subscriptionRequired =
        data['suscripcionRequerida'] as bool? ?? false;

    final String subscriptionStatus =
        (data['estadoSuscripcion'] ?? 'no_aplica').toString().toLowerCase();

    final String configuredPlan =
        (data['nombrePlan'] ?? data['plan'] ?? '').toString().trim();

    final String planName =
        configuredPlan.isNotEmpty
            ? configuredPlan
            : _defaultPlanName(
              subscriptionRequired: subscriptionRequired,
              subscriptionStatus: subscriptionStatus,
            );

    if (!subscriptionRequired) {
      return AccessDecision(
        AccessDecisionType.allowed,
        planName: planName,
        subscriptionStatus: subscriptionStatus,
        subscriptionRequired: false,
      );
    }

    final dynamic rawEnd = data['fechaFinSuscripcion'];
    DateTime? subscriptionEnd;

    if (rawEnd is Timestamp) {
      subscriptionEnd = rawEnd.toDate().toUtc();
    } else if (rawEnd is DateTime) {
      subscriptionEnd = rawEnd.toUtc();
    } else if (rawEnd is String) {
      subscriptionEnd = DateTime.tryParse(rawEnd)?.toUtc();
    }

    final bool validStatus =
        subscriptionStatus == 'activa' || subscriptionStatus == 'prueba';
    final bool validDate =
        subscriptionEnd != null &&
        subscriptionEnd.isAfter(DateTime.now().toUtc());

    if (!validStatus || !validDate) {
      return AccessDecision(
        AccessDecisionType.subscriptionExpired,
        subscriptionEnd: subscriptionEnd,
        planName: planName,
        subscriptionStatus: subscriptionStatus,
        subscriptionRequired: true,
      );
    }

    return AccessDecision(
      AccessDecisionType.allowed,
      subscriptionEnd: subscriptionEnd,
      planName: planName,
      subscriptionStatus: subscriptionStatus,
      subscriptionRequired: true,
    );
  }

  String _defaultPlanName({
    required bool subscriptionRequired,
    required String subscriptionStatus,
  }) {
    if (!subscriptionRequired) {
      return 'Acceso permanente';
    }

    switch (subscriptionStatus) {
      case 'prueba':
        return 'Prueba gratuita';
      case 'activa':
        return 'Plan activo';
      case 'inactiva':
        return 'Suscripción inactiva';
      default:
        return 'Plan pendiente';
    }
  }

  Future<void> saveSuccessfulServerVerification(
    String uid, {
    required String sessionId,
    DateTime? subscriptionEnd,
  }) async {
    final DateTime now = DateTime.now().toUtc();
    DateTime validUntil = now.add(offlineGracePeriod);

    if (subscriptionEnd != null && subscriptionEnd.isBefore(validUntil)) {
      validUntil = subscriptionEnd;
    }

    await _storage.write(key: _cachedUidKey, value: uid);
    await _storage.write(key: _cachedSessionIdKey, value: sessionId);
    await _storage.write(
      key: _offlineValidUntilKey,
      value: validUntil.toIso8601String(),
    );
  }

  Future<bool> hasValidOfflineAccess(
    String uid, {
    required String? sessionId,
  }) async {
    final String? cachedUid = await _storage.read(key: _cachedUidKey);
    final String? cachedSessionId = await _storage.read(
      key: _cachedSessionIdKey,
    );
    final String? validUntilText = await _storage.read(
      key: _offlineValidUntilKey,
    );

    if (cachedUid != uid ||
        sessionId == null ||
        cachedSessionId != sessionId ||
        validUntilText == null) {
      return false;
    }

    final DateTime? validUntil = DateTime.tryParse(validUntilText)?.toUtc();
    if (validUntil == null) {
      return false;
    }

    return DateTime.now().toUtc().isBefore(validUntil);
  }

  Future<void> clearOfflineAccess() async {
    await _storage.delete(key: _cachedUidKey);
    await _storage.delete(key: _offlineValidUntilKey);
    await _storage.delete(key: _cachedSessionIdKey);
  }

  bool isConnectionError(Object error) {
    if (error is! FirebaseException) {
      return false;
    }

    return error.code == 'unavailable' ||
        error.code == 'deadline-exceeded' ||
        error.code == 'network-request-failed';
  }
}
