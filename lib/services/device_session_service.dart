// lib/services/device_session_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class DeviceSessionIdentity {
  const DeviceSessionIdentity({
    required this.uid,
    required this.installationId,
    required this.sessionId,
  });

  final String uid;
  final String installationId;
  final String sessionId;
}

class SessionReplacedException implements Exception {
  const SessionReplacedException();

  @override
  String toString() =>
      'La cuenta fue iniciada en otro dispositivo.';
}

class DeviceSessionService {
  DeviceSessionService({
    FirebaseFirestore? firestore,
    FlutterSecureStorage? storage,
    Uuid? uuid,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? const FlutterSecureStorage(),
       _uuid = uuid ?? Uuid();

  static const String _installationIdKey = 'device_installation_id';
  static const String _sessionUidKey = 'device_session_uid';
  static const String _sessionIdKey = 'device_session_id';
  static const String _freshLoginKey = 'device_fresh_login';

  final FirebaseFirestore _firestore;
  final FlutterSecureStorage _storage;
  final Uuid _uuid;

  Future<DeviceSessionIdentity>? _pendingEnsure;

  DocumentReference<Map<String, dynamic>> sessionDocument(String uid) {
    return _firestore.collection('sesiones').doc(uid);
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchSession(String uid) {
    return sessionDocument(uid).snapshots(includeMetadataChanges: true);
  }

  Future<void> beginInteractiveLogin() {
    return _storage.write(key: _freshLoginKey, value: 'true');
  }

  Future<void> cancelInteractiveLogin() {
    return _storage.delete(key: _freshLoginKey);
  }

  Future<bool> _hasFreshLoginRequest() async {
    return await _storage.read(key: _freshLoginKey) == 'true';
  }

  Future<String> getOrCreateInstallationId() async {
    final String? saved = await _storage.read(key: _installationIdKey);
    if (saved != null && saved.isNotEmpty) {
      return saved;
    }

    final String created = _uuid.v4();
    await _storage.write(key: _installationIdKey, value: created);
    return created;
  }

  Future<DeviceSessionIdentity?> readLocalSession(String uid) async {
    final String? savedUid = await _storage.read(key: _sessionUidKey);
    final String? sessionId = await _storage.read(key: _sessionIdKey);

    if (savedUid != uid || sessionId == null || sessionId.isEmpty) {
      return null;
    }

    final String installationId = await getOrCreateInstallationId();

    return DeviceSessionIdentity(
      uid: uid,
      installationId: installationId,
      sessionId: sessionId,
    );
  }

  Future<DeviceSessionIdentity> ensureActiveSession(String uid) {
    final Future<DeviceSessionIdentity>? activeOperation = _pendingEnsure;
    if (activeOperation != null) {
      return activeOperation;
    }

    final Future<DeviceSessionIdentity> operation = _ensureActiveSession(uid);
    _pendingEnsure = operation;

    return operation.whenComplete(() {
      if (identical(_pendingEnsure, operation)) {
        _pendingEnsure = null;
      }
    });
  }

  Future<DeviceSessionIdentity> _ensureActiveSession(String uid) async {
    final bool freshLogin = await _hasFreshLoginRequest();
    final DeviceSessionIdentity? local = await readLocalSession(uid);

    if (freshLogin || local == null) {
      return claimSession(uid);
    }

    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await sessionDocument(uid).get(const GetOptions(source: Source.server));

    if (!snapshot.exists) {
      return claimSession(uid);
    }

    if (!matchesSnapshot(snapshot, local)) {
      throw const SessionReplacedException();
    }

    return local;
  }

  Future<DeviceSessionIdentity> claimSession(String uid) async {
    final String installationId = await getOrCreateInstallationId();
    final String sessionId = _uuid.v4();
    final String platform = kIsWeb ? 'web' : defaultTargetPlatform.name;

    final DocumentReference<Map<String, dynamic>> userReference =
        _firestore.collection('usuarios').doc(uid);
    final DocumentReference<Map<String, dynamic>> sessionReference =
        sessionDocument(uid);

    await _firestore.runTransaction((Transaction transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> userSnapshot =
          await transaction.get(userReference);
      final Map<String, dynamic>? userData = userSnapshot.data();

      if (!userSnapshot.exists || userData?['estadoAcceso'] != 'activo') {
        throw FirebaseException(
          plugin: 'device_session',
          code: 'access-not-active',
          message: 'La cuenta no está activa para registrar un dispositivo.',
        );
      }

      final DocumentSnapshot<Map<String, dynamic>> currentSession =
          await transaction.get(sessionReference);

      final Map<String, dynamic> data = <String, dynamic>{
        'uid': uid,
        'installationId': installationId,
        'sessionId': sessionId,
        'plataforma': platform,
        'actualizadoEn': FieldValue.serverTimestamp(),
      };

      if (!currentSession.exists) {
        data['creadoEn'] = FieldValue.serverTimestamp();
      } else {
        data['creadoEn'] = currentSession.data()?['creadoEn'];
      }

      transaction.set(sessionReference, data);
    });

    await _storage.write(key: _sessionUidKey, value: uid);
    await _storage.write(key: _sessionIdKey, value: sessionId);
    await _storage.delete(key: _freshLoginKey);

    return DeviceSessionIdentity(
      uid: uid,
      installationId: installationId,
      sessionId: sessionId,
    );
  }

  bool matchesSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    DeviceSessionIdentity local,
  ) {
    final Map<String, dynamic>? data = snapshot.data();
    if (!snapshot.exists || data == null) {
      return false;
    }

    return data['uid'] == local.uid &&
        data['installationId'] == local.installationId &&
        data['sessionId'] == local.sessionId;
  }

  Future<void> clearLocalSession() async {
    await _storage.delete(key: _sessionUidKey);
    await _storage.delete(key: _sessionIdKey);
    await _storage.delete(key: _freshLoginKey);
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
