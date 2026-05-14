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
    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings['permission_required_title']!),
        content: Text(
          strings['permission_allow_message']!.replaceFirst(
            '{permission}',
            permissionName,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings['permission_cancel_button']!),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings['permission_settings_button']!),
          ),
        ],
      ),
    );
    if (shouldOpenSettings == true) {
      await openAppSettings();
    }
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
          'permission_required_title': 'נדרשת הרשאה',
          'permission_allow_message':
              'אנא אפשר את {permission} בהגדרות כדי להמשיך.',
          'permission_cancel_button': 'ביטול',
          'permission_settings_button': 'פתח הגדרות',
        };
      case 'ar':
        return {
          'camera_permission_name': 'إذن الكاميرا',
          'microphone_permission_name': 'إذن الميكروفون',
          'location_permission_name': 'إذن الموقع',
          'permission_required_title': 'الإذن مطلوب',
          'permission_allow_message':
              'يرجى السماح بـ {permission} من الإعدادات للمتابعة.',
          'permission_cancel_button': 'إلغاء',
          'permission_settings_button': 'فتح الإعدادات',
        };
      case 'ru':
        return {
          'camera_permission_name': 'разрешение на камеру',
          'microphone_permission_name': 'разрешение на микрофон',
          'location_permission_name': 'разрешение на геолокацию',
          'permission_required_title': 'Требуется разрешение',
          'permission_allow_message':
              'Пожалуйста, разрешите {permission} в настройках, чтобы продолжить.',
          'permission_cancel_button': 'Отмена',
          'permission_settings_button': 'Открыть настройки',
        };
      case 'am':
        return {
          'camera_permission_name': 'የካሜራ ፍቃድ',
          'microphone_permission_name': 'የማይክሮፎን ፍቃድ',
          'location_permission_name': 'የአካባቢ ፍቃድ',
          'permission_required_title': 'ፍቃድ ያስፈልጋል',
          'permission_allow_message':
              'ለመቀጠል እባክዎ {permission} በቅንብሮች ውስጥ ይፍቀዱ።',
          'permission_cancel_button': 'ሰርዝ',
          'permission_settings_button': 'ቅንብሮችን ክፈት',
        };
      default:
        return {
          'camera_permission_name': 'camera permission',
          'microphone_permission_name': 'microphone permission',
          'location_permission_name': 'location permission',
          'permission_required_title': 'Permission required',
          'permission_allow_message':
              'Please allow {permission} in Settings to continue.',
          'permission_cancel_button': 'Cancel',
          'permission_settings_button': 'Open Settings',
        };
    }
  }
}
