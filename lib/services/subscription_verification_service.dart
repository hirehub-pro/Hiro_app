import 'package:cloud_functions/cloud_functions.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

import 'subscription_access_service.dart';

class SubscriptionVerificationResult {
  final bool isSubscribed;
  final String subscriptionStatus;
  final String? subscriptionProductId;
  final String? subscriptionPlatform;
  final String? subscriptionPurchaseId;
  final String? subscriptionPurchaseToken;
  final String? subscriptionTransactionDate;
  final String? subscriptionAccountToken;
  final String? subscriptionOwnershipKey;
  final String? subscriptionOriginalTransactionId;
  final DateTime? subscriptionDate;
  final DateTime? subscriptionExpiresAt;

  const SubscriptionVerificationResult({
    required this.isSubscribed,
    required this.subscriptionStatus,
    this.subscriptionProductId,
    this.subscriptionPlatform,
    this.subscriptionPurchaseId,
    this.subscriptionPurchaseToken,
    this.subscriptionTransactionDate,
    this.subscriptionAccountToken,
    this.subscriptionOwnershipKey,
    this.subscriptionOriginalTransactionId,
    this.subscriptionDate,
    this.subscriptionExpiresAt,
  });

  factory SubscriptionVerificationResult.fromMap(Map<Object?, Object?> map) {
    final data = Map<String, dynamic>.from(
      map.map((key, value) => MapEntry(key.toString(), value)),
    );

    return SubscriptionVerificationResult(
      isSubscribed: data['isSubscribed'] == true,
      subscriptionStatus: (data['subscriptionStatus'] ?? 'inactive')
          .toString()
          .toLowerCase(),
      subscriptionProductId: data['subscriptionProductId']?.toString(),
      subscriptionPlatform: data['subscriptionPlatform']?.toString(),
      subscriptionPurchaseId: data['subscriptionPurchaseId']?.toString(),
      subscriptionPurchaseToken: data['subscriptionPurchaseToken']?.toString(),
      subscriptionTransactionDate: data['subscriptionTransactionDate']
          ?.toString(),
      subscriptionAccountToken: data['subscriptionAccountToken']?.toString(),
      subscriptionOwnershipKey: data['subscriptionOwnershipKey']?.toString(),
      subscriptionOriginalTransactionId:
          data['subscriptionOriginalTransactionId']?.toString(),
      subscriptionDate: _parseDate(data['subscriptionDate']),
      subscriptionExpiresAt: _parseDate(data['subscriptionExpiresAt']),
    );
  }

  Map<String, dynamic> toPendingWorkerData() {
    return {
      'isSubscribed': isSubscribed,
      'subscriptionStatus': subscriptionStatus,
      'subscriptionCanceled': subscriptionStatus != 'active',
      'subscriptionProductId': subscriptionProductId,
      'subscriptionPlatform': subscriptionPlatform,
      'subscriptionPurchaseId': subscriptionPurchaseId,
      'subscriptionPurchaseToken': subscriptionPurchaseToken,
      'subscriptionTransactionDate': subscriptionTransactionDate,
      'subscriptionAccountToken': subscriptionAccountToken,
      'subscriptionOwnershipKey': subscriptionOwnershipKey,
      'subscriptionOriginalTransactionId': subscriptionOriginalTransactionId,
      'subscriptionDate': subscriptionDate?.toIso8601String(),
      'subscriptionExpiresAt': subscriptionExpiresAt?.toIso8601String(),
    };
  }

  static DateTime? _parseDate(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}

class SubscriptionVerificationService {
  SubscriptionVerificationService._();

  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  static Future<SubscriptionVerificationResult> verifyPurchase({
    required PurchaseDetails purchaseDetails,
    required bool isNewRegistration,
  }) async {
    final accountToken =
        await SubscriptionAccessService.ensureCurrentUserSubscriptionAccountToken();
    final callable = _functions.httpsCallable('verifySubscriptionPurchase');

    final response = await callable.call<Map<String, dynamic>>({
      'productId': purchaseDetails.productID,
      'purchaseId': purchaseDetails.purchaseID,
      'verificationToken':
          purchaseDetails.verificationData.serverVerificationData,
      'verificationSource': purchaseDetails.verificationData.source,
      'transactionDate': purchaseDetails.transactionDate,
      'applicationAccountToken': accountToken,
      'ownershipKey': SubscriptionAccessService.ownershipKeyForPurchase(
        purchaseDetails,
      ),
      'isNewRegistration': isNewRegistration,
      if (purchaseDetails is AppStorePurchaseDetails)
        'originalTransactionId': purchaseDetails
            .skPaymentTransaction
            .originalTransaction
            ?.transactionIdentifier,
      if (purchaseDetails is SK2PurchaseDetails)
        'appAccountToken': purchaseDetails.appAccountToken,
    });

    return SubscriptionVerificationResult.fromMap(response.data);
  }
}
