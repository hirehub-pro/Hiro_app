import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A short-lived, per-device lease for the Invoice Builder.
///
/// The document path and field names are shared with the Hiro website; keep
/// them in sync with that client.
class InvoiceBuilderLockService {
  InvoiceBuilderLockService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  static const _deviceIdPreferenceKey = 'invoice_builder_device_id';
  static const _leaseDuration = Duration(seconds: 60);
  static const _renewalInterval = Duration(seconds: 20);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String? _deviceId;
  DocumentReference<Map<String, dynamic>>? _lockRef;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  Timer? _renewalTimer;
  bool _hasLease = false;
  bool _released = false;

  /// Called when this device no longer owns the lock.
  void Function()? onLeaseLost;

  Future<bool> acquire() async {
    if (_released) return false;
    final user = _auth.currentUser;
    if (user == null) return false;

    _deviceId = await _getDeviceId();
    _lockRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('invoice_builder_lock')
        .doc('active');

    final acquired = await _claimOrRenew();
    if (!acquired) return false;

    // A transaction result alone is not enough to unlock the UI: make sure
    // the committed document is visible from the Firestore server first.
    // This prevents cached/offline state from granting access on two clients.
    if (!await _confirmOwnershipFromServer()) return false;

    _hasLease = true;
    if (_released) {
      await release();
      return false;
    }
    _listenForOwnershipChanges();
    _renewalTimer = Timer.periodic(_renewalInterval, (_) => _renew());
    return true;
  }

  Future<void> _renew() async {
    if (!_hasLease ||
        !await _claimOrRenew() ||
        !await _confirmOwnershipFromServer()) {
      _loseLease();
    }
  }

  Future<bool> _claimOrRenew() async {
    final ref = _lockRef;
    final deviceId = _deviceId;
    if (ref == null || deviceId == null) return false;

    try {
      return await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        final data = snapshot.data();
        final owner = data?['deviceId'] as String?;
        final expiresAtMs = (data?['expiresAtMs'] as num?)?.toInt() ?? 0;
        final nowMs = DateTime.now().millisecondsSinceEpoch;

        if (snapshot.exists && owner != deviceId && expiresAtMs > nowMs) {
          return false;
        }

        transaction.set(ref, {
          'deviceId': deviceId,
          'expiresAtMs': nowMs + _leaseDuration.inMilliseconds,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
    } catch (_) {
      // An offline transaction cannot safely establish exclusive ownership.
      return false;
    }
  }

  Future<bool> _confirmOwnershipFromServer() async {
    final ref = _lockRef;
    final deviceId = _deviceId;
    if (ref == null || deviceId == null) return false;

    try {
      final snapshot = await ref.get(const GetOptions(source: Source.server));
      final data = snapshot.data();
      final owner = data?['deviceId'] as String?;
      final expiresAtMs = (data?['expiresAtMs'] as num?)?.toInt() ?? 0;
      return owner == deviceId &&
          expiresAtMs > DateTime.now().millisecondsSinceEpoch;
    } catch (_) {
      // Never grant or retain exclusive access from cache-only state.
      return false;
    }
  }

  void _listenForOwnershipChanges() {
    _subscription?.cancel();
    final ref = _lockRef;
    final deviceId = _deviceId;
    if (ref == null || deviceId == null) return;

    _subscription = ref.snapshots().listen((snapshot) {
      final owner = snapshot.data()?['deviceId'] as String?;
      if (!snapshot.exists || owner != deviceId) {
        _loseLease();
      }
    }, onError: (_) => _loseLease());
  }

  void _loseLease() {
    if (!_hasLease) return;
    _hasLease = false;
    _renewalTimer?.cancel();
    _renewalTimer = null;
    onLeaseLost?.call();
  }

  Future<void> release() async {
    _released = true;
    _renewalTimer?.cancel();
    _renewalTimer = null;
    await _subscription?.cancel();
    _subscription = null;

    if (!_hasLease) return;
    final ref = _lockRef;
    final deviceId = _deviceId;
    _hasLease = false;
    if (ref == null || deviceId == null) return;

    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        if (snapshot.data()?['deviceId'] == deviceId) {
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

    final random = Random.secure();
    final generated = List<String>.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    await preferences.setString(_deviceIdPreferenceKey, generated);
    return generated;
  }
}
