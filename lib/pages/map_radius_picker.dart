import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class MapRadiusPicker extends StatefulWidget {
  final LatLng? initialCenter;
  final double initialRadius; // in meters

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
  double _radius = 5000; // default 5km
  GoogleMapController? _mapController;
  Set<Circle> _circles = {};
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _center = widget.initialCenter;
    _radius = widget.initialRadius;
    if (_center != null) {
      _updateMapElements();
    } else {
      _determinePosition();
    }
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return;
    } 

    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _center = LatLng(position.latitude, position.longitude);
      _updateMapElements();
    });
    
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_center!, 12));
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
            setState(() {
              _center = newPosition;
              _updateMapElements();
            });
          },
        ),
      };

      _circles = {
        Circle(
          circleId: const CircleId('radius'),
          center: _center!,
          radius: _radius,
          fillColor: Colors.blue.withOpacity(0.3),
          strokeColor: Colors.blue,
          strokeWidth: 2,
        ),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Work Radius'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () {
              if (_center != null) {
                Navigator.pop(context, {
                  'center': _center,
                  'radius': _radius,
                });
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_center == null)
            const Center(child: CircularProgressIndicator())
          else
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _center!,
                zoom: 12,
              ),
              onMapCreated: (controller) => _mapController = controller,
              onTap: (latLng) {
                setState(() {
                  _center = latLng;
                  _updateMapElements();
                });
              },
              circles: _circles,
              markers: _markers,
            ),
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Radius: ${(_radius / 1000).toStringAsFixed(1)} km',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Slider(
                      value: _radius,
                      min: 1000,
                      max: 50000,
                      divisions: 49,
                      label: '${(_radius / 1000).toStringAsFixed(0)} km',
                      onChanged: (value) {
                        setState(() {
                          _radius = value;
                          _updateMapElements();
                        });
                      },
                    ),
                    const Text('Tap map to change center or drag marker'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
