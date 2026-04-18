import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../services/gps_service.dart';
import '../services/api_service.dart';
import '../services/tts_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  LatLng? _currentLocation;
  List<LatLng>? _currentRoute;
  
  @override
  Widget build(BuildContext context) {
    final gpsService = Provider.of<GpsService>(context);
    final routeState = Provider.of<RouteState>(context);
    
    _currentLocation = gpsService.currentPosition != null
        ? LatLng(gpsService.currentPosition!.latitude, gpsService.currentPosition!.longitude)
        : null;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pavement Predictor'),
        actions: [
          IconButton(
            icon: Icon(gpsService.isTracking ? Icons.gps_fixed : Icons.gps_off),
            onPressed: () {
              if (gpsService.isTracking) {
                gpsService.stopTracking();
              } else {
                gpsService.startTracking();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showRoutePlanner(context),
          ),
        ],
      ),
      body: GoogleMap(
        onMapCreated: _onMapCreated,
        initialCameraPosition: const CameraPosition(
          target: LatLng(49.895, -97.138),
          zoom: 12,
        ),
        polylines: _polylines,
        markers: _markers,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
      ),
    );
  }
  
  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _loadPotholeSegments();
  }
  
  Future<void> _loadPotholeSegments() async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    try {
      final segments = await apiService.fetchSegments();
      final polylines = <Polyline>{};
      
      for (int i = 0; i < segments.length; i++) {
        final seg = segments[i];
        final coords = seg['coords'] as List<dynamic>;
        final color = seg['color'] as String;
        
        if (coords.length >= 2) {
          final latLngs = coords.map<LatLng>((c) => LatLng(c[0] as double, c[1] as double)).toList();
          polylines.add(Polyline(
            polylineId: PolylineId('segment_$i'),
            points: latLngs,
            color: color == '#ff0000' ? Colors.red : Colors.orange,
            width: 5,
          ));
        }
      }
      
      setState(() {
        _polylines = polylines;
      });
    } catch (e) {
      debugPrint('Error loading segments: $e');
    }
  }
  
  void _showRoutePlanner(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => RoutePlannerSheet(
        onRoutePlanned: (coordinates, instructions) {
          _drawRoute(coordinates);
          Provider.of<RouteState>(context, listen: false).setRoute(coordinates, instructions);
          Navigator.pop(context);
        },
      ),
    );
  }
  
  void _drawRoute(List<LatLng> coordinates) {
    if (coordinates.isEmpty) return;
    
    setState(() {
      _polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        points: coordinates,
        color: Colors.blue,
        width: 6,
      ));
    });
    
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(
      _getBoundsFromPoints(coordinates),
      50,
    ));
  }
  
  LatLngBounds _getBoundsFromPoints(List<LatLng> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    
    for (final point in points) {
      minLat = minLat < point.latitude ? minLat : point.latitude;
      maxLat = maxLat > point.latitude ? maxLat : point.latitude;
      minLng = minLng < point.longitude ? minLng : point.longitude;
      maxLng = maxLng > point.longitude ? maxLng : point.longitude;
    }
    
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }
}

class RoutePlannerSheet extends StatefulWidget {
  final Function(List<LatLng>, List<Map<String, dynamic>>) onRoutePlanned;
  
  const RoutePlannerSheet({super.key, required this.onRoutePlanned});
  
  @override
  State<RoutePlannerSheet> createState() => _RoutePlannerSheetState();
}

class _RoutePlannerSheetState extends State<RoutePlannerSheet> {
  final TextEditingController _destinationController = TextEditingController();
  final TextEditingController _startController = TextEditingController();
  bool _isLoading = false;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
    );
  }
  
  Future<void> _planRoute() async {
    if (_destinationController.text.isEmpty) return;
    
    setState(() => _isLoading = true);
    
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final gpsService = Provider.of<GpsService>(context, listen: false);
      
      double startLat, startLng;
      
      if (_startController.text.isNotEmpty) {
        final startCoords = await apiService.geocode(_startController.text);
        startLat = startCoords['lat'];
        startLng = startCoords['lon'];
      } else {
        final currentPos = gpsService.currentPosition;
        if (currentPos == null) {
          throw Exception('GPS not available. Please enter a start address.');
        }
        startLat = currentPos.latitude;
        startLng = currentPos.longitude;
      }
      
      final endCoords = await apiService.geocode(_destinationController.text);
      final endLat = endCoords['lat'];
      final endLng = endCoords['lon'];
      
      final routeData = await apiService.planRoute(startLat, startLng, endLat, endLng);
      
      if (routeData['code'] == 'Ok') {
        final coordinates = (routeData['coordinates'] as List<dynamic>)
            .map<LatLng>((c) => LatLng(c[0] as double, c[1] as double))
            .toList();
        
        final route = routeData['routes'][0];
        final steps = route['legs'][0]['steps'] as List<dynamic>;
        
        final instructions = steps.map((step) {
          return {
            'text': step['text'] ?? step['name'] ?? 'Continue',
            'distance': (step['distance'] ?? 0).toDouble(),
            'streetName': step['name'] ?? '',
          };
        }).toList();
        
        final instructionTexts = instructions.map((i) => i['text'] as String).toList();
        apiService.processRoute(coordinates, instructionTexts);
        
        widget.onRoutePlanned(coordinates, instructions);
        
        if (instructions.isNotEmpty) {
          final firstInst = instructions[0];
          TtsService.speak('Route planned. ${firstInst['distance'].round()} meters, ${firstInst['text']}');
        }
      } else {
        throw Exception('Route planning failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}