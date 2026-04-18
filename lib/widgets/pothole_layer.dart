import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class PotholeLayer {
  static Future<void> addToMap(MapboxMap map, List<Map<String, dynamic>> segments) async {
    final redFeatures = <Feature>[];
    final orangeFeatures = <Feature>[];
    
    for (final segment in segments) {
      final coords = segment['coords'] as List<dynamic>;
      final color = segment['color'] as String;
      
      if (coords.length < 2) continue;
      
      final positions = <Position>[];
      for (final coord in coords) {
        positions.add(Position(coord[1] as double, coord[0] as double));
      }
      
      final geometry = LineString(coordinates: positions);
      final feature = Feature(geometry: geometry);
      
      if (color == '#ff0000') {
        redFeatures.add(feature);
      } else if (color == '#ff8800') {
        orangeFeatures.add(feature);
      }
    }
    
    // Add red segments
    if (redFeatures.isNotEmpty) {
      try {
        final redSource = GeoJsonSource(id: 'pothole-red-source', features: redFeatures);
        await map.addSource(redSource);
        
        final redLayer = LineLayer(
          id: 'pothole-red-layer',
          sourceId: 'pothole-red-source',
          lineColor: 0xFF0000,
          lineWidth: 4,
          lineOpacity: 0.7,
        );
        await map.addLayer(redLayer);
      } catch (e) {
        debugPrint('Error adding red segments: $e');
      }
    }
    
    // Add orange segments
    if (orangeFeatures.isNotEmpty) {
      try {
        final orangeSource = GeoJsonSource(id: 'pothole-orange-source', features: orangeFeatures);
        await map.addSource(orangeSource);
        
        final orangeLayer = LineLayer(
          id: 'pothole-orange-layer',
          sourceId: 'pothole-orange-source',
          lineColor: 0xFF8800,
          lineWidth: 4,
          lineOpacity: 0.7,
        );
        await map.addLayer(orangeLayer);
      } catch (e) {
        debugPrint('Error adding orange segments: $e');
      }
    }
  }
}