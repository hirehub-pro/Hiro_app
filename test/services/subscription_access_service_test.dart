import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/services/subscription_access_service.dart';

void main() {
  group('hasActiveWorkerSubscriptionFromData', () {
    test('treats a VIP worker as active Pro without a subscription', () {
      final hasAccess =
          SubscriptionAccessService.hasActiveWorkerSubscriptionFromData({
            'role': 'worker',
            'subscriptionStatus': 'inactive',
            'isVIP': true,
          });

      expect(hasAccess, isTrue);
    });

    test('keeps the existing subscription rule for non-VIP workers', () {
      final hasAccess =
          SubscriptionAccessService.hasActiveWorkerSubscriptionFromData({
            'role': 'worker',
            'subscriptionStatus': 'inactive',
            'isVIP': false,
          });

      expect(hasAccess, isFalse);
    });
  });
}
