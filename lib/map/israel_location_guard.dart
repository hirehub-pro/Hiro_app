import 'dart:math' as math;

import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class IsraelLocationGuard {
  static const LatLng fallbackCenter = LatLng(32.0853, 34.7818);
  static const double borderCityToleranceMeters = 3000;

  static final LatLngBounds bounds = LatLngBounds(
    southwest: const LatLng(29.45, 34.20),
    northeast: const LatLng(33.35, 35.90),
  );

  // Rough Israel border polygon used for coordinate validation.
  // Replace this list with exact official border coordinates when available.
  static const List<LatLng> borderPolygon = [
    LatLng(33.3356, 35.6389),
    LatLng(33.2700, 35.7600),
    LatLng(33.0900, 35.8200),
    LatLng(32.7600, 35.6900),
    LatLng(32.5150, 35.5650),
    LatLng(32.2000, 35.5450),
    LatLng(31.7650, 35.5650),
    LatLng(31.3500, 35.4750),
    LatLng(30.9000, 35.3900),
    LatLng(30.4300, 35.1750),
    LatLng(29.8500, 35.0700),
    LatLng(29.5500, 34.9650),
    LatLng(29.4900, 34.9050),
    LatLng(29.5500, 34.8700),
    LatLng(29.7600, 34.8650),
    LatLng(30.0500, 34.7900),
    LatLng(30.3600, 34.6900),
    LatLng(30.6000, 34.5500),
    LatLng(30.7800, 34.4550),
    LatLng(30.9300, 34.4000),
    LatLng(31.2300, 34.2700),
    LatLng(31.3200, 34.2450),
    LatLng(31.5600, 34.4450),
    LatLng(31.7400, 34.5650),
    LatLng(31.9000, 34.6700),
    LatLng(32.0850, 34.7550),
    LatLng(32.3200, 34.8450),
    LatLng(32.5900, 34.9250),
    LatLng(32.8300, 35.0000),
    LatLng(33.0800, 35.1050),
    LatLng(33.2050, 35.3000),
  ];

  static bool isInsideIsrael(LatLng position) {
    if (!_isInsideBounds(position)) return false;
    if (_isInsidePolygon(position)) return true;
    return distanceToBorderMeters(position) <= borderCityToleranceMeters;
  }

  static Future<bool> isValidIsraelLocation(LatLng position) async {
    if (!_isInsideBounds(position)) return false;

    final insidePolygon = _isInsidePolygon(position);
    final nearBorder =
        distanceToBorderMeters(position) <= borderCityToleranceMeters;
    if (!insidePolygon && !nearBorder) return false;

    final countryCode = await _reverseGeocodedCountryCode(position);
    if (countryCode == null || countryCode.isEmpty) {
      return insidePolygon;
    }

    return countryCode == 'IL';
  }

  static LatLng clampToBounds(LatLng position) {
    return LatLng(
      position.latitude
          .clamp(bounds.southwest.latitude, bounds.northeast.latitude)
          .toDouble(),
      position.longitude
          .clamp(bounds.southwest.longitude, bounds.northeast.longitude)
          .toDouble(),
    );
  }

  static bool _isInsideBounds(LatLng position) {
    return position.latitude >= bounds.southwest.latitude &&
        position.latitude <= bounds.northeast.latitude &&
        position.longitude >= bounds.southwest.longitude &&
        position.longitude <= bounds.northeast.longitude;
  }

  static bool _isInsidePolygon(LatLng position) {
    var inside = false;
    for (
      var i = 0, j = borderPolygon.length - 1;
      i < borderPolygon.length;
      j = i++
    ) {
      final xi = borderPolygon[i].longitude;
      final yi = borderPolygon[i].latitude;
      final xj = borderPolygon[j].longitude;
      final yj = borderPolygon[j].latitude;
      final x = position.longitude;
      final y = position.latitude;

      final intersects =
          ((yi > y) != (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  static Future<String?> _reverseGeocodedCountryCode(LatLng position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isEmpty) return null;
      return placemarks.first.isoCountryCode?.toUpperCase();
    } catch (_) {
      return null;
    }
  }

  static double distanceToBorderMeters(LatLng position) {
    var shortestDistance = double.infinity;
    for (var i = 0; i < borderPolygon.length; i++) {
      final start = borderPolygon[i];
      final end = borderPolygon[(i + 1) % borderPolygon.length];
      final distance = _distanceToSegmentMeters(position, start, end);
      if (distance < shortestDistance) shortestDistance = distance;
    }
    return shortestDistance;
  }

  static double _distanceToSegmentMeters(
    LatLng point,
    LatLng start,
    LatLng end,
  ) {
    final latitudeScale = 111320.0;
    final longitudeScale =
        111320.0 * math.cos(point.latitude * 0.017453292519943295).abs();
    final px = point.longitude * longitudeScale;
    final py = point.latitude * latitudeScale;
    final sx = start.longitude * longitudeScale;
    final sy = start.latitude * latitudeScale;
    final ex = end.longitude * longitudeScale;
    final ey = end.latitude * latitudeScale;
    final dx = ex - sx;
    final dy = ey - sy;

    if (dx == 0 && dy == 0) {
      return math.sqrt((px - sx) * (px - sx) + (py - sy) * (py - sy));
    }

    final t = (((px - sx) * dx) + ((py - sy) * dy)) / ((dx * dx) + (dy * dy));
    final clampedT = t.clamp(0.0, 1.0);
    final closestX = sx + clampedT * dx;
    final closestY = sy + clampedT * dy;
    return math.sqrt(
      (px - closestX) * (px - closestX) + (py - closestY) * (py - closestY),
    );
  }
}
