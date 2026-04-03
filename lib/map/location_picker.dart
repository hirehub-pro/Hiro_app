import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

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
        title: const Text(
          'Pick Location',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
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
                child: const Text(
                  'Confirm',
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
                    const SnackBar(
                      content: Text("Please select a location within Israel"),
                    ),
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
                        const SnackBar(
                          content: Text("Please stay within Israel bounds"),
                        ),
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
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF1976D2), size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tap the map or drag the marker within Israel to select your location.',
                      style: TextStyle(
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
