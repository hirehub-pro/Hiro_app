/// Keeps invoice-builder verification only for the lifetime of this app run.
///
/// This intentionally does not use SharedPreferences, secure storage, or any
/// other persistent store: stopping the app creates a fresh process and makes
/// the user verify again.
class InvoiceBuilderVerificationSession {
  InvoiceBuilderVerificationSession._();

  static String? _verifiedUserId;

  static bool isVerifiedFor(String? userId) =>
      userId != null && userId.isNotEmpty && _verifiedUserId == userId;

  static void markVerified(String userId) {
    _verifiedUserId = userId;
  }

  static void clear() {
    _verifiedUserId = null;
  }
}
