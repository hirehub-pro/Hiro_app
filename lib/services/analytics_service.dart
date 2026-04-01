import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  AnalyticsService._();

  static FirebaseAnalytics get _analytics => FirebaseAnalytics.instance;

  static FirebaseAnalyticsObserver get observer =>
      FirebaseAnalyticsObserver(analytics: _analytics);

  static Future<void> logAppOpen() async {
    try {
      await _analytics.logAppOpen();
    } catch (_) {}
  }

  static Future<void> setCurrentScreen(String screenName) async {
    try {
      await _analytics.logScreenView(screenName: screenName);
    } catch (_) {}
  }

  static Future<void> logSignInCodeRequested() async {
    await _logEvent('sign_in_code_requested');
  }

  static Future<void> logSignInSuccess({required String method}) async {
    try {
      await _analytics.logLogin(loginMethod: method);
    } catch (_) {}
    await _logEvent('sign_in_success', parameters: {'method': method});
  }

  static Future<void> logGuestSignIn() async {
    await _logEvent('guest_sign_in');
  }

  static Future<void> logSignUpCodeRequested({required String userType}) async {
    await _logEvent(
      'sign_up_code_requested',
      parameters: {'user_type': userType},
    );
  }

  static Future<void> logSignUpCompleted({
    required String userType,
    required bool hasEmail,
  }) async {
    try {
      await _analytics.logSignUp(signUpMethod: 'phone');
    } catch (_) {}
    await _logEvent(
      'sign_up_completed',
      parameters: {'user_type': userType, 'has_email': hasEmail},
    );
  }

  static Future<void> logSearchProfession(String profession) async {
    await _logEvent(
      'profession_search',
      parameters: {'profession': profession},
    );
  }

  static Future<void> logWorkerProfileOpened({
    required String source,
    String? profession,
  }) async {
    final params = <String, Object>{'source': source};
    if (profession != null && profession.isNotEmpty) {
      params['profession'] = profession;
    }
    await _logEvent('worker_profile_opened', parameters: params);
  }

  static Future<void> _logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    try {
      await _analytics.logEvent(name: name, parameters: parameters);
    } catch (_) {}
  }
}
