import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/map_screen.dart';
import 'services/gps_service.dart';
import 'services/api_service.dart';
import 'services/tts_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TtsService.init();
  runApp(const PavementPredictorApp());
}

class PavementPredictorApp extends StatelessWidget {
  const PavementPredictorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GpsService()),
        ChangeNotifierProvider(create: (_) => ApiService()),
        ChangeNotifierProvider(create: (_) => RouteState()),
      ],
      child: MaterialApp(
        title: 'Pavement Predictor',
        theme: ThemeData(
          primaryColor: const Color(0xFF0047AB),
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0047AB)),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0047AB),
            foregroundColor: Colors.white,
          ),
          useMaterial3: true,
        ),
        home: const MapScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class RouteState extends ChangeNotifier {
  List<Map<String, dynamic>>? instructions;
  int nextInstructionIndex = 0;
  double traveledDistance = 0.0;
  List<List<double>>? routeCoordinates;
  
  void setRoute(List<List<double>> coordinates, List<Map<String, dynamic>> instructions) {
    this.routeCoordinates = coordinates;
    this.instructions = instructions;
    nextInstructionIndex = 0;
    traveledDistance = 0.0;
    notifyListeners();
  }
  
  void updateTraveledDistance(double distance) {
    traveledDistance = distance;
    _checkNextInstruction();
    notifyListeners();
  }
  
  void _checkNextInstruction() {
    if (instructions == null || nextInstructionIndex >= instructions!.length) return;
    
    final nextInst = instructions![nextInstructionIndex];
    final double distToTurn = nextInst['distance'] - traveledDistance;
    
    if (distToTurn <= 200 && distToTurn > 20) {
      final direction = nextInst['text'].toLowerCase().contains('left') ? 'left' : 
                       (nextInst['text'].toLowerCase().contains('right') ? 'right' : '');
      final street = nextInst['streetName'] ?? 'the road';
      
      TtsService.speak('In ${distToTurn.round()} meters, turn $direction onto $street');
      nextInstructionIndex++;
    }
  }
  
  void reset() {
    instructions = null;
    nextInstructionIndex = 0;
    traveledDistance = 0.0;
    routeCoordinates = null;
    notifyListeners();
  }
}
