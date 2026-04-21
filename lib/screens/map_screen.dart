import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mapbox_gl/mapbox_gl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/api_service.dart';
import '../services/gps_service.dart';
import '../services/tts_service.dart';

const String MAPBOX_TOKEN = 'pk.eyJ1IjoiNzkxOTYxMSIsImEiOiJjbW8zd3kzbXgxYjVmMnBwdWZnemF3NWhlIn0.nPTx4At6TJEiNe7xlU4YkQ';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapboxMapController? _mapController;
  LatLng? _currentLocation;
  bool _isTracking = false;
  List<dynamic> _segments = [];
  List<LatLng> _routeCoordinates = [];
  
  final TextEditingController _destinationController = TextEditingController();
  final TextEditingController _startController = TextEditingController();
  bool _isLoading = false;
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadSegments();
    _requestLocation();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.9);
  }

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _requestLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return;
    }
    
    final position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentLocation = LatLng(position.latitude, position.longitude);
    });
    
    if (_mapController != null && _currentLocation != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _currentLocation!, zoom: 14),
        ),
      );
    }
  }

  Future<void> _loadSegments() async {
    try {
      final response = await http.get(
        Uri.parse('https://pavement.ainewsdaily.ca/api/segments'),
      );
      if (response.statusCode == 200) {
        setState(() {
          _segments = json.decode(response.body);
        });
        _addSegmentsToMap();
      }
    } catch (e) {
      debugPrint('Error loading segments: $e');
    }
  }

  void _addSegmentsToMap() {
    if (_mapController == null) return;
    
    for (int i = 0; i < _segments.length; i++) {
      final segment = _segments[i];
      final coords = segment['coords'] as List;
      final color = segment['color'] == '#ff0000' ? '#FF0000' : '#FF8800';
      
      if (coords.length >= 2) {
        final points = coords.map<LatLng>((c) => LatLng(c[0], c[1])).toList();
        
        _mapController!.addLine(LineOptions(
          geometry: points,
          lineColor: color,
          lineWidth: 4,
          lineOpacity: 0.8,
        ));
      }
    }
  }

  Future<void> _planRoute() async {
    if (_destinationController.text.isEmpty) return;
    
    setState(() => _isLoading = true);
    
    try {
      double startLat, startLng;
      
      if (_startController.text.isNotEmpty) {
        final startResponse = await http.post(
          Uri.parse('https://pavement.ainewsdaily.ca/geocode'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'address': _startController.text}),
        );
        final startData = json.decode(startResponse.body);
        startLat = startData['lat'];
        startLng = startData['lon'];
      } else if (_currentLocation != null) {
        startLat = _currentLocation!.latitude;
        startLng = _currentLocation!.longitude;
      } else {
        throw Exception('No start location available');
      }
      
      final endResponse = await http.post(
        Uri.parse('https://pavement.ainewsdaily.ca/geocode'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'address': _destinationController.text}),
      );
      final endData = json.decode(endResponse.body);
      final endLat = endData['lat'];
      final endLng = endData['lon'];
      
      final routeResponse = await http.post(
        Uri.parse('https://pavement.ainewsdaily.ca/proxy-route'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'start': [startLat, startLng],
          'end': [endLat, endLng],
        }),
      );
      final routeData = json.decode(routeResponse.body);
      
      if (routeData['code'] == 'Ok') {
        final coordinates = (routeData['coordinates'] as List)
            .map<LatLng>((c) => LatLng(c[0], c[1]))
            .toList();
        
        setState(() => _routeCoordinates = coordinates);
        
        if (_mapController != null && coordinates.isNotEmpty) {
          _mapController!.addLine(LineOptions(
            geometry: coordinates,
            lineColor: '#0078FF',
            lineWidth: 6,
            lineOpacity: 0.9,
          ));
          
          double minLat = coordinates.first.latitude;
          double maxLat = coordinates.first.latitude;
          double minLng = coordinates.first.longitude;
          double maxLng = coordinates.first.longitude;
          
          for (final point in coordinates) {
            minLat = minLat < point.latitude ? minLat : point.latitude;
            maxLat = maxLat > point.latitude ? maxLat : point.latitude;
            minLng = minLng < point.longitude ? minLng : point.longitude;
            maxLng = maxLng > point.longitude ? maxLng : point.longitude;
          }
          
          _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(minLat, minLng),
              northeast: LatLng(maxLat, maxLng),
            ),
            50,
          ));
        }
        
        await _speak('Route planned. Follow the blue line on the map.');
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showRoutePlanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Plan Your Route', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(
              controller: _startController,
              decoration: const InputDecoration(
                labelText: 'Start (optional)',
                prefixIcon: Icon(Icons.my_location),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _destinationController,
              decoration: const InputDecoration(
                labelText: 'Destination *',
                prefixIcon: Icon(Icons.location_on),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isLoading ? null : _planRoute,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0047AB),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Plan Route', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  void _startTracking() async {
    setState(() => _isTracking = true);
    await _requestLocation();
    
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      final newLocation = LatLng(position.latitude, position.longitude);
      setState(() => _currentLocation = newLocation);
      
      if (_mapController != null && _isTracking) {
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: newLocation, zoom: 15),
          ),
        );
      }
    });
  }

  void _stopTracking() {
    setState(() => _isTracking = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pavement Predictor'),
        actions: [
          IconButton(
            icon: Icon(_isTracking ? Icons.gps_fixed : Icons.gps_off),
            onPressed: _isTracking ? _stopTracking : _startTracking,
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _showRoutePlanner,
          ),
        ],
      ),
      body: MapboxMap(
        accessToken: MAPBOX_TOKEN,
        onMapCreated: (controller) {
          _mapController = controller;
          _addSegmentsToMap();
          if (_currentLocation != null) {
            controller.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(target: _currentLocation!, zoom: 14),
              ),
            );
          }
        },
        initialCameraPosition: const CameraPosition(
          target: LatLng(49.895, -97.138),
          zoom: 12,
        ),
        compassEnabled: true,
        myLocationEnabled: _isTracking,
        myLocationTrackingMode: _isTracking 
            ? MyLocationTrackingMode.Tracking
            : MyLocationTrackingMode.None,
      ),
    );
  }
}
