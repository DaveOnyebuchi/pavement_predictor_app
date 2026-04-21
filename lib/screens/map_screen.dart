import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
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
  MapboxMap? _mapboxMap;
  bool _isMapReady = false;
  double? _currentLat;
  double? _currentLng;
  bool _isTracking = false;
  List<dynamic> _segments = [];
  
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
      _currentLat = position.latitude;
      _currentLng = position.longitude;
    });
    
    if (_mapboxMap != null && _isMapReady && _currentLat != null) {
      _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(_currentLng!, _currentLat!)),
          zoom: 14,
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

  void _addSegmentsToMap() async {
    if (_mapboxMap == null || !_isMapReady) return;
    
    for (int i = 0; i < _segments.length; i++) {
      final segment = _segments[i];
      final coords = segment['coords'] as List;
      final color = segment['color'] == '#ff0000' ? 0xFFFF0000 : 0xFFFF8800;
      
      if (coords.length >= 2) {
        final positions = coords.map<Position>((c) => Position(c[1], c[0])).toList();
        
        // Add as a polyline using annotation API
        await _mapboxMap!.addPolyline(
          PolylineOptions(
            geometry: LineString(coordinates: positions),
            lineColor: color,
            lineWidth: 4,
          ),
        );
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
      } else if (_currentLat != null) {
        startLat = _currentLat!;
        startLng = _currentLng!;
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
            .map<Position>((c) => Position(c[1], c[0]))
            .toList();
        
        if (_mapboxMap != null && _isMapReady && coordinates.isNotEmpty) {
          await _mapboxMap!.addPolyline(
            PolylineOptions(
              geometry: LineString(coordinates: coordinates),
              lineColor: 0xFF0078FF,
              lineWidth: 6,
            ),
          );
          
          // Fit camera to route bounds
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
          
          _mapboxMap!.flyTo(
            CameraOptions(
              bounds: Bounds(
                southwest: Position(minLng, minLat),
                northeast: Position(maxLng, maxLat),
              ),
              padding: EdgeInsets.all(50),
            ),
          );
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
      setState(() {
        _currentLat = position.latitude;
        _currentLng = position.longitude;
      });
      
      if (_mapboxMap != null && _isMapReady && _isTracking && _currentLat != null) {
        _mapboxMap!.flyTo(
          CameraOptions(
            center: Point(coordinates: Position(_currentLng!, _currentLat!)),
            zoom: 15,
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
      body: MapWidget(
        key: const ValueKey('mapWidget'),
        onMapCreated: _onMapCreated,
        cameraOptions: CameraOptions(
          center: Point(coordinates: Position(-97.138, 49.895)),
          zoom: 12,
        ),
        styleUri: MapboxStyles.STREETS,
      ),
    );
  }
  
  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    _isMapReady = true;
    _addSegmentsToMap();
    
    // Enable user location on map
    mapboxMap.location.updateSettings(LocationComponentSettings(enabled: true));
  }
}
