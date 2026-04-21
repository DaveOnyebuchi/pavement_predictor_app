import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
// Token will be injected from local.properties at build time
// For local development, set MAPBOX_TOKEN environment variable
const String MAPBOX_TOKEN = String.fromEnvironment('MAPBOX_TOKEN', defaultValue: '');
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}
class _MapScreenState extends State<MapScreen> {
  mapbox.MapboxMap? _mapboxMap;
  bool _isMapReady = false;
  String _mapStatus = 'Initializing...';
  double? _currentLat;
  double? _currentLng;
  bool _isTracking = false;
  final TextEditingController _destinationController = TextEditingController();
  final TextEditingController _startController = TextEditingController();
  bool _isLoading = false;
  final FlutterTts _tts = FlutterTts();
  @override
  void initState() {
    super.initState();
    _initTts();
    _requestLocation();
    _checkToken();
  }
  void _checkToken() {
    if (MAPBOX_TOKEN.isEmpty) {
      setState(() => _mapStatus = 'ERROR: No Mapbox token. Set MAPBOX_TOKEN environment variable.');
    } else {
      setState(() => _mapStatus = 'Token present, loading map...');
      debugPrint('Token loaded (starts with: ${MAPBOX_TOKEN.substring(0, 10)}...)');
    }
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
    geo.LocationPermission permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }
    if (permission == geo.LocationPermission.deniedForever) {
      return;
    }
    final geo.Position position = await geo.Geolocator.getCurrentPosition();
    setState(() {
      _currentLat = position.latitude;
      _currentLng = position.longitude;
    });
    if (_mapboxMap != null && _isMapReady && _currentLat != null) {
      final mapbox.CameraOptions options = mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(_currentLng!, _currentLat!)
        ),
        zoom: 14.0,
      );
      final mapbox.MapAnimationOptions animation = mapbox.MapAnimationOptions(duration: 1000);
      _mapboxMap!.flyTo(options, animation);
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
        await _speak('Route planned successfully.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Route planned!')),
        );
        if (mounted) Navigator.pop(context);
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
      builder: (context) => SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
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
      ),
    );
  }
  void _startTracking() async {
    setState(() => _isTracking = true);
    await _requestLocation();
    geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen((geo.Position position) {
      setState(() {
        _currentLat = position.latitude;
        _currentLng = position.longitude;
      });
      if (_mapboxMap != null && _isMapReady && _isTracking && _currentLat != null) {
        final mapbox.CameraOptions options = mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(_currentLng!, _currentLat!)
          ),
          zoom: 15.0,
        );
        final mapbox.MapAnimationOptions animation = mapbox.MapAnimationOptions(duration: 500);
        _mapboxMap!.flyTo(options, animation);
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
      body: Stack(
        children: [
          mapbox.MapWidget(
            key: const ValueKey('mapWidget'),
            onMapCreated: _onMapCreated,
            cameraOptions: mapbox.CameraOptions(
              center: mapbox.Point(
                coordinates: mapbox.Position(-97.138, 49.895)
              ),
              zoom: 12.0,
            ),
            styleUri: 'mapbox://styles/mapbox/standard',
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.black54,
              child: Text(
                _mapStatus,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          if (!_isMapReady)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text('Loading map...'),
                ],
              ),
            ),
        ],
      ),
    );
  }
  void _onMapCreated(mapbox.MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    _isMapReady = true;
    setState(() => _mapStatus = '✅ Map loaded!');
    debugPrint('✅ Map created successfully!');
    mapboxMap.location.updateSettings(
      mapbox.LocationComponentSettings(enabled: true)
    );
  }
}
