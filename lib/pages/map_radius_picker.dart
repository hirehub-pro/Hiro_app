import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
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
  String? _errorMessage;

  // Approximate bounds for Israel
  final LatLngBounds _israelBounds = LatLngBounds(
    southwest: const LatLng(29.4533, 34.2674),
    northeast: const LatLng(33.3328, 35.8955),
  );

  @override
  void initState() {
    super.initState();
    _radius = widget.initialRadius;
    _center = widget.initialCenter;
    if (_center != null) {
      _updateMapElements();
    } else {
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
        throw 'Location services are disabled. Please enable them in settings.';
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

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      
      LatLng newCenter = LatLng(position.latitude, position.longitude);
      
      // Ensure the determined position is within Israel bounds
      if (!_isWithinIsrael(newCenter)) {
        newCenter = const LatLng(32.0853, 34.7818); // Default to Tel Aviv
      }

      if (mounted) {
        setState(() {
          _center = newCenter;
          _isLoading = false;
          _updateMapElements();
        });
        _moveCameraToCenter();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
          if (_center == null) {
            // Fallback to Tel Aviv
            _center = const LatLng(32.0853, 34.7818);
            _updateMapElements();
          }
        });
        _moveCameraToCenter();
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
    double scale = radius / 500;
    return max(0, min(21, (16 - log(scale) / log(2))));
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
        title: const Text('Work Area', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
                child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1976D2))),
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
              cameraTargetBounds: CameraTargetBounds(_israelBounds),
              minMaxZoomPreference: const MinMaxZoomPreference(5.0, null),
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
            Container(
              color: Colors.black.withOpacity(0.1),
              child: const Center(child: CircularProgressIndicator(color: Color(0xFF1976D2))),
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
                  child: const Icon(Icons.my_location, color: Color(0xFF1976D2)),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoom_in',
                  onPressed: () => _mapController?.animateCamera(CameraUpdate.zoomIn()),
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.add, color: Color(0xFF1976D2)),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoom_out',
                  onPressed: () => _mapController?.animateCamera(CameraUpdate.zoomOut()),
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
                  BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -5)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Work Radius',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1976D2).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${(_radius / 1000).toStringAsFixed(1)} km',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1976D2)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFF1976D2),
                      inactiveTrackColor: Colors.blue.withOpacity(0.1),
                      thumbColor: const Color(0xFF1976D2),
                      overlayColor: const Color(0xFF1976D2).withOpacity(0.2),
                    ),
                    child: Slider(
                      value: _radius,
                      min: 1000,
                      max: 500000, // Increased to 500km
                      divisions: 499, // Finer divisions for the larger range
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
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info_outline, size: 14, color: Colors.grey),
                      SizedBox(width: 4),
                      Text(
                        'Tap the map or drag the marker to set your center',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          if (_errorMessage != null && _center == null)
            Positioned.fill(
              child: Container(
                color: Colors.white,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_off_outlined, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text(
                          'Location Access Error',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _determinePosition,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1976D2),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
