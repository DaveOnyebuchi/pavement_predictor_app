import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class ApiService extends ChangeNotifier {
  final String baseUrl = 'https://pavement.ainewsdaily.ca';
  
  Future<List<Map<String, dynamic>>> fetchSegments() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/segments'));
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      throw Exception('Failed to load segments');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
  
  Future<Map<String, dynamic>> geocode(String address) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/geocode'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'address': address}),
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      throw Exception('Geocoding failed');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
  
  Future<Map<String, dynamic>> planRoute(double startLat, double startLng, double endLat, double endLng) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/proxy-route'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'start': [startLat, startLng],
          'end': [endLat, endLng],
        }),
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      throw Exception('Route planning failed');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
  
  Future<void> processRoute(List<LatLng> coordinates, List<String> instructions) async {
    try {
      final coordsList = coordinates.map((c) => [c.latitude, c.longitude]).toList();
      await http.post(
        Uri.parse('$baseUrl/process-route'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'coordinates': coordsList,
          'instructions': instructions,
        }),
      );
    } catch (e) {
      // Silent fail - non-critical
    }
  }
}