import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';
import 'dart:math';

class MapRadiusPicker extends StatefulWidget {
  final LatLng? initialCenter;
  final double initialRadius;


  const MapRadiusPicker({
    super.key,
    this.initialCenter,
    this.initialRadius = 5000,
  });

  @override
  State<MapRadiusPicker> createState() => _MapRadiusPickerState();
}

class _MapRadiusPickerState extends State<MapRadiusPicker> {
  LatLng? _center;
  late double _radius;
  GoogleMapController? _mapController;
  Set<Circle> _circles = {};
  Set<Marker> _markers = {};
  bool _isLoading = false;

  String _t(String key) {
    final code = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    const en = <String, String>{
      'work_area': 'Work Area',
      'save': 'Save',
      'work_radius': 'Work Radius',
      'instruction': 'Tap the map or drag the marker within Israel',
      'stay_within_israel': 'Please stay within Israel bounds',
      'location_services_disabled': 'Location services are disabled.',
      'location_permissions_denied': 'Location permissions are denied.',
      'location_permissions_permanently_denied':
          'Location permissions are permanently denied.',
    };
    const he = <String, String>{
      'work_area': 'אזור עבודה',
      'save': 'שמור',
      'work_radius': 'רדיוס עבודה',
      'instruction': 'הקשו על המפה או גררו את הסמן בתוך ישראל',
      'stay_within_israel': 'נא להישאר בתוך גבולות ישראל',
      'location_services_disabled': 'שירותי המיקום כבויים.',
      'location_permissions_denied': 'הרשאות המיקום נדחו.',
      'location_permissions_permanently_denied': 'הרשאות המיקום נדחו לצמיתות.',
    };
    const ar = <String, String>{
      'work_area': 'منطقة العمل',
      'save': 'حفظ',
      'work_radius': 'نطاق العمل',
      'instruction': 'اضغط على الخريطة أو اسحب العلامة داخل إسرائيل',
      'stay_within_israel': 'يرجى البقاء داخل حدود إسرائيل',
      'location_services_disabled': 'خدمات الموقع غير مفعلة.',
      'location_permissions_denied': 'تم رفض أذونات الموقع.',
      'location_permissions_permanently_denied':
          'تم رفض أذونات الموقع بشكل دائم.',
    };
    const am = <String, String>{
      'work_area': 'የስራ አካባቢ',
      'save': 'አስቀምጥ',
      'work_radius': 'የስራ ራዲየስ',
      'instruction': 'በካርታው ላይ ይጫኑ ወይም ማርከሩን በእስራኤል ውስጥ ይጎትቱ',
      'stay_within_israel': 'እባክዎ በእስራኤል ድንበር ውስጥ ይቆዩ',
      'location_services_disabled': 'የአካባቢ አገልግሎቶች ተዘግተዋል።',
      'location_permissions_denied': 'የአካባቢ ፍቃድ ተከልክሏል።',
      'location_permissions_permanently_denied': 'የአካባቢ ፍቃድ ለዘላለም ተከልክሏል።',
    };
    const ru = <String, String>{
      'work_area': 'Рабочая зона',
      'save': 'Сохранить',
      'work_radius': 'Рабочий радиус',
      'instruction':
          'Нажмите на карту или перетащите маркер в пределах Израиля',
      'stay_within_israel': 'Пожалуйста, оставайтесь в пределах Израиля',
      'location_services_disabled': 'Службы геолокации отключены.',
      'location_permissions_denied': 'Доступ к геолокации запрещен.',
      'location_permissions_permanently_denied':
          'Доступ к геолокации навсегда запрещен.',
    };

    switch (code) {
      case 'he':
        return he[key] ?? en[key] ?? key;
      case 'ar':
        return ar[key] ?? en[key] ?? key;
      case 'am':
        return am[key] ?? en[key] ?? key;
      case 'ru':
        return ru[key] ?? en[key] ?? key;
      default:
        return en[key] ?? key;
    }
  }

  // Exact bounds for Israel to lock the map
  final LatLngBounds _israelBounds = LatLngBounds(
    southwest: const LatLng(29.4533, 34.2674),
    northeast: const LatLng(33.3328, 35.8955),
  );

  @override
  void initState() {
    super.initState();
    _radius = widget.initialRadius;
    _center = widget.initialCenter;

    // If no initial center or initial center is outside Israel, default to center of Israel (approx Tel Aviv area)
    if (_center == null || !_isWithinIsrael(_center!)) {
      _center = const LatLng(32.0853, 34.7818);
    }

    _updateMapElements();
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
        });
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw _t('location_services_disabled');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw _t('location_permissions_denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw _t('location_permissions_permanently_denied');
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      LatLng newCenter = LatLng(position.latitude, position.longitude);

      // Only update if the user is actually in Israel
      if (_isWithinIsrael(newCenter)) {
        if (mounted) {
          setState(() {
            _center = newCenter;
            _isLoading = false;
            _updateMapElements();
          });
          _moveCameraToCenter();
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  bool _isWithinIsrael(LatLng position) {
    return position.latitude >= _israelBounds.southwest.latitude &&
        position.latitude <= _israelBounds.northeast.latitude &&
        position.longitude >= _israelBounds.southwest.longitude &&
        position.longitude <= _israelBounds.northeast.longitude;
  }

  void _moveCameraToCenter() {
    if (_mapController != null && _center != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(_center!, _getZoomLevel(_radius)),
      );
    }
  }

  double _getZoomLevel(double radius) {
    // Adjusted zoom logic to keep things visible within Israel
    double scale = radius / 500;
    return max(6.0, min(21.0, (16 - log(scale) / log(2))));
  }

  void _updateMapElements() {
    if (_center == null) return;

    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('center'),
          position: _center!,
          draggable: true,
          onDragEnd: (newPosition) {
            if (_isWithinIsrael(newPosition)) {
              _center = newPosition;
            } else {
              // If dragged out, snap back to a valid position near the edge or keep old center
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(_t('stay_within_israel'))));
            }
            _updateMapElements();
          },
        ),
      };

      _circles = {
        Circle(
          circleId: const CircleId('radius'),
          center: _center!,
          radius: _radius,
          fillColor: const Color(0xFF1976D2).withOpacity(0.2),
          strokeColor: const Color(0xFF1976D2),
          strokeWidth: 2,
        ),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _t('work_area'),
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          if (_center != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: TextButton(
                onPressed: () {
                  Navigator.pop(context, {
                    'center': _center,
                    'radius': _radius,
                  });
                },
                child: Text(
                  _t('save'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF1976D2),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          if (_center != null)
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _center!,
                zoom: _getZoomLevel(_radius),
              ),
              // Lock the map to Israel bounds
              cameraTargetBounds: CameraTargetBounds(_israelBounds),
              // Prevent zooming out too far to keep the focus on Israel
              minMaxZoomPreference: const MinMaxZoomPreference(7.0, 18.0),
              onMapCreated: (controller) {
                _mapController = controller;
                _moveCameraToCenter();
              },
              onTap: (latLng) {
                if (_isWithinIsrael(latLng)) {
                  setState(() {
                    _center = latLng;
                    _updateMapElements();
                    _moveCameraToCenter();
                  });
                }
              },
              circles: _circles,
              markers: _markers,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: true,
            ),

          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF1976D2)),
            ),

          Positioned(
            top: 16,
            right: 16,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'my_location',
                  onPressed: _determinePosition,
                  backgroundColor: Colors.white,
                  child: const Icon(
                    Icons.my_location,
                    color: Color(0xFF1976D2),
                  ),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoom_in',
                  onPressed: () =>
                      _mapController?.animateCamera(CameraUpdate.zoomIn()),
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.add, color: Color(0xFF1976D2)),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoom_out',
                  onPressed: () =>
                      _mapController?.animateCamera(CameraUpdate.zoomOut()),
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.remove, color: Color(0xFF1976D2)),
                ),
              ],
            ),
          ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 20,
                    offset: Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _t('work_radius'),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1976D2).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${(_radius / 1000).toStringAsFixed(1)} km',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1976D2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFF1976D2),
                      inactiveTrackColor: const Color(
                        0xFF1976D2,
                      ).withOpacity(0.2),
                      thumbColor: const Color(0xFF1976D2),
                      overlayColor: const Color(0xFF1976D2).withOpacity(0.2),
                    ),
                    child: Slider(
                      value: _radius,
                      min: 1000,
                      max:
                          200000, // Reduced to 200km as it covers most of Israel's width/height effectively
                      divisions: 199,
                      onChanged: (value) {
                        setState(() {
                          _radius = value;
                          _updateMapElements();
                        });
                      },
                      onChangeEnd: (value) {
                        _moveCameraToCenter();
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _t('instruction'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
