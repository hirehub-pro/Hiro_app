import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';

import 'subscription_verification_service.dart';

enum SubscriptionPurchaseEventType {
  pending,
  verified,
  inactive,
  canceled,
  storeError,
  verificationError,
  ownershipConflict,
  completionError,
}

class SubscriptionPurchaseEvent {
  const SubscriptionPurchaseEvent({
    required this.type,
    required this.purchaseDetails,
    this.verification,
    this.error,
  });

  final SubscriptionPurchaseEventType type;
  final PurchaseDetails purchaseDetails;
  final SubscriptionVerificationResult? verification;
  final Object? error;
}

/// Owns the store purchase stream for the lifetime of the application.
///
/// UI pages may come and go, but verification and transaction completion must
/// continue until the store transaction reaches a safe terminal state.
class SubscriptionPurchaseCoordinator {
  SubscriptionPurchaseCoordinator._();

  static final SubscriptionPurchaseCoordinator instance =
      SubscriptionPurchaseCoordinator._();

  static const Set<String> supportedProductIds = {
    'HIRO_SUBSCRIPTION',
    'pro_worker_monthly',
    'com-hiro-app-pro-worker-monthly',
  };

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final StreamController<SubscriptionPurchaseEvent> _events =
      StreamController<SubscriptionPurchaseEvent>.broadcast();
  final Set<String> _queuedPurchases = <String>{};

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Future<void> _processingQueue = Future<void>.value();
  Future<void>? _startFuture;
  bool _started = false;

  Stream<SubscriptionPurchaseEvent> get events => _events.stream;

  Future<void> start() {
    if (kIsWeb) return Future<void>.value();
    return _startFuture ??= _start();
  }

  Future<void> _start() async {
    if (_started) return;

    try {
      if (_isApplePlatform) {
        final storeKit = _inAppPurchase
            .getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
        await storeKit.setDelegate(_SubscriptionPaymentQueueDelegate());
      }

      _purchaseSubscription = _inAppPurchase.purchaseStream.listen(
        _enqueuePurchases,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Purchase stream error: $error');
          debugPrintStack(stackTrace: stackTrace);
        },
      );
      _started = true;
    } catch (_) {
      _startFuture = null;
      rethrow;
    }
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    _startFuture = null;
    await _purchaseSubscription?.cancel();
    _purchaseSubscription = null;

    if (_isApplePlatform) {
      final storeKit = _inAppPurchase
          .getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
      await storeKit.setDelegate(null);
    }
  }

  bool get _isApplePlatform =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  void _enqueuePurchases(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      final key = _purchaseKey(purchase);
      if (!_queuedPurchases.add(key)) continue;

      _processingQueue = _processingQueue.then((_) async {
        try {
          await _processPurchase(purchase);
        } catch (error, stackTrace) {
          // Keep one unexpected purchase failure from stopping the queue.
          debugPrint('Unexpected purchase processing error: $error');
          debugPrintStack(stackTrace: stackTrace);
          _emit(
            SubscriptionPurchaseEvent(
              type: SubscriptionPurchaseEventType.verificationError,
              purchaseDetails: purchase,
              error: error,
            ),
          );
        } finally {
          _queuedPurchases.remove(key);
        }
      });
    }
  }

  Future<void> _processPurchase(PurchaseDetails purchase) async {
    switch (purchase.status) {
      case PurchaseStatus.pending:
        _emit(
          SubscriptionPurchaseEvent(
            type: SubscriptionPurchaseEventType.pending,
            purchaseDetails: purchase,
          ),
        );
        return;
      case PurchaseStatus.canceled:
        _emit(
          SubscriptionPurchaseEvent(
            type: SubscriptionPurchaseEventType.canceled,
            purchaseDetails: purchase,
          ),
        );
        return;
      case PurchaseStatus.error:
        _emit(
          SubscriptionPurchaseEvent(
            type: SubscriptionPurchaseEventType.storeError,
            purchaseDetails: purchase,
            error: purchase.error,
          ),
        );
        return;
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        break;
    }

    if (!supportedProductIds.contains(purchase.productID)) {
      debugPrint('Ignoring unsupported purchase: ${purchase.productID}');
      return;
    }

    if (purchase.verificationData.serverVerificationData.trim().isEmpty) {
      _emit(
        SubscriptionPurchaseEvent(
          type: SubscriptionPurchaseEventType.verificationError,
          purchaseDetails: purchase,
          error: StateError('The store returned empty verification data.'),
        ),
      );
      return;
    }

    SubscriptionVerificationResult verification;
    try {
      verification = await SubscriptionVerificationService.verifyPurchase(
        purchaseDetails: purchase,
        // Registration affects UI routing, not whether a receipt is genuine.
        isNewRegistration: false,
      );
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'already-exists') {
        if (!await _completeIfNeeded(purchase)) return;
        _emit(
          SubscriptionPurchaseEvent(
            type: SubscriptionPurchaseEventType.ownershipConflict,
            purchaseDetails: purchase,
            error: error,
          ),
        );
      } else {
        _emit(
          SubscriptionPurchaseEvent(
            type: SubscriptionPurchaseEventType.verificationError,
            purchaseDetails: purchase,
            error: error,
          ),
        );
      }
      return;
    } catch (error) {
      // Do not complete after a temporary verification failure. An unfinished
      // transaction can be delivered again by the store on a later app start.
      _emit(
        SubscriptionPurchaseEvent(
          type: SubscriptionPurchaseEventType.verificationError,
          purchaseDetails: purchase,
          error: error,
        ),
      );
      return;
    }

    // Verification writes the entitlement on the trusted backend. Only after
    // that succeeds is it safe to acknowledge/finish the store transaction.
    if (!await _completeIfNeeded(purchase)) return;

    _emit(
      SubscriptionPurchaseEvent(
        type: verification.isSubscribed
            ? SubscriptionPurchaseEventType.verified
            : SubscriptionPurchaseEventType.inactive,
        purchaseDetails: purchase,
        verification: verification,
      ),
    );
  }

  Future<bool> _completeIfNeeded(PurchaseDetails purchase) async {
    if (!purchase.pendingCompletePurchase) return true;
    try {
      await _inAppPurchase.completePurchase(purchase);
      return true;
    } catch (error, stackTrace) {
      debugPrint('Could not complete store transaction: $error');
      debugPrintStack(stackTrace: stackTrace);
      _emit(
        SubscriptionPurchaseEvent(
          type: SubscriptionPurchaseEventType.completionError,
          purchaseDetails: purchase,
          error: error,
        ),
      );
      return false;
    }
  }

  void _emit(SubscriptionPurchaseEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  String _purchaseKey(PurchaseDetails purchase) {
    final purchaseId = purchase.purchaseID?.trim();
    if (purchaseId != null && purchaseId.isNotEmpty) {
      return '${purchase.productID}:$purchaseId';
    }
    final verificationToken = purchase.verificationData.serverVerificationData
        .trim();
    if (verificationToken.isNotEmpty) {
      return '${purchase.productID}:$verificationToken';
    }
    return '${purchase.productID}:${purchase.transactionDate ?? 'unknown'}';
  }
}

class _SubscriptionPaymentQueueDelegate
    implements SKPaymentQueueDelegateWrapper {
  @override
  bool shouldContinueTransaction(
    SKPaymentTransactionWrapper transaction,
    SKStorefrontWrapper storefront,
  ) {
    return true;
  }

  @override
  bool shouldShowPriceConsent() {
    return true;
  }
}
