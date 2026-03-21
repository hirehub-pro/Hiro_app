import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class LocationPicker extends StatefulWidget {
  final LatLng? initialCenter;

  const LocationPicker({
    super.key,
    this.initialCenter,
  });

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  LatLng? _selectedLocation;
  GoogleMapController? _mapController;
  bool _isLoading = false;
  String? _errorMessage;

  final LatLngBounds _israelBounds = LatLngBounds(
    southwest: const LatLng(29.4533, 34.2674),
    northeast: const LatLng(33.3328, 35.8955),
  );

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialCenter;
    if (_selectedLocation == null) {
      _determinePosition();
    }
  }

  Future<void> _determinePosition() async {
    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'Location services are disabled.';
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'Location permissions are denied.';
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        throw 'Location permissions are permanently denied.';
      } 

      Position position = await Geolocator.getCurrentPosition();
      LatLng newPos = LatLng(position.latitude, position.longitude);
      
      if (!_isWithinIsrael(newPos)) {
        newPos = const LatLng(32.0853, 34.7818); // Tel Aviv
      }

      if (mounted) {
        setState(() {
          _selectedLocation = newPos;
          _isLoading = false;
        });
        _moveCameraTo(newPos);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
          if (_selectedLocation == null) {
            _selectedLocation = const LatLng(32.0853, 34.7818);
          }
        });
        _moveCameraTo(_selectedLocation!);
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
        title: const Text('Pick Location', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          if (_selectedLocation != null)
            TextButton(
              onPressed: () => Navigator.pop(context, _selectedLocation),
              child: const Text('Confirm', style: TextStyle(color: Color(0xFF1976D2), fontWeight: FontWeight.bold, fontSize: 16)),
            ),
        ],
      ),
      body: Stack(
        children: [
          if (_selectedLocation != null)
            GoogleMap(
              initialCameraPosition: CameraPosition(target: _selectedLocation!, zoom: 15),
              cameraTargetBounds: CameraTargetBounds(_israelBounds),
              onMapCreated: (controller) => _mapController = controller,
              onTap: (pos) {
                if (_isWithinIsrael(pos)) {
                  setState(() => _selectedLocation = pos);
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
                    }
                  },
                ),
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
            ),
          
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),

          Positioned(
            top: 16,
            right: 16,
            child: FloatingActionButton.small(
              onPressed: _determinePosition,
              backgroundColor: Colors.white,
              child: const Icon(Icons.my_location, color: Color(0xFF1976D2)),
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
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tap the map or drag the marker to select your home location.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
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
