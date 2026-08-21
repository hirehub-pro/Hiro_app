import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'dart:convert';

class SubscriptionAccessState {
  final String role;
  final String subscriptionStatus;
  final bool isVip;

  const SubscriptionAccessState({
    required this.role,
    required this.subscriptionStatus,
    this.isVip = false,
  });

  bool get isWorker => role == 'worker';

  bool get isSubscribed =>
      isVip ||
      SubscriptionAccessService.isEntitledSubscriptionStatus(
        subscriptionStatus,
      );

  bool get hasActiveWorkerSubscription {
    if (!isWorker) return true;
    if (isVip) return true;
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
  static const String _subscriptionSourceField = 'subscriptionSource';

  static bool hasActiveWorkerSubscriptionFromData(Map<String, dynamic>? data) {
    final role = (data?['role'] ?? 'customer').toString().toLowerCase();
    if (role != 'worker') return true;
    if (data?['isVIP'] == true) return true;

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

    // Entitlement identifiers are server-controlled. The deterministic token
    // is sent to the store/callable and persisted only after server-side
    // purchase verification succeeds.
    return subscriptionAccountTokenForUid(user.uid);
  }

  static Future<bool>
  isCurrentGooglePlaySubscriptionLinkedToAnotherAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final playSnapshot = await _queryGooglePlayState();
    if (playSnapshot == null || !playSnapshot.isActive) {
      return false;
    }

    // Cross-account ownership is checked by verifySubscriptionPurchase using
    // the Admin SDK. Client-side collection queries would expose private
    // purchase tokens and are intentionally denied by Firestore rules.
    return false;
  }

  static String? ownershipKeyForPurchase(PurchaseDetails purchaseDetails) {
    if (purchaseDetails is AppStorePurchaseDetails) {
      final originalTransactionId = purchaseDetails
          .skPaymentTransaction
          .originalTransaction
          ?.transactionIdentifier
          ?.trim();
      if (originalTransactionId != null && originalTransactionId.isNotEmpty) {
        return 'appstore:$originalTransactionId';
      }

      final purchaseId = purchaseDetails.purchaseID?.trim();
      if (purchaseId != null && purchaseId.isNotEmpty) {
        return 'appstore:$purchaseId';
      }
    }

    if (purchaseDetails is SK2PurchaseDetails) {
      final appAccountToken = purchaseDetails.appAccountToken?.trim();
      if (appAccountToken != null && appAccountToken.isNotEmpty) {
        return 'appstore-account:$appAccountToken';
      }

      final purchaseId = purchaseDetails.purchaseID?.trim();
      if (purchaseId != null && purchaseId.isNotEmpty) {
        return 'appstore-sk2:$purchaseId';
      }
    }

    final verificationToken = purchaseDetails
        .verificationData
        .serverVerificationData
        .trim();
    if (verificationToken.isNotEmpty) {
      return 'verification:$verificationToken';
    }

    final purchaseId = purchaseDetails.purchaseID?.trim();
    if (purchaseId != null && purchaseId.isNotEmpty) {
      return 'purchase:$purchaseId';
    }

    return null;
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
    final isVip = data['isVIP'] == true;

    if (role == 'worker') {
      if (isVip) {
        return SubscriptionAccessState(
          role: role,
          subscriptionStatus: _resolveSubscriptionStatusFromData(data),
          isVip: true,
        );
      }

      // Firestore contains the server-verified state. Store notifications,
      // explicit purchase verification and the scheduled backend refresh are
      // the only writers of entitlement fields.
      return SubscriptionAccessState(
        role: role,
        subscriptionStatus: _resolveSubscriptionStatusFromData(data),
      );
    }

    return SubscriptionAccessState(
      role: role,
      subscriptionStatus: _resolveSubscriptionStatusFromData(data),
      isVip: isVip,
    );
  }

  static Future<void> refreshCurrentUserStateInBackground() async {
    try {
      await refreshCurrentUserState();
    } catch (e) {
      debugPrint('Subscription refresh skipped: $e');
    }
  }

  static bool _hasGooglePlayHistory(Map<String, dynamic>? data) {
    final source = (data?[_subscriptionSourceField] ?? '')
        .toString()
        .toLowerCase();
    if (source == 'google_play') return true;

    final platform = (data?['subscriptionPlatform'] ?? '')
        .toString()
        .toLowerCase();
    if (platform.contains('google_play') || platform.contains('play')) {
      return true;
    }

    final productId = (data?['subscriptionProductId'] ?? '').toString();
    return _workerSubscriptionProductIds.contains(productId);
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

  static String _resolveSubscriptionStatusFromData(Map<String, dynamic>? data) {
    final status = (data?['subscriptionStatus'] ?? '').toString().toLowerCase();
    if (!isEntitledSubscriptionStatus(status)) {
      return 'inactive';
    }

    if (_hasGooglePlayHistory(data)) {
      return status;
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
