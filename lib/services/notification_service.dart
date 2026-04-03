import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static StreamSubscription? _notificationSubscription;
  static StreamSubscription? _broadcastSubscription;
  static StreamSubscription<String>? _tokenRefreshSubscription;
  static bool _isInitialized = false;
  static bool _isListening = false;
  static String? _activeUserId;

  static final StreamController<String?> selectNotificationStream =
      StreamController<String?>.broadcast();

  static Future<void> init() async {
    if (_isInitialized) return;

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    await _notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        selectNotificationStream.add(response.payload);
      },
    );

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        _showNotification(
          id: message.hashCode,
          title: message.notification!.title ?? '',
          body: message.notification!.body ?? '',
          payload: jsonEncode(message.data),
        );
      }
    });

    RemoteMessage? initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      selectNotificationStream.add(jsonEncode(initialMessage.data));
    }

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      selectNotificationStream.add(jsonEncode(message.data));
    });

    _isInitialized = true;
  }

  static Future<void> saveDeviceToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;

    try {
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        String? token = await _messaging.getToken();
        if (token != null) {
          final firestore = FirebaseFirestore.instance;
          final data = {
            'fcmToken': token,
            'lastTokenUpdate': FieldValue.serverTimestamp(),
            'platform': Platform.isAndroid ? 'android' : 'ios',
          };
          // Save token to the unified 'users' collection
          await firestore
              .collection('users')
              .doc(user.uid)
              .set(data, SetOptions(merge: true));
        }
      }
    } catch (e) {
      debugPrint("Error saving FCM token: $e");
    }
  }

  static void startListening() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      stopListening();
      return;
    }

    if (_isListening && _activeUserId == user.uid) return;

    _isListening = true;
    _activeUserId = user.uid;

    saveDeviceToken();
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((_) {
      saveDeviceToken();
    });
    _notificationSubscription?.cancel();
    _broadcastSubscription?.cancel();

    // 1. Personal Notifications
    bool isInitialLoad = true;

    // Listen to personal notifications in the unified 'users' collection
    _notificationSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
          if (isInitialLoad) {
            isInitialLoad = false;
            return;
          }
          if (snapshot.docs.isNotEmpty) {
            final data = snapshot.docs.first.data();
            _showNotification(
              id: snapshot.docs.first.id.hashCode,
              title: data['title'] ?? 'New Notification',
              body: data['body'] ?? '',
              payload: jsonEncode(data),
            );
          }
        });

    // 2. Global Broadcasts
    bool isInitialBroadcastLoad = true;
    _broadcastSubscription = FirebaseFirestore.instance
        .collection('system_announcements')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
          if (isInitialBroadcastLoad) {
            isInitialBroadcastLoad = false;
            return;
          }
          if (snapshot.docs.isNotEmpty) {
            final data = snapshot.docs.first.data();
            _showNotification(
              id: snapshot.docs.first.id.hashCode,
              title: data['title'] ?? 'System Broadcast',
              body: data['message'] ?? '',
              payload: jsonEncode({'type': 'broadcast', ...data}),
            );
          }
        });
  }

  static void stopListening() {
    _notificationSubscription?.cancel();
    _broadcastSubscription?.cancel();
    _tokenRefreshSubscription?.cancel();
    _notificationSubscription = null;
    _broadcastSubscription = null;
    _tokenRefreshSubscription = null;
    _isListening = false;
    _activeUserId = null;
  }

  static Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'main_channel',
          'Main Notifications',
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
      payload: payload,
    );
  }

  static Future<void> sendPushNotification({
    required String targetToken,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      debugPrint("FCM notification request for token: $targetToken");
      debugPrint("Title: $title, Body: $body");
    } catch (e) {
      debugPrint("Error sending push notification: $e");
    }
  }
}
