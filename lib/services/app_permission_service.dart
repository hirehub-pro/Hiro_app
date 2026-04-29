import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';

enum AppPermissionKind { camera, microphone, location }

class AppPermissionService {
  static Future<bool> ensureGranted(
    BuildContext context, {
    required Permission permission,
    required AppPermissionKind kind,
  }) async {
    var status = await permission.status;
    if (_isGranted(status)) return true;

    status = await permission.request();
    if (_isGranted(status)) return true;

    if (!context.mounted) return false;

    final strings = _stringsFor(context);
    final permissionName = strings[_permissionNameKey(kind)]!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          strings['permission_allow_message']!.replaceFirst(
            '{permission}',
            permissionName,
          ),
        ),
      ),
    );
    await openAppSettings();
    return false;
  }

  static bool _isGranted(PermissionStatus status) {
    return status.isGranted || status.isLimited || status.isProvisional;
  }

  static String _permissionNameKey(AppPermissionKind kind) {
    switch (kind) {
      case AppPermissionKind.camera:
        return 'camera_permission_name';
      case AppPermissionKind.microphone:
        return 'microphone_permission_name';
      case AppPermissionKind.location:
        return 'location_permission_name';
    }
  }

  static Map<String, String> _stringsFor(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;

    switch (locale) {
      case 'he':
        return {
          'camera_permission_name': 'הרשאת המצלמה',
          'microphone_permission_name': 'הרשאת המיקרופון',
          'location_permission_name': 'הרשאת המיקום',
          'permission_allow_message':
              'אנא אפשר את {permission} בהגדרות כדי להמשיך.',
        };
      case 'ar':
        return {
          'camera_permission_name': 'إذن الكاميرا',
          'microphone_permission_name': 'إذن الميكروفون',
          'location_permission_name': 'إذن الموقع',
          'permission_allow_message':
              'يرجى السماح بـ {permission} من الإعدادات للمتابعة.',
        };
      case 'ru':
        return {
          'camera_permission_name': 'разрешение на камеру',
          'microphone_permission_name': 'разрешение на микрофон',
          'location_permission_name': 'разрешение на геолокацию',
          'permission_allow_message':
              'Пожалуйста, разрешите {permission} в настройках, чтобы продолжить.',
        };
      case 'am':
        return {
          'camera_permission_name': 'የካሜራ ፍቃድ',
          'microphone_permission_name': 'የማይክሮፎን ፍቃድ',
          'location_permission_name': 'የአካባቢ ፍቃድ',
          'permission_allow_message':
              'ለመቀጠል እባክዎ {permission} በቅንብሮች ውስጥ ይፍቀዱ።',
        };
      default:
        return {
          'camera_permission_name': 'camera permission',
          'microphone_permission_name': 'microphone permission',
          'location_permission_name': 'location permission',
          'permission_allow_message':
              'Please allow {permission} in Settings to continue.',
        };
    }
  }
}
