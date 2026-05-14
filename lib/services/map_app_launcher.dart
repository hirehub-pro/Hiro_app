import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class MapAppLauncher {
  static Future<void> openLocation({
    required BuildContext context,
    required double latitude,
    required double longitude,
    required String languageCode,
  }) async {
    final strings = _localizedStrings(languageCode);
    final options = await _availableOptions(
      latitude: latitude,
      longitude: longitude,
      strings: strings,
    );

    if (!context.mounted) return;

    if (options.isEmpty) {
      await _launchFallback(latitude, longitude);
      return;
    }

    if (options.length == 1) {
      await options.first.launch();
      return;
    }

    final selected = await showModalBottomSheet<_MapOption>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.title,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                strings.subtitle,
                style: Theme.of(sheetContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              for (final option in options)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(option.icon),
                  title: Text(option.label),
                  onTap: () => Navigator.of(sheetContext).pop(option),
                ),
            ],
          ),
        ),
      ),
    );

    if (selected != null) {
      await selected.launch();
    }
  }

  static Future<List<_MapOption>> _availableOptions({
    required double latitude,
    required double longitude,
    required _MapStrings strings,
  }) async {
    final options = <_MapOption>[];

    if (kIsWeb) {
      options.add(
        _MapOption(
          label: strings.googleMaps,
          icon: Icons.map_outlined,
          launch: () => _launchUrl(_googleWebUri(latitude, longitude)),
        ),
      );
      return options;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final appleUri = _appleMapsUri(latitude, longitude);
      if (await canLaunchUrl(appleUri)) {
        options.add(
          _MapOption(
            label: strings.appleMaps,
            icon: Icons.map_outlined,
            launch: () => _launchUrl(appleUri),
          ),
        );
      }

      final googleIosUri = _googleIosUri(latitude, longitude);
      if (await canLaunchUrl(googleIosUri)) {
        options.add(
          _MapOption(
            label: strings.googleMaps,
            icon: Icons.location_on_outlined,
            launch: () => _launchUrl(googleIosUri),
          ),
        );
      }

      final wazeUri = _wazeUri(latitude, longitude);
      if (await canLaunchUrl(wazeUri)) {
        options.add(
          _MapOption(
            label: strings.waze,
            icon: Icons.alt_route_outlined,
            launch: () => _launchUrl(wazeUri),
          ),
        );
      }
      return options;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final googleAndroidUri = _googleAndroidUri(latitude, longitude);
      if (await canLaunchUrl(googleAndroidUri)) {
        options.add(
          _MapOption(
            label: strings.googleMaps,
            icon: Icons.location_on_outlined,
            launch: () => _launchUrl(googleAndroidUri),
          ),
        );
      }

      final wazeUri = _wazeUri(latitude, longitude);
      if (await canLaunchUrl(wazeUri)) {
        options.add(
          _MapOption(
            label: strings.waze,
            icon: Icons.alt_route_outlined,
            launch: () => _launchUrl(wazeUri),
          ),
        );
      }
      return options;
    }

    options.add(
      _MapOption(
        label: strings.googleMaps,
        icon: Icons.map_outlined,
        launch: () => _launchUrl(_googleWebUri(latitude, longitude)),
      ),
    );
    return options;
  }

  static Future<void> _launchFallback(double latitude, double longitude) {
    return _launchUrl(_googleWebUri(latitude, longitude));
  }

  static Future<void> _launchUrl(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Uri _googleWebUri(double latitude, double longitude) {
    return Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );
  }

  static Uri _googleIosUri(double latitude, double longitude) {
    return Uri.parse('comgooglemaps://?q=$latitude,$longitude');
  }

  static Uri _googleAndroidUri(double latitude, double longitude) {
    return Uri.parse('google.navigation:q=$latitude,$longitude');
  }

  static Uri _appleMapsUri(double latitude, double longitude) {
    return Uri.parse('https://maps.apple.com/?ll=$latitude,$longitude');
  }

  static Uri _wazeUri(double latitude, double longitude) {
    return Uri.parse('waze://?ll=$latitude,$longitude&navigate=yes');
  }

  static _MapStrings _localizedStrings(String code) {
    switch (code) {
      case 'he':
        return const _MapStrings(
          title: 'בחרו אפליקציית מפה',
          subtitle: 'באיזו מפה לפתוח את המיקום?',
          appleMaps: 'Apple Maps',
          googleMaps: 'Google Maps',
          waze: 'Waze',
        );
      case 'ar':
        return const _MapStrings(
          title: 'اختر تطبيق الخريطة',
          subtitle: 'أي خريطة تريد فتح الموقع بها؟',
          appleMaps: 'Apple Maps',
          googleMaps: 'Google Maps',
          waze: 'Waze',
        );
      case 'am':
        return const _MapStrings(
          title: 'የካርታ መተግበሪያ ይምረጡ',
          subtitle: 'አካባቢውን በየትኛው ካርታ ማብራት ይፈልጋሉ?',
          appleMaps: 'Apple Maps',
          googleMaps: 'Google Maps',
          waze: 'Waze',
        );
      case 'ru':
        return const _MapStrings(
          title: 'Выберите приложение карты',
          subtitle: 'В какой карте открыть местоположение?',
          appleMaps: 'Apple Maps',
          googleMaps: 'Google Maps',
          waze: 'Waze',
        );
      default:
        return const _MapStrings(
          title: 'Choose a map app',
          subtitle: 'Which map would you like to use?',
          appleMaps: 'Apple Maps',
          googleMaps: 'Google Maps',
          waze: 'Waze',
        );
    }
  }
}

class _MapOption {
  const _MapOption({
    required this.label,
    required this.icon,
    required this.launch,
  });

  final String label;
  final IconData icon;
  final Future<void> Function() launch;
}

class _MapStrings {
  const _MapStrings({
    required this.title,
    required this.subtitle,
    required this.appleMaps,
    required this.googleMaps,
    required this.waze,
  });

  final String title;
  final String subtitle;
  final String appleMaps;
  final String googleMaps;
  final String waze;
}
