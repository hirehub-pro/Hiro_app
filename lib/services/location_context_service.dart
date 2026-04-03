import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class AppLocation {
  static const String currentId = '__current__';

  final String id;
  final String label;
  final double latitude;
  final double longitude;
  final bool isCurrent;

  const AppLocation({
    required this.id,
    required this.label,
    required this.latitude,
    required this.longitude,
    this.isCurrent = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'lat': latitude,
      'lng': longitude,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static AppLocation fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return AppLocation(
      id: doc.id,
      label: (data['label'] ?? 'Location').toString(),
      latitude: (data['lat'] as num).toDouble(),
      longitude: (data['lng'] as num).toDouble(),
    );
  }
}

class LocationContextService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final ValueNotifier<int> locationPermissionGrantedTick =
      ValueNotifier<int>(0);

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static DocumentReference<Map<String, dynamic>> _userDoc(String uid) {
    return _firestore.collection('users').doc(uid);
  }

  static CollectionReference<Map<String, dynamic>> _savedLocations(String uid) {
    return _userDoc(uid).collection('saved_locations');
  }

  static Future<String> getActiveLocationId() async {
    final uid = _uid;
    if (uid == null) return AppLocation.currentId;

    final doc = await _userDoc(uid).get();
    final data = doc.data();
    return (data?['activeLocationId'] as String?) ?? AppLocation.currentId;
  }

  static Future<void> setActiveLocationId(String id) async {
    final uid = _uid;
    if (uid == null) return;

    await _userDoc(uid).set({
      'activeLocationId': id,
      'activeLocationUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<List<AppLocation>> getSavedLocations() async {
    final uid = _uid;
    if (uid == null) return [];

    final snap = await _savedLocations(
      uid,
    ).orderBy('updatedAt', descending: true).get();
    return snap.docs
        .where((doc) {
          final data = doc.data();
          return data['lat'] is num && data['lng'] is num;
        })
        .map(AppLocation.fromDoc)
        .toList();
  }

  static Future<AppLocation?> getLocationById(String id) async {
    final uid = _uid;
    if (uid == null) return null;

    final doc = await _savedLocations(uid).doc(id).get();
    if (!doc.exists) return null;

    final data = doc.data();
    if (data == null || data['lat'] is! num || data['lng'] is! num) return null;
    return AppLocation.fromDoc(doc);
  }

  static Future<void> saveLocation({
    String? id,
    required String label,
    required double latitude,
    required double longitude,
  }) async {
    final uid = _uid;
    if (uid == null) return;

    final locations = _savedLocations(uid);
    final docRef = id == null ? locations.doc() : locations.doc(id);
    await docRef.set(
      AppLocation(
        id: docRef.id,
        label: label.trim(),
        latitude: latitude,
        longitude: longitude,
      ).toMap(),
      SetOptions(merge: true),
    );
  }

  static Future<void> deleteLocation(String id) async {
    final uid = _uid;
    if (uid == null) return;

    await _savedLocations(uid).doc(id).delete();

    final activeId = await getActiveLocationId();
    if (activeId == id) {
      await setActiveLocationId(AppLocation.currentId);
    }
  }

  static Future<AppLocation?> getCurrentDeviceLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      final previousPermission = permission;
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }

      if (permission == LocationPermission.deniedForever) return null;

      if ((previousPermission == LocationPermission.denied ||
              previousPermission == LocationPermission.deniedForever) &&
          permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever) {
        locationPermissionGrantedTick.value++;
      }

      final pos = await Geolocator.getCurrentPosition();
      return AppLocation(
        id: AppLocation.currentId,
        label: 'Current Location',
        latitude: pos.latitude,
        longitude: pos.longitude,
        isCurrent: true,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<AppLocation?> getActiveLocation() async {
    final activeId = await getActiveLocationId();

    if (activeId == AppLocation.currentId) {
      return getCurrentDeviceLocation();
    }

    final saved = await getLocationById(activeId);
    if (saved != null) return saved;

    return getCurrentDeviceLocation();
  }
}
