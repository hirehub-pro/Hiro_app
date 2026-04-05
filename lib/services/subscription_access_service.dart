import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SubscriptionAccessState {
  final String role;
  final bool isSubscribed;
  final String subscriptionStatus;

  const SubscriptionAccessState({
    required this.role,
    required this.isSubscribed,
    required this.subscriptionStatus,
  });

  bool get isWorker => role == 'worker';

  bool get hasActiveWorkerSubscription {
    if (!isWorker) return true;
    // Keep access when a user is marked subscribed even if status is stale.
    return isSubscribed;
  }

  bool get isUnsubscribedWorker => isWorker && !hasActiveWorkerSubscription;

  bool get hasActiveRenewingSubscription {
    if (!isWorker) return true;
    return subscriptionStatus == 'active';
  }
}

class SubscriptionAccessService {
  static const MethodChannel _billingStatusChannel = MethodChannel(
    'com.hirehub.app/subscription_status',
  );

  static const Set<String> _workerSubscriptionProductIds = {
    'pro_worker_monthly',
    'com-hiro-app-pro-worker-monthly',
  };

  static bool hasActiveWorkerSubscriptionFromData(Map<String, dynamic>? data) {
    final role = (data?['role'] ?? 'customer').toString().toLowerCase();
    if (role != 'worker') return true;

    final isSubscribed = data?['isSubscribed'] == true;
    return isSubscribed;
  }

  static Future<SubscriptionAccessState> getCurrentUserState() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const SubscriptionAccessState(
        role: 'guest',
        isSubscribed: false,
        subscriptionStatus: 'inactive',
      );
    }

    final firestore = FirebaseFirestore.instance;
    final doc = await firestore.collection('users').doc(user.uid).get();
    final data = doc.data() ?? <String, dynamic>{};
    final role = (data['role'] ?? 'customer').toString().toLowerCase();

    if (role == 'worker') {
      final playState = await _queryGooglePlayState();
      if (playState != null) {
        final mapped = _mapGooglePlayToAccessState(
          role: role,
          playState: playState,
        );

        await firestore.collection('users').doc(user.uid).set({
          'isSubscribed': mapped.isSubscribed,
          'subscriptionStatus': mapped.subscriptionStatus,
          'subscriptionCanceled': mapped.subscriptionStatus == 'inactive',
          'subscriptionUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        return mapped;
      }
    }

    final isSubscribed = data['isSubscribed'] == true;

    return SubscriptionAccessState(
      role: role,
      isSubscribed: isSubscribed,
      subscriptionStatus:
          data['subscriptionStatus']?.toString().toLowerCase() ??
          (isSubscribed ? 'active' : 'inactive'),
    );
  }

  static Future<String?> _queryGooglePlayState() async {
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
      return status;
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
          isSubscribed: true,
          subscriptionStatus: 'active',
        );
      case 'active_canceled':
        return SubscriptionAccessState(
          role: role,
          isSubscribed: true,
          subscriptionStatus: 'inactive',
        );
      default:
        return SubscriptionAccessState(
          role: role,
          isSubscribed: false,
          subscriptionStatus: 'inactive',
        );
    }
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
