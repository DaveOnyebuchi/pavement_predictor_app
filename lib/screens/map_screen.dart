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
  String _debugMessage = "Initializing...";
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
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() => _debugMessage = "Loading: $url");
            debugPrint("Page started: $url");
          },
          onPageFinished: (String url) {
            setState(() => _debugMessage = "Loaded: $url");
            debugPrint("Page finished: $url");
            // Test if JavaScript works
            _controller.runJavaScript('console.log("Flutter: Page loaded");');
          },
          onWebResourceError: (WebResourceError error) {
            setState(() => _debugMessage = "Error: ${error.description}");
            debugPrint("WebView error: ${error.description}");
          },
        ),
      )
      ..loadRequest(Uri.parse('https://pavement.ainewsdaily.ca'));
  }
  Future<void> _testJavaScript() async {
    try {
      final result = await _controller.runJavaScriptReturningResult('''
        (function() {
          return {
            hasMap: typeof map !== 'undefined',
            hasMapbox: typeof mapboxgl !== 'undefined',
            url: window.location.href
          };
        })();
      ''');
      setState(() => _debugMessage = "JS Test: $result");
      debugPrint("JavaScript test result: $result");
    } catch (e) {
      setState(() => _debugMessage = "JS Error: $e");
      debugPrint("JavaScript error: $e");
    }
  }
  Future<void> _sendTestLocation() async {
    await _controller.runJavaScript('''
      console.log("Flutter: Sending test location");
      if (typeof map !== 'undefined' && map) {
        map.flyTo({
          center: [-97.138, 49.895],
          zoom: 14
        });
      }
    ''');
    setState(() => _debugMessage = "Sent test location to map");
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pavement Predictor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.code),
            onPressed: _testJavaScript,
          ),
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _sendTestLocation,
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.black87,
              child: Text(
                _debugMessage,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
