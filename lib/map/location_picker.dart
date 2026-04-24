import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/services/language_provider.dart';

class LocationPicker extends StatefulWidget {
  final LatLng? initialCenter;

  const LocationPicker({super.key, this.initialCenter});

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  LatLng? _selectedLocation;
  GoogleMapController? _mapController;
  bool _isLoading = false;
  String _t(String key) {
    final code = Provider.of<LanguageProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    const en = <String, String>{
      'pick_location': 'Pick Location',
      'confirm': 'Confirm',
      'select_within_israel': 'Please select a location within Israel',
      'stay_within_israel': 'Please stay within Israel bounds',
      'instruction':
          'Tap the map or drag the marker within Israel to select your location.',
      'location_services_disabled': 'Location services are disabled.',
      'location_permissions_denied': 'Location permissions are denied.',
      'location_permissions_permanently_denied':
          'Location permissions are permanently denied.',
    };
    const he = <String, String>{
      'pick_location': 'בחירת מיקום',
      'confirm': 'אישור',
      'select_within_israel': 'נא לבחור מיקום בתוך גבולות ישראל',
      'stay_within_israel': 'נא להישאר בתוך גבולות ישראל',
      'instruction': 'הקשו על המפה או גררו את הסמן בתוך ישראל כדי לבחור מיקום.',
      'location_services_disabled': 'שירותי המיקום כבויים.',
      'location_permissions_denied': 'הרשאות המיקום נדחו.',
      'location_permissions_permanently_denied': 'הרשאות המיקום נדחו לצמיתות.',
    };
    const ar = <String, String>{
      'pick_location': 'اختيار الموقع',
      'confirm': 'تأكيد',
      'select_within_israel': 'يرجى اختيار موقع داخل حدود إسرائيل',
      'stay_within_israel': 'يرجى البقاء داخل حدود إسرائيل',
      'instruction':
          'اضغط على الخريطة أو اسحب العلامة داخل إسرائيل لاختيار موقعك.',
      'location_services_disabled': 'خدمات الموقع غير مفعلة.',
      'location_permissions_denied': 'تم رفض أذونات الموقع.',
      'location_permissions_permanently_denied':
          'تم رفض أذونات الموقع بشكل دائم.',
    };
    const am = <String, String>{
      'pick_location': 'ቦታ ምረጥ',
      'confirm': 'አረጋግጥ',
      'select_within_israel': 'እባክዎ በእስራኤል ድንበር ውስጥ ቦታ ይምረጡ',
      'stay_within_israel': 'እባክዎ በእስራኤል ድንበር ውስጥ ይቆዩ',
      'instruction': 'ቦታዎን ለመምረጥ በእስራኤል ውስጥ በካርታው ላይ ይጫኑ ወይም ማርከሩን ይጎትቱ።',
      'location_services_disabled': 'የአካባቢ አገልግሎቶች ተዘግተዋል።',
      'location_permissions_denied': 'የአካባቢ ፍቃድ ተከልክሏል።',
      'location_permissions_permanently_denied': 'የአካባቢ ፍቃድ ለዘላለም ተከልክሏል።',
    };
    const ru = <String, String>{
      'pick_location': 'Выбор местоположения',
      'confirm': 'Подтвердить',
      'select_within_israel':
          'Пожалуйста, выберите местоположение в пределах Израиля',
      'stay_within_israel': 'Пожалуйста, оставайтесь в пределах Израиля',
      'instruction':
          'Нажмите на карту или перетащите маркер в пределах Израиля, чтобы выбрать местоположение.',
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
    _selectedLocation = widget.initialCenter;

    // Default to Tel Aviv if no location provided or if it's outside Israel
    if (_selectedLocation == null || !_isWithinIsrael(_selectedLocation!)) {
      _selectedLocation = const LatLng(32.0853, 34.7818);
    }

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

      Position position = await Geolocator.getCurrentPosition();
      LatLng newPos = LatLng(position.latitude, position.longitude);

      // Only snap to user location if they are in Israel
      if (_isWithinIsrael(newPos)) {
        if (mounted) {
          setState(() {
            _selectedLocation = newPos;
            _isLoading = false;
          });
          _moveCameraTo(newPos);
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

  void _moveCameraTo(LatLng pos) {
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(pos, 15));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _t('pick_location'),
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          if (_selectedLocation != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: TextButton(
                onPressed: () => Navigator.pop(context, _selectedLocation),
                child: Text(
                  _t('confirm'),
                  style: TextStyle(
                    color: Color(0xFF1976D2),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          if (_selectedLocation != null)
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _selectedLocation!,
                zoom: 15,
              ),
              // Lock the map to Israel bounds
              cameraTargetBounds: CameraTargetBounds(_israelBounds),
              // Prevent zooming out too far to keep the focus on Israel
              minMaxZoomPreference: const MinMaxZoomPreference(7.0, 18.0),
              onMapCreated: (controller) => _mapController = controller,
              onTap: (pos) {
                if (_isWithinIsrael(pos)) {
                  setState(() => _selectedLocation = pos);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(_t('select_within_israel'))),
                  );
                }
              },
              markers: {
                Marker(
                  markerId: const MarkerId('selected'),
                  position: _selectedLocation!,
                  draggable: true,
                  onDragEnd: (pos) {
                    if (_isWithinIsrael(pos)) {
                      setState(() => _selectedLocation = pos);
                    } else {
                      // Stay at previous location if dragged out
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(_t('stay_within_israel'))),
                      );
                    }
                  },
                ),
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: true,
              mapToolbarEnabled: false,
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
            bottom: 30,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Color(0xFF1976D2),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _t('instruction'),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
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
