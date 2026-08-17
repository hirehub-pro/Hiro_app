import 'package:flutter/foundation.dart';

class AppNavigationService {
  AppNavigationService._();

  static final ValueNotifier<int> homeRequests = ValueNotifier<int>(0);

  static void requestHome() {
    homeRequests.value++;
  }
}
