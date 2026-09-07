import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/services/subscription_access_service.dart';

void main() {
  final now = DateTime.utc(2026, 9, 7, 12);

  test('generates the server-matched subscription account token', () {
    expect(
      SubscriptionAccessService.subscriptionAccountTokenForUid('test-user-123'),
      '8b374f5a-f4f2-5215-ada8-9afbe05ab8c1',
    );
  });

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

    test('allows an active Android subscription before its expiry', () {
      final hasAccess =
          SubscriptionAccessService.hasActiveWorkerSubscriptionFromData({
            'role': 'worker',
            'subscriptionSource': 'google_play',
            'subscriptionStatus': 'active',
            'subscriptionExpiresAt': DateTime.utc(2026, 10, 7),
          }, now: now);

      expect(hasAccess, isTrue);
    });

    test('blocks an expired Android subscription even if status is active', () {
      final hasAccess =
          SubscriptionAccessService.hasActiveWorkerSubscriptionFromData({
            'role': 'worker',
            'subscriptionSource': 'google_play',
            'subscriptionStatus': 'active',
            'subscriptionExpiresAt': DateTime.utc(2026, 9, 7, 11, 59),
          }, now: now);

      expect(hasAccess, isFalse);
    });

    test('keeps canceled subscriptions active only until their expiry', () {
      final future =
          SubscriptionAccessService.hasActiveWorkerSubscriptionFromData({
            'role': 'worker',
            'subscriptionSource': 'google_play',
            'subscriptionStatus': 'active_canceled',
            'subscriptionExpiresAt': DateTime.utc(2026, 9, 8),
          }, now: now);
      final expired =
          SubscriptionAccessService.hasActiveWorkerSubscriptionFromData({
            'role': 'worker',
            'subscriptionSource': 'google_play',
            'subscriptionStatus': 'active_canceled',
            'subscriptionExpiresAt': DateTime.utc(2026, 9, 7, 11, 59),
          }, now: now);

      expect(future, isTrue);
      expect(expired, isFalse);
    });

    test('blocks active status when the verified expiration is missing', () {
      final hasAccess =
          SubscriptionAccessService.hasActiveWorkerSubscriptionFromData({
            'role': 'worker',
            'subscriptionSource': 'google_play',
            'subscriptionStatus': 'active',
          }, now: now);

      expect(hasAccess, isFalse);
    });

    test('applies the same expiration rule to an iOS subscription', () {
      final hasAccess =
          SubscriptionAccessService.hasActiveWorkerSubscriptionFromData({
            'role': 'worker',
            'subscriptionSource': 'app_store',
            'subscriptionStatus': 'active',
            'subscriptionExpiresAt': DateTime.utc(2026, 9, 7, 11, 59),
          }, now: now);

      expect(hasAccess, isFalse);
    });
  });
}
