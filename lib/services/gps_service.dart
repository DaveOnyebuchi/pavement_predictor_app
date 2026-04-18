import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class GpsService extends ChangeNotifier {
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  bool _isTracking = false;
  double _totalDistance = 0.0;
  Position? _lastPosition;
  
  Position? get currentPosition => _currentPosition;
  bool get isTracking => _isTracking;
  double get totalDistance => _totalDistance;
  
  Future<bool> requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }
  
  Future<void> startTracking() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return;
    
    _isTracking = true;
    _totalDistance = 0.0;
    _lastPosition = null;
    notifyListeners();
    
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        timeLimit: Duration(seconds: 1),
      ),
    ).listen((Position position) {
      if (_lastPosition != null) {
        final distance = Geolocator.distanceBetween(
          _lastPosition!.latitude, _lastPosition!.longitude,
          position.latitude, position.longitude
        );
        _totalDistance += distance;
      }
      
      _currentPosition = position;
      _lastPosition = position;
      notifyListeners();
    });
  }
  
  void stopTracking() {
    _positionStream?.cancel();
    _isTracking = false;
    notifyListeners();
  }
}