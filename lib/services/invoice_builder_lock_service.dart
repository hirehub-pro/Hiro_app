import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum InvoiceBuilderLockAcquireResult { acquired, occupied, unavailable }

enum InvoiceBuilderLockLossReason { ownershipChanged, unavailable }

/// A short-lived, per-device lease for the Invoice Builder.
///
/// The document path and field names are shared with the Hiro website; keep
/// them in sync with that client.
class InvoiceBuilderLockService {
  InvoiceBuilderLockService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance,
      _sessionId = _generateRandomId();

  static const _deviceIdPreferenceKey = 'invoice_builder_device_id';
  static const _leaseDuration = Duration(seconds: 60);
  static const _renewalInterval = Duration(seconds: 20);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final String _sessionId;

  String? _deviceId;
  String? _userId;
  Object? _lastOperationError;
  DocumentReference<Map<String, dynamic>>? _lockRef;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  Timer? _renewalTimer;
  bool _hasLease = false;
  bool _released = false;
  bool _renewalInProgress = false;
  DateTime? _confirmedExpiresAt;

  /// Called when this device no longer owns the lock.
  void Function(InvoiceBuilderLockLossReason reason)? onLeaseLost;

  Future<InvoiceBuilderLockAcquireResult> acquire() async {
    if (_released) return InvoiceBuilderLockAcquireResult.unavailable;
    final user = _auth.currentUser;
    if (user == null) return InvoiceBuilderLockAcquireResult.unavailable;

    _userId = user.uid;
    _deviceId = await _getDeviceId();
    _lockRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('invoice_builder_lock')
        .doc('active');

    _lastOperationError = null;
    final acquired = await _claimOrRenew();
    if (!acquired) {
      return _lastOperationError == null
          ? InvoiceBuilderLockAcquireResult.occupied
          : InvoiceBuilderLockAcquireResult.unavailable;
    }

    // A transaction result alone is not enough to unlock the UI: make sure
    // the committed document is visible from the Firestore server first.
    // This prevents cached/offline state from granting access on two clients.
    final confirmation = await _confirmOwnershipFromServer();
    if (confirmation != InvoiceBuilderLockAcquireResult.acquired) {
      return confirmation;
    }

    _hasLease = true;
    if (_released) {
      await release();
      return InvoiceBuilderLockAcquireResult.unavailable;
    }
    _listenForOwnershipChanges();
    _renewalTimer = Timer.periodic(_renewalInterval, (_) => _renew());
    return InvoiceBuilderLockAcquireResult.acquired;
  }

  Future<void> _renew() async {
    if (!_hasLease || _renewalInProgress) return;
    _renewalInProgress = true;
    try {
      if (!await _claimOrRenew()) {
        if (_lastOperationError == null) {
          _loseLease(InvoiceBuilderLockLossReason.ownershipChanged);
        } else {
          _handleTemporaryRenewalFailure();
        }
        return;
      }

      final confirmation = await _confirmOwnershipFromServer();
      switch (confirmation) {
        case InvoiceBuilderLockAcquireResult.acquired:
          return;
        case InvoiceBuilderLockAcquireResult.occupied:
          _loseLease(InvoiceBuilderLockLossReason.ownershipChanged);
          return;
        case InvoiceBuilderLockAcquireResult.unavailable:
          _handleTemporaryRenewalFailure();
          return;
      }
    } finally {
      _renewalInProgress = false;
    }
  }

  void _handleTemporaryRenewalFailure() {
    final confirmedExpiresAt = _confirmedExpiresAt;
    if (confirmedExpiresAt == null ||
        !DateTime.now().isBefore(confirmedExpiresAt)) {
      _loseLease(InvoiceBuilderLockLossReason.unavailable);
    }
  }

  Future<bool> _claimOrRenew() async {
    final ref = _lockRef;
    final deviceId = _deviceId;
    final userId = _userId;
    if (ref == null || deviceId == null || userId == null) return false;
    _lastOperationError = null;

    try {
      return await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        final data = snapshot.data();
        final ownerSessionId = data?['sessionId'] as String?;
        final ownerDeviceId = data?['deviceId'] as String?;
        final expiresAt = data?['expiresAt'];
        final expiresAtMs = expiresAt is Timestamp
            ? expiresAt.millisecondsSinceEpoch
            : (data?['expiresAtMs'] as num?)?.toInt() ?? 0;
        final nowMs = DateTime.now().millisecondsSinceEpoch;

        if (snapshot.exists &&
            ownerSessionId != _sessionId &&
            ownerDeviceId != deviceId &&
            expiresAtMs > nowMs) {
          return false;
        }

        final sameSession = ownerSessionId == _sessionId;
        final existingAcquiredAt = data?['acquiredAt'];
        transaction.set(ref, {
          'ownerUid': userId,
          'sessionId': _sessionId,
          'deviceId': deviceId,
          'acquiredAt': sameSession && existingAcquiredAt is Timestamp
              ? existingAcquiredAt
              : FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromMillisecondsSinceEpoch(
            nowMs + _leaseDuration.inMilliseconds,
          ),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
    } catch (error) {
      _lastOperationError = error;
      // An offline transaction cannot safely establish exclusive ownership.
      return false;
    }
  }

  Future<InvoiceBuilderLockAcquireResult> _confirmOwnershipFromServer() async {
    final ref = _lockRef;
    final userId = _userId;
    if (ref == null || userId == null) {
      return InvoiceBuilderLockAcquireResult.unavailable;
    }

    try {
      final snapshot = await ref.get(const GetOptions(source: Source.server));
      final data = snapshot.data();
      final expiresAt = data?['expiresAt'];
      final isOwned =
          data?['ownerUid'] == userId &&
          data?['sessionId'] == _sessionId &&
          expiresAt is Timestamp &&
          expiresAt.millisecondsSinceEpoch >
              DateTime.now().millisecondsSinceEpoch;
      if (!isOwned) return InvoiceBuilderLockAcquireResult.occupied;
      _confirmedExpiresAt = expiresAt.toDate();
      return InvoiceBuilderLockAcquireResult.acquired;
    } catch (error) {
      _lastOperationError = error;
      // Never grant or retain exclusive access from cache-only state.
      return InvoiceBuilderLockAcquireResult.unavailable;
    }
  }

  void _listenForOwnershipChanges() {
    _subscription?.cancel();
    final ref = _lockRef;
    if (ref == null) return;

    _subscription = ref.snapshots(includeMetadataChanges: true).listen((
      snapshot,
    ) {
      // A listener may first emit an older cached owner even after the server
      // has confirmed this session. Only server state may revoke the lease.
      if (snapshot.metadata.isFromCache) return;
      final ownerSessionId = snapshot.data()?['sessionId'] as String?;
      if (!snapshot.exists || ownerSessionId != _sessionId) {
        _loseLease(InvoiceBuilderLockLossReason.ownershipChanged);
      }
    }, onError: (_) => _handleTemporaryRenewalFailure());
  }

  void _loseLease(InvoiceBuilderLockLossReason reason) {
    if (!_hasLease) return;
    _hasLease = false;
    _renewalTimer?.cancel();
    _renewalTimer = null;
    onLeaseLost?.call(reason);
  }

  Future<void> release() async {
    _released = true;
    _renewalTimer?.cancel();
    _renewalTimer = null;
    await _subscription?.cancel();
    _subscription = null;

    if (!_hasLease) return;
    final ref = _lockRef;
    _hasLease = false;
    if (ref == null) return;

    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        if (snapshot.data()?['sessionId'] == _sessionId) {
          transaction.delete(ref);
        }
      });
    } catch (_) {
      // The lease naturally expires after an abrupt close or offline release.
    }
  }

  Future<String> _getDeviceId() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_deviceIdPreferenceKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final generated = _generateRandomId();
    await preferences.setString(_deviceIdPreferenceKey, generated);
    return generated;
  }

  static String _generateRandomId() {
    final random = Random.secure();
    return List<String>.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }
}
