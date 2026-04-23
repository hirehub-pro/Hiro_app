import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: "AIzaSyBL55dWOh2eIBDooZ0EwzXegyAMEiWMuNE",
    authDomain: "hire-hub-fe6c4.firebaseapp.com",
    databaseURL: "https://hire-hub-fe6c4-default-rtdb.firebaseio.com",
    projectId: "hire-hub-fe6c4",
    storageBucket: "hire-hub-fe6c4.firebasestorage.app",
    messagingSenderId: "29257648718",
    appId: "1:29257648718:web:40cec5d689067d9cb8111f",
    measurementId: "G-66P0301100",
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB1CWooXT-Gxc4q1q4XmYGSE4Rixyp1EXk',
    appId: '1:29257648718:android:e89f9a18d21f507db8111f',
    messagingSenderId: '29257648718',
    projectId: 'hire-hub-fe6c4',
    storageBucket: 'hire-hub-fe6c4.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDh5ZzwkafsDkup9k2sKMkykr5Ukra9xQA',
    appId: '1:29257648718:ios:6ef27488d62e3fb9b8111f',
    messagingSenderId: '29257648718',
    projectId: 'hire-hub-fe6c4',
    storageBucket: 'hire-hub-fe6c4.firebasestorage.app',
    iosBundleId: 'com.hiro.hiroapp',
  );
}
