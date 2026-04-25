import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

class SubscriptionAccessState {
  final String role;
  final String subscriptionStatus;

  const SubscriptionAccessState({
    required this.role,
    required this.subscriptionStatus,
  });

  bool get isWorker => role == 'worker';

  bool get isSubscribed =>
      SubscriptionAccessService.isEntitledSubscriptionStatus(
        subscriptionStatus,
      );

  bool get hasActiveWorkerSubscription {
    if (!isWorker) return true;
    return SubscriptionAccessService.isEntitledSubscriptionStatus(
      subscriptionStatus,
    );
  }

  bool get isUnsubscribedWorker => isWorker && !hasActiveWorkerSubscription;

  bool get hasActiveRenewingSubscription {
    if (!isWorker) return true;
    return subscriptionStatus == 'active';
  }
}

class GooglePlaySubscriptionSnapshot {
  final String status;
  final String? productId;
  final String? purchaseToken;
  final String? orderId;

  const GooglePlaySubscriptionSnapshot({
    required this.status,
    this.productId,
    this.purchaseToken,
    this.orderId,
  });

  bool get isActive =>
      status == 'active_renewing' || status == 'active_canceled';
}

class SubscriptionAccessService {
  static const MethodChannel _billingStatusChannel = MethodChannel(
    'com.hirehub.app/subscription_status',
  );

  static const Set<String> _workerSubscriptionProductIds = {
    'pro_worker_monthly',
    'com-hiro-app-pro-worker-monthly',
  };

  static const String _subscriptionAccountTokenField =
      'subscriptionAccountToken';

  static bool hasActiveWorkerSubscriptionFromData(Map<String, dynamic>? data) {
    final role = (data?['role'] ?? 'customer').toString().toLowerCase();
    if (role != 'worker') return true;

    return _resolveSubscriptionStatusFromData(data) != 'inactive';
  }

  static bool isEntitledSubscriptionStatus(String? status) {
    final normalized = (status ?? '').toLowerCase();
    return normalized == 'active' || normalized == 'active_canceled';
  }

  static String subscriptionAccountTokenForUid(String uid) {
    final digest = sha1.convert(utf8.encode('hirehub-subscription::$uid'));
    final hex = digest.toString().padRight(32, '0').substring(0, 32);
    final chars = hex.split('');

    chars[12] = '5';
    final variant = int.parse(chars[16], radix: 16);
    chars[16] = ((variant & 0x3) | 0x8).toRadixString(16);

    final normalized = chars.join();
    return '${normalized.substring(0, 8)}-'
        '${normalized.substring(8, 12)}-'
        '${normalized.substring(12, 16)}-'
        '${normalized.substring(16, 20)}-'
        '${normalized.substring(20, 32)}';
  }

  static Future<String?> ensureCurrentUserSubscriptionAccountToken({
    Map<String, dynamic>? existingData,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final token = subscriptionAccountTokenForUid(user.uid);
    final currentValue =
        existingData?[_subscriptionAccountTokenField]?.toString().trim() ?? '';

    if (currentValue == token) {
      return token;
    }

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      _subscriptionAccountTokenField: token,
    }, SetOptions(merge: true));
    return token;
  }

  static Future<bool>
  isCurrentGooglePlaySubscriptionLinkedToAnotherAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final playSnapshot = await _queryGooglePlayState();
    if (playSnapshot == null || !playSnapshot.isActive) {
      return false;
    }

    final purchaseToken = playSnapshot.purchaseToken?.trim();
    if (purchaseToken == null || purchaseToken.isEmpty) {
      return false;
    }

    final ownerQuery = await FirebaseFirestore.instance
        .collection('users')
        .where('subscriptionPurchaseToken', isEqualTo: purchaseToken)
        .limit(1)
        .get();

    return ownerQuery.docs.isNotEmpty && ownerQuery.docs.first.id != user.uid;
  }

  static Future<SubscriptionAccessState> getCurrentUserState() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const SubscriptionAccessState(
        role: 'guest',
        subscriptionStatus: 'inactive',
      );
    }

    return refreshCurrentUserState();
  }

  static Future<SubscriptionAccessState> refreshCurrentUserState() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const SubscriptionAccessState(
        role: 'guest',
        subscriptionStatus: 'inactive',
      );
    }

    final firestore = FirebaseFirestore.instance;
    final doc = await firestore.collection('users').doc(user.uid).get();
    final data = doc.data() ?? <String, dynamic>{};
    final role = (data['role'] ?? 'customer').toString().toLowerCase();
    await ensureCurrentUserSubscriptionAccountToken(existingData: data);

    if (role == 'worker') {
      final normalizedState = await _syncExpiredSubscriptionIfNeeded(
        userRef: doc.reference,
        data: data,
      );

      final syncedState = await syncCurrentUserWithGooglePlay(
        existingData: {
          ...data,
          'subscriptionStatus': normalizedState.subscriptionStatus,
        },
      );
      if (syncedState != null) {
        return syncedState;
      }

      return normalizedState;
    }

    return SubscriptionAccessState(
      role: role,
      subscriptionStatus: _resolveSubscriptionStatusFromData(data),
    );
  }

  static Future<void> refreshCurrentUserStateInBackground() async {
    try {
      await refreshCurrentUserState();
    } catch (e) {
      debugPrint('Subscription refresh skipped: $e');
    }
  }

  static Future<SubscriptionAccessState?> syncCurrentUserWithGooglePlay({
    Map<String, dynamic>? existingData,
    bool allowClaimUnownedPurchase = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final firestore = FirebaseFirestore.instance;
    final userRef = firestore.collection('users').doc(user.uid);
    final data = existingData ?? (await userRef.get()).data();
    final role = (data?['role'] ?? 'customer').toString().toLowerCase();
    if (role != 'worker') return null;

    final playSnapshot = await _queryGooglePlayState();
    if (playSnapshot == null) return null;

    final mapped = _mapGooglePlayToAccessState(
      role: role,
      playState: playSnapshot.status,
    );

    if (!playSnapshot.isActive) {
      await userRef.set({
        'isSubscribed': false,
        'subscriptionStatus': mapped.subscriptionStatus,
        'subscriptionCanceled': true,
        'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return mapped;
    }

    final purchaseToken = playSnapshot.purchaseToken?.trim();
    if (purchaseToken == null || purchaseToken.isEmpty) {
      return null;
    }

    final storedToken =
        data?['subscriptionPurchaseToken']?.toString().trim() ?? '';

    final ownerQuery = await firestore
        .collection('users')
        .where('subscriptionPurchaseToken', isEqualTo: purchaseToken)
        .limit(1)
        .get();

    if (ownerQuery.docs.isNotEmpty && ownerQuery.docs.first.id != user.uid) {
      debugPrint(
        'Ignoring Google Play subscription for ${user.uid} because token belongs to ${ownerQuery.docs.first.id}.',
      );
      await userRef.set({
        'isSubscribed': false,
        'subscriptionStatus': 'inactive',
        'subscriptionCanceled': true,
        'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return SubscriptionAccessState(
        role: role,
        subscriptionStatus: 'inactive',
      );
    }

    final ownsStoredToken =
        storedToken.isNotEmpty && storedToken == purchaseToken;
    final canClaimUnownedToken =
        allowClaimUnownedPurchase && ownerQuery.docs.isEmpty;

    if (!ownsStoredToken && !canClaimUnownedToken) {
      debugPrint(
        'Ignoring unclaimed Google Play subscription for ${user.uid}; token is not bound to this account.',
      );
      await userRef.set({
        'isSubscribed': false,
        'subscriptionStatus': 'inactive',
        'subscriptionCanceled': true,
        'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return SubscriptionAccessState(
        role: role,
        subscriptionStatus: 'inactive',
      );
    }

    await userRef.set({
      'isSubscribed': mapped.isSubscribed,
      'subscriptionStatus': mapped.subscriptionStatus,
      'subscriptionCanceled': playSnapshot.status == 'active_canceled',
      'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
      'subscriptionPurchaseToken': purchaseToken,
      'subscriptionProductId':
          playSnapshot.productId ?? data?['subscriptionProductId'],
      'subscriptionPurchaseOrderId':
          playSnapshot.orderId ?? data?['subscriptionPurchaseOrderId'],
    }, SetOptions(merge: true));

    return mapped;
  }

  static Future<GooglePlaySubscriptionSnapshot?> _queryGooglePlayState() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }

    try {
      final dynamic response = await _billingStatusChannel.invokeMethod(
        'getSubscriptionState',
        {'productIds': _workerSubscriptionProductIds.toList()},
      );

      if (response is! Map) return null;
      final result = Map<String, dynamic>.from(response);
      final status = (result['status'] ?? '').toString().toLowerCase();
      if (status.isEmpty) return null;
      return GooglePlaySubscriptionSnapshot(
        status: status,
        productId: result['productId']?.toString(),
        purchaseToken: result['purchaseToken']?.toString(),
        orderId: result['orderId']?.toString(),
      );
    } on PlatformException catch (e) {
      debugPrint('Google Play state read failed: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('Google Play state read failed: $e');
      return null;
    }
  }

  static SubscriptionAccessState _mapGooglePlayToAccessState({
    required String role,
    required String playState,
  }) {
    switch (playState) {
      case 'active_renewing':
        return SubscriptionAccessState(
          role: role,
          subscriptionStatus: 'active',
        );
      case 'active_canceled':
        return SubscriptionAccessState(
          role: role,
          subscriptionStatus: 'active_canceled',
        );
      default:
        return SubscriptionAccessState(
          role: role,
          subscriptionStatus: 'inactive',
        );
    }
  }

  static Future<SubscriptionAccessState> _syncExpiredSubscriptionIfNeeded({
    required DocumentReference<Map<String, dynamic>> userRef,
    required Map<String, dynamic>? data,
  }) async {
    final role = (data?['role'] ?? 'customer').toString().toLowerCase();
    final resolvedStatus = _resolveSubscriptionStatusFromData(data);

    if (role == 'worker' && resolvedStatus == 'inactive') {
      final storedStatus = (data?['subscriptionStatus'] ?? '')
          .toString()
          .toLowerCase();
      final isSubscribed = data?['isSubscribed'] == true;

      if (storedStatus != 'inactive' || isSubscribed) {
        await userRef.set({
          'isSubscribed': false,
          'subscriptionStatus': 'inactive',
          'subscriptionCanceled': true,
          'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    return SubscriptionAccessState(
      role: role,
      subscriptionStatus: resolvedStatus,
    );
  }

  static String _resolveSubscriptionStatusFromData(Map<String, dynamic>? data) {
    final status = (data?['subscriptionStatus'] ?? '').toString().toLowerCase();
    if (!isEntitledSubscriptionStatus(status)) {
      return 'inactive';
    }

    final expiry = _resolveExpiryDate(data);
    if (expiry == null) {
      return status;
    }

    return DateTime.now().isBefore(expiry) ? status : 'inactive';
  }

  static DateTime? _resolveExpiryDate(Map<String, dynamic>? data) {
    final directExpiry = _toDate(data?['subscriptionExpiresAt']);
    if (directExpiry != null) {
      return directExpiry;
    }

    final subscriptionDate = _toDate(data?['subscriptionDate']);
    if (subscriptionDate == null) {
      return null;
    }

    return subscriptionDate.add(const Duration(days: 30));
  }

  static DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      return parsed;
    }
    return null;
  }

  static Scaffold buildLockedScaffold({
    required String title,
    required String message,
  }) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1976D2),
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.workspace_premium_outlined,
                size: 72,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
