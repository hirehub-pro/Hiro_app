import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

// Must be a top-level function for background handling
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // FCM automatically shows notifications in the background if they contain a 'notification' object.
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static StreamSubscription? _notificationSubscription;
  static bool _isInitialized = false;
  static bool _isListening = false;
  static String? _activeUserId;

  static Future<void> init() async {
    if (_isInitialized) return;

    // 1. Android/iOS local settings
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap
      },
    );

    // 2. Setup FCM Background Handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 3. Handle Foreground FCM messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        _showNotification(
          id: message.hashCode,
          title: message.notification!.title ?? '',
          body: message.notification!.body ?? '',
        );
      }
    });

    _isInitialized = true;
  }

  /// Saves the FCM token to the user's document in Firestore
  static Future<void> saveDeviceToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;

    try {
      // Request permission for iOS/Android 13+
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        String? token = await _messaging.getToken();
        if (token != null) {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'fcmToken': token,
            'lastTokenUpdate': FieldValue.serverTimestamp(),
            'platform': Platform.isAndroid ? 'android' : 'ios',
          }, SetOptions(merge: true));
        }
      }
    } catch (e) {
      debugPrint("Error saving FCM token: $e");
    }
  }

  /// Sends a push notification to a specific device token.
  /// Note: In production, use Firebase Cloud Functions to keep your server key secure.
  static Future<void> sendPushNotification({
    required String targetToken,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      // Note: This is a placeholder for where you would call your backend or Cloud Function.
      // If you are using FCM Legacy API (not recommended for production apps on stores):
      /*
      await http.post(
        Uri.parse('https://fcm.googleapis.com/fcm/send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'key=YOUR_SERVER_KEY',
        },
        body: jsonEncode({
          'to': targetToken,
          'notification': {'title': title, 'body': body},
          'data': data ?? {'click_action': 'FLUTTER_NOTIFICATION_CLICK'},
        }),
      );
      */
      debugPrint("FCM notification request for token: $targetToken");
      debugPrint("Title: $title, Body: $body");
    } catch (e) {
      debugPrint("Error sending push notification: $e");
    }
  }

  static void startListening() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      stopListening();
      return;
    }

    // Prevent multiple listeners for the same user
    if (_isListening && _activeUserId == user.uid) return;
    
    _isListening = true;
    _activeUserId = user.uid;

    saveDeviceToken(); 
    _notificationSubscription?.cancel();

    // Listener for the internal notification collection (UI updates)
    bool isInitialLoad = true;
    _notificationSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) async {
      if (isInitialLoad) {
        isInitialLoad = false;
        return;
      }

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final bool enabled = userDoc.data()?['notificationsEnabled'] ?? true;

        if (enabled) {
          _showNotification(
            id: snapshot.docs.first.id.hashCode,
            title: data['title'] ?? 'New Notification',
            body: data['body'] ?? 'You have a new update.',
          );
        }
      }
    }, onError: (e) => debugPrint("Notification Stream Error: $e"));
  }

  static void stopListening() {
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
    _isListening = false;
    _activeUserId = null;
  }

  static Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'main_channel',
      'Main Notifications',
      channelDescription: 'Notifications for work requests and updates',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _notificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
    );
  }
}
