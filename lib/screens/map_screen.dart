import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}
class _MapScreenState extends State<MapScreen> {
  late final WebViewController _controller;
  bool _isTracking = false;
  double _currentZoom = 12.0;
  StreamSubscription<Position>? _positionStream;
  final FlutterTts _tts = FlutterTts();
  @override
  void initState() {
    super.initState();
    _initTts();
    _initWebView();
  }
  Future<void> _initTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.9);
  }
  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'PavementApp',
        onMessageReceived: (JavaScriptMessage message) {
          debugPrint('Message from web: ${message.message}');
          if (message.message.contains('Route planned')) {
            _tts.speak('Route planned successfully.');
          }
        },
      )
      ..loadRequest(Uri.parse('https://pavement.ainewsdaily.ca'));
  }
  Future<void> _sendLocationToWeb(double lat, double lng) async {
    await _controller.runJavaScript('''
      if (typeof updateNativeLocation === 'function') {
        updateNativeLocation($lat, $lng);
      } else {
        console.log('Native location:', $lat, $lng);
        window.nativeLat = $lat;
        window.nativeLng = $lng;
      }
    ''');
  }
  Future<void> _startTracking() async {
    setState(() => _isTracking = true);
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission denied')),
      );
      setState(() => _isTracking = false);
      return;
    }
    final position = await Geolocator.getCurrentPosition();
    await _sendLocationToWeb(position.latitude, position.longitude);
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen((Position position) async {
      await _sendLocationToWeb(position.latitude, position.longitude);
      if (_isTracking) {
        await _controller.runJavaScript('''
          if (typeof map !== 'undefined' && map && map.flyTo) {
            map.flyTo({
              center: [${position.longitude}, ${position.latitude}],
              zoom: ${_currentZoom.toInt()},
              duration: 500
            });
          }
        ''');
      }
    });
  }
  void _stopTracking() {
    setState(() => _isTracking = false);
    _positionStream?.cancel();
  }
  Future<void> _zoomIn() async {
    _currentZoom = (_currentZoom + 1).clamp(1, 20);
    await _controller.runJavaScript('''
      if (typeof map !== 'undefined' && map && map.zoomIn) {
        map.zoomIn();
      } else if (typeof map !== 'undefined' && map && map.setZoom) {
        map.setZoom(${_currentZoom.toInt()});
      }
    ''');
  }
  Future<void> _zoomOut() async {
    _currentZoom = (_currentZoom - 1).clamp(1, 20);
    await _controller.runJavaScript('''
      if (typeof map !== 'undefined' && map && map.zoomOut) {
        map.zoomOut();
      } else if (typeof map !== 'undefined' && map && map.setZoom) {
        map.setZoom(${_currentZoom.toInt()});
      }
    ''');
  }
  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
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
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          Positioned(
            bottom: 20,
            right: 20,
            child: Column(
              children: [
                FloatingActionButton(
                  heroTag: 'zoomIn',
                  onPressed: _zoomIn,
                  mini: true,
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: 'zoomOut',
                  onPressed: _zoomOut,
                  mini: true,
                  child: const Icon(Icons.remove),
                ),
              ],
            ),
          ),
          if (_isTracking)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'GPS Active',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
