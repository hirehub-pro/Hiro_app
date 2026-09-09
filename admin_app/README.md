# Hiro Admin for Android

This is the private Android administration client for Hiro. It uses the same
Firebase project (`hire-hub-fe6c4`) as the customer and worker application, but
is registered as a separate Firebase Android app:

- Display name: `Hiro Admin`
- Android application ID: `com.hiro.admin`
- Firebase app ID: `1:29257648718:android:029a75d6eca55517b8111f`

## Authentication

The sign-in screen accepts Firebase email/password credentials. Access is
granted when the ID token has the server-issued `admin: true` custom claim.
During migration, the app also accepts an existing protected
`users/{uid}.role == "admin"` value so the current administrator is not locked
out. Remove that fallback from `lib/main.dart` and `firestore.rules` after the
custom claim has been verified on the administrator account.

## App Check

Release builds activate the Play Integrity provider. Register this Android app
under Firebase Console > App Check before enabling enforcement. Local debug
builds activate App Check only when run with:

```sh
flutter run --dart-define=ENABLE_FIREBASE_APP_CHECK=true
```

Register the printed debug token in the Firebase Console when testing App
Check locally.

## Build

```sh
flutter pub get
flutter build apk --debug
```

The project intentionally contains only an Android platform directory.

The debug APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.
Before building a release APK, create a private upload keystore and configure
`android/key.properties`; release builds intentionally fail instead of signing
with a debug key when that file is missing.
